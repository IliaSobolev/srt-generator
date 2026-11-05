import Foundation

public enum TranscriptionError: LocalizedError, Equatable {
    case modelNotLoaded
    case alreadyDownloading(String)
    case downloadIncomplete(String)
    case noSpeech

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "No model is loaded."
        case .alreadyDownloading(let name): "\(name) is still downloading."
        case .downloadIncomplete(let name): "\(name) did not finish downloading. Please try again."
        case .noSpeech: "No speech detected."
        }
    }
}

public struct TranscriptionOutput: Sendable, Equatable {
    public var cues: [SubtitleCue]
    public var language: String
}

/// Keeps one speech engine loaded and turns its output into subtitle cues.
public actor TranscriptionService {
    private let registry: ModelRegistry
    private var engine: (any SpeechEngine)?
    private var loadedModelID: String?
    private var loadedCompute: ComputeTarget?

    public init(registry: ModelRegistry) {
        self.registry = registry
    }

    public var isLoaded: Bool { engine != nil }

    public func load(_ model: ModelInfo, compute: ComputeTarget) async throws {
        if loadedModelID == model.id, loadedCompute == compute, engine != nil { return }
        unload()
        engine = try await registry.provider(for: model).load(model, compute: compute)
        loadedModelID = model.id
        loadedCompute = compute
    }

    public func unload() {
        engine = nil
        loadedModelID = nil
        loadedCompute = nil
    }

    public func transcribe(
        samples: [Float], request: TranscriptionRequest, progress: @escaping ProgressHandler
    ) async throws -> TranscriptionOutput {
        guard let engine else { throw TranscriptionError.modelNotLoaded }
        let result = try await engine.transcribe(samples: samples, request: request, progress: progress)
        try Task.checkCancellation()
        return TranscriptionOutput(cues: request.settings.cueBuilder.build(result.segments), language: result.language)
    }
}
