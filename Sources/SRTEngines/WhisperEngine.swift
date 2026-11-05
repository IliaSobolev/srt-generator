import CoreML
import Foundation
import SRTCore
import WhisperKit

/// Stores and loads OpenAI Whisper models (CoreML builds from argmaxinc/whisperkit-coreml).
public struct WhisperProvider: ModelProvider {
    public let storageRoot: URL

    public init(storageRoot: URL = WhisperProvider.defaultStorageRoot) {
        self.storageRoot = storageRoot
    }

    public static let defaultStorageRoot: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SRTGenerator", isDirectory: true)

    /// Spoken-language table (`name → ISO code`) supported by Whisper.
    public static var languageTable: [String: String] { Constants.languages }

    public func folder(for model: SRTCore.ModelInfo) -> URL {
        storageRoot.appendingPathComponent(
            "models/argmaxinc/whisperkit-coreml/\(model.whisperVariant ?? model.id)", isDirectory: true)
    }

    public func isDownloaded(_ model: SRTCore.ModelInfo) -> Bool {
        let folder = folder(for: model)
        return ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    public func download(_ model: SRTCore.ModelInfo, progress: @escaping SRTCore.ProgressHandler) async throws {
        try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
        _ = try await WhisperKit.download(variant: model.whisperVariant ?? model.id, downloadBase: storageRoot) { p in
            progress(p.fractionCompleted)
        }
    }

    public func delete(_ model: SRTCore.ModelInfo) throws {
        try FileManager.default.removeItem(at: folder(for: model))
    }

    public func load(_ model: SRTCore.ModelInfo, compute: ComputeTarget) async throws -> any SpeechEngine {
        let units: MLComputeUnits = compute == .gpu ? .cpuAndGPU : .cpuAndNeuralEngine
        let config = WhisperKitConfig(
            modelFolder: folder(for: model).path,
            tokenizerFolder: storageRoot,
            computeOptions: ModelComputeOptions(audioEncoderCompute: units, textDecoderCompute: units),
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        return WhisperEngine(pipe: try await WhisperKit(config))
    }
}

final class WhisperEngine: SpeechEngine, @unchecked Sendable {
    // WhisperKit is not Sendable; SRTCore's TranscriptionService actor serializes access.
    private let pipe: WhisperKit

    init(pipe: WhisperKit) { self.pipe = pipe }

    func transcribe(samples: [Float], request: TranscriptionRequest, progress: @escaping SRTCore.ProgressHandler)
        async throws -> EngineResult
    {
        let settings = request.settings
        var promptTokens: [Int]?
        if let prompt = CueBuilder.customWordsPrompt(settings.customWords), let tokenizer = pipe.tokenizer {
            promptTokens = tokenizer.encode(text: prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        let options = DecodingOptions(
            task: request.translate ? .translate : .transcribe,
            language: request.language,
            temperatureFallbackCount: settings.whisperTemperatureFallback ? 3 : 0,
            usePrefillPrompt: true,
            detectLanguage: request.language == nil,
            skipSpecialTokens: true,
            wordTimestamps: true,
            promptTokens: promptTokens,
            suppressBlank: settings.whisperSuppressNonSpeech,
            noSpeechThreshold: settings.whisperSuppressNonSpeech ? 0.6 : nil,
            chunkingStrategy: settings.whisperVAD ? .vad : ChunkingStrategy.none
        )
        let tracker = ProgressTracker(
            duration: Double(samples.count) / Double(AudioLoader.sampleRate), report: progress)
        let results = try await pipe.transcribe(
            audioArray: samples,
            decodeOptions: options,
            callback: { _ in Task.isCancelled ? false : nil },
            segmentCallback: { segments in tracker.update(segments.map { Double($0.end) }) }
        )
        let segments = results.flatMap(\.segments).sorted { $0.start < $1.start }.map { seg in
            SpeechSegment(
                start: Double(seg.start), end: Double(seg.end), text: seg.text,
                words: seg.words?.map { TimedWord(text: $0.word, start: Double($0.start), end: Double($0.end)) })
        }
        return EngineResult(segments: segments, language: results.first?.language ?? request.language ?? "en")
    }
}
