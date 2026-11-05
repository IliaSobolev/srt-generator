import Foundation

public struct Job: Identifiable, Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case queued
        case downloadingModel(Double)
        case loadingModel
        case decoding
        case transcribing(Double)
        case translating(String)
        case done
        case failed(String)
        case cancelled

        public var isFinished: Bool {
            switch self {
            case .done, .failed, .cancelled: true
            default: false
            }
        }

        /// Failed and stopped jobs go back into the queue on the next run.
        public var isRetryable: Bool {
            switch self {
            case .failed, .cancelled: true
            default: false
            }
        }
    }

    public let id: UUID
    public let url: URL
    public var status: Status = .queued
    public var outputs: [URL] = []
    public var detectedLanguage: String?
    public var warnings: [String] = []

    public init(url: URL, id: UUID = UUID()) {
        self.url = url
        self.id = id
    }

    public var isFinished: Bool { status.isFinished }
}

public enum OutputMode: String, CaseIterable, Identifiable, Sendable {
    case original, english
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .original: "Original language"
        case .english: "Translate to English (Whisper)"
        }
    }
}

/// Everything one queue run needs, captured when the run starts.
public struct PipelineConfig: Sendable, Equatable {
    public var model: ModelInfo
    /// ISO code, or nil for auto-detect.
    public var language: String?
    public var translateToEnglish: Bool
    /// Extra on-device translations (language identifiers such as "de").
    public var extraTargets: [String]
    /// nil saves next to each source file.
    public var outputFolder: URL?
    public var settings: TranscriptionSettings

    public init(
        model: ModelInfo, language: String? = nil, translateToEnglish: Bool = false,
        extraTargets: [String] = [], outputFolder: URL? = nil, settings: TranscriptionSettings = .init()
    ) {
        self.model = model
        self.language = language
        self.translateToEnglish = translateToEnglish && model.supportsTranslation
        self.extraTargets = extraTargets
        self.outputFolder = outputFolder
        self.settings = settings
    }
}
