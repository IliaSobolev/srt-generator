import Foundation
import WhisperKit

/// Owns local model storage and the loaded WhisperKit pipeline.
actor Transcriber {
    static let storageRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SRTGenerator", isDirectory: true)
    }()

    static func modelFolder(_ model: ModelInfo) -> URL {
        storageRoot.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model.whisperVariant ?? model.id)",
                                           isDirectory: true)
    }

    static func isDownloaded(_ model: ModelInfo) -> Bool {
        let folder = modelFolder(model)
        return ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    static func delete(_ model: ModelInfo) throws {
        try FileManager.default.removeItem(at: modelFolder(model))
    }

    static func download(_ model: ModelInfo, progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
        _ = try await WhisperKit.download(variant: model.whisperVariant ?? model.id, downloadBase: storageRoot) { p in
            progress(p.fractionCompleted)
        }
    }

    private var pipe: WhisperKit?
    private var loadedModel: ModelInfo?

    func load(_ model: ModelInfo) async throws {
        if loadedModel == model, pipe != nil { return }
        pipe = nil
        let config = WhisperKitConfig(
            modelFolder: Self.modelFolder(model).path,
            tokenizerFolder: Self.storageRoot,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        pipe = try await WhisperKit(config)
        loadedModel = model
    }

    struct Output: Sendable {
        var cues: [SubtitleCue]
        var language: String
    }

    /// - Parameters:
    ///   - language: ISO code, or nil for auto-detect.
    ///   - translate: Whisper's built-in X → English translation.
    func transcribe(
        samples: [Float],
        language: String?,
        translate: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Output {
        guard let pipe else { throw CocoaError(.featureUnsupported) }
        let duration = Double(samples.count) / Double(AudioLoader.sampleRate)

        let options = DecodingOptions(
            task: translate ? .translate : .transcribe,
            language: language,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            wordTimestamps: true,
            chunkingStrategy: .vad
        )

        let tracker = ProgressTracker(duration: duration, report: progress)
        let results = try await pipe.transcribe(
            audioArray: samples,
            decodeOptions: options,
            callback: { _ in Task.isCancelled ? false : nil },
            segmentCallback: { segments in tracker.update(segments) }
        )
        try Task.checkCancellation()

        let segments = results.flatMap(\.segments).sorted { $0.start < $1.start }
        let lang = results.first?.language ?? language ?? "en"
        return Output(cues: CueBuilder.build(segments), language: lang)
    }
}

private final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var maxEnd: Double = 0
    let duration: Double
    let report: @Sendable (Double) -> Void

    init(duration: Double, report: @escaping @Sendable (Double) -> Void) {
        self.duration = duration
        self.report = report
    }

    func update(_ segments: [TranscriptionSegment]) {
        guard duration > 0, let end = segments.map({ Double($0.end) }).max() else { return }
        lock.lock()
        // VAD chunks run concurrently with chunk-relative times, so this is an approximation.
        maxEnd = max(maxEnd, end)
        let value = min(0.99, maxEnd / duration)
        lock.unlock()
        report(value)
    }
}

/// Turns Whisper segments into readable subtitle cues (≤ ~2 lines, ≤ ~7 s each).
enum CueBuilder {
    static let maxChars = 84
    static let maxDuration = 7.0

    static func build(_ segments: [TranscriptionSegment]) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for seg in segments {
            let text = clean(seg.text)
            guard !text.isEmpty else { continue }
            let tooLong = text.count > maxChars || Double(seg.end - seg.start) > maxDuration
            if tooLong, let words = seg.words, words.count > 1 {
                cues.append(contentsOf: split(words))
            } else {
                cues.append(SubtitleCue(start: Double(seg.start), end: Double(seg.end), text: text))
            }
        }
        // Enforce monotonic, non-overlapping, non-zero-length timing.
        var fixed: [SubtitleCue] = []
        for var cue in cues {
            if let prev = fixed.last, cue.start < prev.end { cue.start = prev.end }
            if cue.end <= cue.start + 0.2 { cue.end = cue.start + max(0.5, Double(cue.text.count) * 0.05) }
            cue.text = SRTWriter.wrap(cue.text)
            fixed.append(cue)
        }
        // Pull back any end time that now overlaps the following cue.
        for i in fixed.indices.dropLast() where fixed[i].end > fixed[i + 1].start {
            fixed[i].end = max(fixed[i].start + 0.1, fixed[i + 1].start)
        }
        return fixed
    }

    private static func split(_ words: [WordTiming]) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var current: [WordTiming] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = clean(current.map(\.word).joined())
            if !text.isEmpty {
                cues.append(SubtitleCue(start: Double(first.start), end: Double(last.end), text: text))
            }
            current.removeAll()
        }

        for word in words {
            if let first = current.first {
                let text = (current.map(\.word).joined() + word.word)
                let wouldOverflow = text.trimmingCharacters(in: .whitespaces).count > maxChars
                    || Double(word.end - first.start) > maxDuration
                if wouldOverflow { flush() }
            }
            current.append(word)
            // Prefer breaking at sentence ends once the cue has some substance.
            let w = word.word.trimmingCharacters(in: .whitespaces)
            if let last = w.last, ".!?。！？".contains(last),
               current.map(\.word).joined().count > maxChars / 3 {
                flush()
            }
        }
        flush()
        return cues
    }

    static func clean(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
