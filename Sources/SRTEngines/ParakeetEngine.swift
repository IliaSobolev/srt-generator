import FluidAudio
import Foundation
import SRTCore

/// Stores and loads NVIDIA Parakeet TDT 0.6B (v2: English, v3: 25 European languages) via FluidAudio.
public struct ParakeetProvider: ModelProvider {
    public init() {}

    static func version(_ model: SRTCore.ModelInfo) -> AsrModelVersion {
        model.id.hasSuffix("v2") ? .v2 : .v3
    }

    public func folder(for model: SRTCore.ModelInfo) -> URL {
        AsrModels.defaultCacheDirectory(for: Self.version(model))
    }

    public func isDownloaded(_ model: SRTCore.ModelInfo) -> Bool {
        AsrModels.modelsExist(at: folder(for: model), version: Self.version(model))
    }

    public func download(_ model: SRTCore.ModelInfo, progress: @escaping SRTCore.ProgressHandler) async throws {
        _ = try await AsrModels.download(version: Self.version(model)) { p in progress(p.fractionCompleted) }
    }

    public func delete(_ model: SRTCore.ModelInfo) throws {
        try FileManager.default.removeItem(at: folder(for: model))
    }

    public func load(_ model: SRTCore.ModelInfo, compute: ComputeTarget) async throws -> any SpeechEngine {
        let version = Self.version(model)
        let models = try await AsrModels.load(
            from: folder(for: model), version: version, encoderComputeUnits: compute == .gpu ? .cpuAndGPU : nil)
        let manager = AsrManager()
        try await manager.loadModels(models)
        return ParakeetEngine(manager: manager, englishOnly: version == .v2)
    }
}

struct ParakeetEngine: SpeechEngine {
    let manager: AsrManager
    let englishOnly: Bool

    func transcribe(samples: [Float], request: TranscriptionRequest, progress: @escaping SRTCore.ProgressHandler)
        async throws -> EngineResult
    {
        let progressTask = Task {
            do { for try await p in await manager.transcriptionProgressStream { progress(p) } } catch {}
        }
        defer { progressTask.cancel() }

        var state = TdtDecoderState.make()
        let hint = request.language.flatMap(Language.init(rawValue:))
        let result = try await manager.transcribe(samples, decoderState: &state, language: hint)

        let words = buildWordTimings(from: result.tokenTimings ?? []).map {
            TimedWord(text: " " + $0.word, start: $0.startTime, end: $0.endTime)
        }
        let language = request.language ?? (englishOnly ? "en" : Languages.detect(in: result.text))
        let segments = SpeechSegment.group(words, fallbackText: result.text, duration: result.duration)
        return EngineResult(segments: segments, language: language)
    }
}

/// Live model registry for the app and CLI.
public enum LiveEngines {
    public static func registry() -> SRTCore.ModelRegistry {
        SRTCore.ModelRegistry(whisper: WhisperProvider(), parakeet: ParakeetProvider())
    }
}
