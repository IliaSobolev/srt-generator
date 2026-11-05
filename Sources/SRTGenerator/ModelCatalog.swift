import Foundation

enum EngineType: String, Codable, Sendable {
    case whisper
    case parakeet

    var title: String {
        switch self {
        case .whisper: "Whisper"
        case .parakeet: "Parakeet"
        }
    }
}

/// A speech model the user can download and select. The list mirrors HandyAI's model catalog
/// (https://github.com/JIEHT9U/HandyAI), using native CoreML builds of the same models.
struct ModelInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let sizeMB: Int
    let engine: EngineType
    let accuracy: Double // 0...1, higher is more accurate
    let speed: Double // 0...1, higher is faster
    let languages: String
    /// Whisper can translate any language to English.
    let supportsTranslation: Bool
    /// Whether the spoken language can be chosen manually.
    let supportsLanguageSelection: Bool
    /// WhisperKit variant folder in argmaxinc/whisperkit-coreml.
    let whisperVariant: String?

    var sizeText: String {
        sizeMB >= 1000 ? String(format: "%.1f GB", Double(sizeMB) / 1000) : "\(sizeMB) MB"
    }
}

enum ModelCatalog {
    static let all: [ModelInfo] = [
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
                  whisperVariant: nil),
        ModelInfo(id: "parakeet-tdt-0.6b-v3", name: "Parakeet V3", description: "Fast and accurate",
                  sizeMB: 478, engine: .parakeet, accuracy: 0.80, speed: 0.85,
                  languages: "25 European languages", supportsTranslation: false, supportsLanguageSelection: true,
                  whisperVariant: nil),
    ]

    static let defaultID = "small"

    static func model(id: String) -> ModelInfo? { all.first { $0.id == id } }
}
