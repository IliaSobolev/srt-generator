import FluidAudio
import Foundation
import NaturalLanguage

/// NVIDIA Parakeet TDT 0.6B (v2: English, v3: 25 European languages) on CoreML via FluidAudio.
enum ParakeetStore {
    static func version(_ model: ModelInfo) -> AsrModelVersion {
        model.id.hasSuffix("v2") ? .v2 : .v3
    }

    static func folder(_ model: ModelInfo) -> URL {
        AsrModels.defaultCacheDirectory(for: version(model))
    }

    static func isDownloaded(_ model: ModelInfo) -> Bool {
        AsrModels.modelsExist(at: folder(model), version: version(model))
    }

    static func download(_ model: ModelInfo, progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await AsrModels.download(version: version(model)) { p in progress(p.fractionCompleted) }
    }

    static func delete(_ model: ModelInfo) throws {
        try FileManager.default.removeItem(at: folder(model))
    }
}

actor ParakeetEngine {
    private let manager: AsrManager
    private let model: ModelInfo

    private init(manager: AsrManager, model: ModelInfo) {
        self.manager = manager
        self.model = model
    }

    static func load(_ model: ModelInfo) async throws -> ParakeetEngine {
        let version = ParakeetStore.version(model)
        let models = try await AsrModels.load(from: ParakeetStore.folder(model), version: version)
        let manager = AsrManager()
        try await manager.loadModels(models)
        return ParakeetEngine(manager: manager, model: model)
    }

    /// - Parameter language: ISO code hint (v3 only), or nil.
    func transcribe(
        samples: [Float],
        language: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (segments: [SpeechSegment], language: String) {
        let progressTask = Task {
            do {
                for try await p in await manager.transcriptionProgressStream { progress(p) }
            } catch {}
        }
        defer { progressTask.cancel() }

        var state = TdtDecoderState.make()
        let hint = language.flatMap(Language.init(rawValue:))
        let result = try await manager.transcribe(samples, decoderState: &state, language: hint)
        try Task.checkCancellation()

        let words = buildWordTimings(from: result.tokenTimings ?? []).map {
            TimedWord(text: " " + $0.word, start: $0.startTime, end: $0.endTime)
        }
        let detected = language ?? Self.detectLanguage(result.text, english: ParakeetStore.version(model) == .v2)
        return (Self.segments(from: words, fallbackText: result.text, duration: result.duration), detected)
    }

    /// Splits the continuous word stream into segments at pauses longer than 0.8 s.
    private static func segments(from words: [TimedWord], fallbackText: String, duration: Double) -> [SpeechSegment] {
        guard !words.isEmpty else {
            let text = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [SpeechSegment(start: 0, end: duration, text: text)]
        }
        var result: [SpeechSegment] = []
        var run: [TimedWord] = []
        func flush() {
            guard let first = run.first, let last = run.last else { return }
            result.append(SpeechSegment(start: first.start, end: last.end, text: run.map(\.text).joined(), words: run))
            run.removeAll()
        }
        for word in words {
            if let last = run.last, word.start - last.end > 0.8 { flush() }
            run.append(word)
        }
        flush()
        return result
    }

    private static func detectLanguage(_ text: String, english: Bool) -> String {
        if english { return "en" }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }
}
