import Foundation

enum ComputeTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case neuralEngine, gpu
    var id: String { rawValue }
    var title: String {
        switch self {
        case .neuralEngine: "Neural Engine (efficient)"
        case .gpu: "GPU (often faster on Pro/Max chips)"
        }
    }
}

enum UnloadTimeout: Int, Codable, CaseIterable, Identifiable, Sendable {
    case never = -1
    case immediately = 0
    case min2 = 120
    case min5 = 300
    case min15 = 900
    case hour1 = 3600
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .never: "Never"
        case .immediately: "Immediately after a batch"
        case .min2: "After 2 minutes"
        case .min5: "After 5 minutes"
        case .min15: "After 15 minutes"
        case .hour1: "After 1 hour"
        }
    }
}

/// User-tunable model settings, persisted as JSON in UserDefaults.
struct TranscriptionSettings: Codable, Equatable, Sendable {
    // Shared (HandyAI-style)
    var customWords: [String] = []
    var unloadTimeout: UnloadTimeout = .min5
    var compute: ComputeTarget = .neuralEngine

    // Whisper
    var whisperVAD = true
    var whisperTemperatureFallback = true
    var whisperSuppressNonSpeech = true

    // Subtitles
    var maxLineLength = 42
    var maxCueDuration = 7.0

    var cueBuilder: CueBuilder { CueBuilder(maxLineLength: maxLineLength, maxDuration: maxCueDuration) }

    static let key = "transcriptionSettings"

    static func load(_ defaults: UserDefaults = .standard) -> TranscriptionSettings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(TranscriptionSettings.self, from: data) else { return .init() }
        return s
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

extension TranscriptionSettings {
    // Tolerate settings saved by older versions that lack newer keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TranscriptionSettings()
        customWords = try c.decodeIfPresent([String].self, forKey: .customWords) ?? d.customWords
        unloadTimeout = try c.decodeIfPresent(UnloadTimeout.self, forKey: .unloadTimeout) ?? d.unloadTimeout
        compute = try c.decodeIfPresent(ComputeTarget.self, forKey: .compute) ?? d.compute
        whisperVAD = try c.decodeIfPresent(Bool.self, forKey: .whisperVAD) ?? d.whisperVAD
        whisperTemperatureFallback = try c.decodeIfPresent(Bool.self, forKey: .whisperTemperatureFallback)
            ?? d.whisperTemperatureFallback
        whisperSuppressNonSpeech = try c.decodeIfPresent(Bool.self, forKey: .whisperSuppressNonSpeech)
            ?? d.whisperSuppressNonSpeech
        maxLineLength = try c.decodeIfPresent(Int.self, forKey: .maxLineLength) ?? d.maxLineLength
        maxCueDuration = try c.decodeIfPresent(Double.self, forKey: .maxCueDuration) ?? d.maxCueDuration
    }
}
