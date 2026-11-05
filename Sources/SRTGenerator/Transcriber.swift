import CoreML
import Foundation
import WhisperKit

/// Owns local model storage and the currently loaded speech engine.
actor Transcriber {
    static let storageRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SRTGenerator", isDirectory: true)
    }()

    // MARK: Storage

    static func whisperFolder(_ model: ModelInfo) -> URL {
        storageRoot.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model.whisperVariant ?? model.id)",
                                           isDirectory: true)
    }

    static func modelFolder(_ model: ModelInfo) -> URL {
        switch model.engine {
        case .whisper: whisperFolder(model)
        case .parakeet: ParakeetStore.folder(model)
        }
    }

    static func isDownloaded(_ model: ModelInfo) -> Bool {
        switch model.engine {
        case .whisper:
            let folder = whisperFolder(model)
            return ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"].allSatisfy {
                FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
            }
        case .parakeet:
            return ParakeetStore.isDownloaded(model)
        }
    }

    static func delete(_ model: ModelInfo) throws {
        switch model.engine {
        case .whisper: try FileManager.default.removeItem(at: whisperFolder(model))
        case .parakeet: try ParakeetStore.delete(model)
        }
    }

    static func download(_ model: ModelInfo, progress: @escaping @Sendable (Double) -> Void) async throws {
        switch model.engine {
        case .whisper:
            try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
            _ = try await WhisperKit.download(variant: model.whisperVariant ?? model.id, downloadBase: storageRoot) { p in
                progress(p.fractionCompleted)
            }
        case .parakeet:
            try await ParakeetStore.download(model, progress: progress)
        }
    }

    // MARK: Loading

    private var whisper: WhisperKit?
    private var parakeet: ParakeetEngine?
    private var loadedModel: ModelInfo?
    private var loadedCompute: ComputeTarget?

    var isLoaded: Bool { whisper != nil || parakeet != nil }

    func load(_ model: ModelInfo, compute: ComputeTarget) async throws {
        if loadedModel == model, loadedCompute == compute, isLoaded { return }
        unload()
        switch model.engine {
        case .whisper:
            let units: MLComputeUnits = compute == .gpu ? .cpuAndGPU : .cpuAndNeuralEngine
            let config = WhisperKitConfig(
                modelFolder: Self.whisperFolder(model).path,
                tokenizerFolder: Self.storageRoot,
                computeOptions: ModelComputeOptions(audioEncoderCompute: units, textDecoderCompute: units),
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: true,
                download: false
            )
            whisper = try await WhisperKit(config)
        case .parakeet:
            parakeet = try await ParakeetEngine.load(model, compute: compute)
        }
        loadedModel = model
        loadedCompute = compute
    }

    func unload() {
        whisper = nil
        parakeet = nil
        loadedModel = nil
        loadedCompute = nil
    }

    // MARK: Transcription

    struct Output: Sendable {
        var cues: [SubtitleCue]
        var language: String
    }

    /// - Parameters:
    ///   - language: ISO code, or nil for auto-detect.
    ///   - translate: Whisper's built-in X → English translation (ignored by other engines).
    func transcribe(
        samples: [Float],
        language: String?,
        translate: Bool,
        settings: TranscriptionSettings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Output {
        let builder = settings.cueBuilder
        if let parakeet {
            let result = try await parakeet.transcribe(samples: samples, language: language, progress: progress)
            return Output(cues: builder.build(result.segments), language: result.language)
        }
        guard let whisper else { throw CocoaError(.featureUnsupported) }
        let duration = Double(samples.count) / Double(AudioLoader.sampleRate)

        // Custom words are fed to Whisper as an initial prompt to bias spelling.
        var promptTokens: [Int]?
        let words = settings.customWords.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !words.isEmpty, let tokenizer = whisper.tokenizer {
            promptTokens = tokenizer.encode(text: " " + words.joined(separator: ", "))
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }

        let options = DecodingOptions(
            task: translate ? .translate : .transcribe,
            language: language,
            temperatureFallbackCount: settings.whisperTemperatureFallback ? 3 : 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            wordTimestamps: true,
            promptTokens: promptTokens,
            suppressBlank: settings.whisperSuppressNonSpeech,
            noSpeechThreshold: settings.whisperSuppressNonSpeech ? 0.6 : nil,
            chunkingStrategy: settings.whisperVAD ? .vad : ChunkingStrategy.none
        )

        let tracker = ProgressTracker(duration: duration, report: progress)
        let results = try await whisper.transcribe(
            audioArray: samples,
            decodeOptions: options,
            callback: { _ in Task.isCancelled ? false : nil },
            segmentCallback: { segments in tracker.update(segments.map { Double($0.end) }) }
        )
        try Task.checkCancellation()

        let segments = results.flatMap(\.segments).sorted { $0.start < $1.start }.map { seg in
            SpeechSegment(
                start: Double(seg.start), end: Double(seg.end), text: seg.text,
                words: seg.words?.map { TimedWord(text: $0.word, start: Double($0.start), end: Double($0.end)) }
            )
        }
        let lang = results.first?.language ?? language ?? "en"
        return Output(cues: builder.build(segments), language: lang)
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

    func update(_ ends: [Double]) {
        guard duration > 0, let end = ends.max() else { return }
        lock.lock()
        // VAD chunks run concurrently with chunk-relative times, so this is an approximation.
        maxEnd = max(maxEnd, end)
        let value = min(0.99, maxEnd / duration)
        lock.unlock()
        report(value)
    }
}
