import Foundation

public enum ComputeTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case neuralEngine, gpu
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .neuralEngine: "Neural Engine (efficient)"
        case .gpu: "GPU (often faster on Pro/Max chips)"
        }
    }
}

public enum UnloadTimeout: Int, Codable, CaseIterable, Identifiable, Sendable {
    case never = -1
    case immediately = 0
    case min2 = 120
    case min5 = 300
    case min15 = 900
    case hour1 = 3600
    public var id: Int { rawValue }
    public var title: String {
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
public struct TranscriptionSettings: Codable, Equatable, Sendable {
    // Shared (HandyAI-style)
    public var customWords: [String] = []
    public var unloadTimeout: UnloadTimeout = .min5
    public var compute: ComputeTarget = .neuralEngine

    // Whisper
    public var whisperVAD = true
    public var whisperTemperatureFallback = true
    public var whisperSuppressNonSpeech = true

    // Subtitles
    public var maxLineLength = 42
    public var maxCueDuration = 7.0

    public init() {}

    public var cueBuilder: CueBuilder { CueBuilder(maxLineLength: maxLineLength, maxDuration: maxCueDuration) }

    public static let key = "transcriptionSettings"

    public static func load(_ defaults: UserDefaults) -> TranscriptionSettings {
        let data = defaults.data(forKey: key)
        return data.flatMap { try? JSONDecoder().decode(TranscriptionSettings.self, from: $0) } ?? .init()
    }

    public func save(_ defaults: UserDefaults) {
        // Encoding a struct of plain values cannot fail.
        defaults.set(try! JSONEncoder().encode(self), forKey: Self.key)
    }

    // Tolerate settings saved by older versions that lack newer keys.
    public init(from decoder: Decoder) throws {
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
