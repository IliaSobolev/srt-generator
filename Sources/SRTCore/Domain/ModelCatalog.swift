import Foundation

public enum EngineType: String, Codable, Sendable, CaseIterable {
    case whisper
    case parakeet

    public var title: String {
        switch self {
        case .whisper: "Whisper"
        case .parakeet: "Parakeet"
        }
    }
}

/// A speech model the user can download and select. The list mirrors HandyAI's model catalog
/// (https://github.com/JIEHT9U/HandyAI), using native CoreML builds of the same models.
public struct ModelInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let sizeMB: Int
    public let engine: EngineType
    /// 0...1, higher is more accurate.
    public let accuracy: Double
    /// 0...1, higher is faster.
    public let speed: Double
    public let languages: String
    /// Whisper can translate any language to English.
    public let supportsTranslation: Bool
    /// Whether the spoken language can be chosen manually.
    public let supportsLanguageSelection: Bool
    /// WhisperKit variant folder in argmaxinc/whisperkit-coreml.
    public let whisperVariant: String?
    /// Spoken languages the model accepts as a hint; nil = every Whisper language.
    public let languageCodes: [String]?

    public init(
        id: String, name: String, description: String, sizeMB: Int, engine: EngineType,
        accuracy: Double, speed: Double, languages: String, supportsTranslation: Bool,
        supportsLanguageSelection: Bool, whisperVariant: String?, languageCodes: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.sizeMB = sizeMB
        self.engine = engine
        self.accuracy = accuracy
        self.speed = speed
        self.languages = languages
        self.supportsTranslation = supportsTranslation
        self.supportsLanguageSelection = supportsLanguageSelection
        self.whisperVariant = whisperVariant
        self.languageCodes = languageCodes
    }

    public var sizeText: String {
        sizeMB >= 1000 ? String(format: "%.1f GB", Double(sizeMB) / 1000) : "\(sizeMB) MB"
    }

    public func supportsLanguage(_ code: String) -> Bool {
        supportsLanguageSelection && (languageCodes?.contains(code) ?? true)
    }
}

public enum ModelCatalog {
    public static let all: [ModelInfo] = [
        ModelInfo(id: "small", name: "Whisper Small", description: "Fast and fairly accurate.",
                  sizeMB: 486, engine: .whisper, accuracy: 0.60, speed: 0.85,
                  languages: "99 languages", supportsTranslation: true, supportsLanguageSelection: true,
                  whisperVariant: "openai_whisper-small"),
        ModelInfo(id: "medium", name: "Whisper Medium", description: "Good accuracy, medium speed",
                  sizeMB: 1529, engine: .whisper, accuracy: 0.75, speed: 0.60,
                  languages: "99 languages", supportsTranslation: true, supportsLanguageSelection: true,
                  whisperVariant: "openai_whisper-medium"),
        ModelInfo(id: "turbo", name: "Whisper Turbo", description: "Balanced accuracy and speed.",
                  sizeMB: 1638, engine: .whisper, accuracy: 0.80, speed: 0.40,
                  languages: "99 languages", supportsTranslation: true, supportsLanguageSelection: true,
                  whisperVariant: "openai_whisper-large-v3-v20240930_turbo"),
        ModelInfo(id: "large", name: "Whisper Large", description: "Good accuracy, but slow.",
                  sizeMB: 948, engine: .whisper, accuracy: 0.85, speed: 0.30,
                  languages: "99 languages", supportsTranslation: true, supportsLanguageSelection: true,
                  whisperVariant: "openai_whisper-large-v3_947MB"),
        ModelInfo(id: "parakeet-tdt-0.6b-v2", name: "Parakeet V2",
                  description: "English only. The best model for English speakers.",
                  sizeMB: 473, engine: .parakeet, accuracy: 0.85, speed: 0.85,
                  languages: "English", supportsTranslation: false, supportsLanguageSelection: false,
                  whisperVariant: nil, languageCodes: ["en"]),
        ModelInfo(id: "parakeet-tdt-0.6b-v3", name: "Parakeet V3", description: "Fast and accurate",
                  sizeMB: 478, engine: .parakeet, accuracy: 0.80, speed: 0.85,
                  languages: "25 European languages", supportsTranslation: false, supportsLanguageSelection: true,
                  whisperVariant: nil, languageCodes: parakeetV3Languages),
    ]

    public static let defaultID = "small"

    public static let parakeetV3Languages = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
        "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk",
    ]

    public static var defaultModel: ModelInfo { all[0] }

    public static func model(id: String) -> ModelInfo? { all.first { $0.id == id } }
}
