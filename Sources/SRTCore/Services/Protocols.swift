import Foundation

// Every external capability SRTCore needs is expressed as a protocol here, so the app wires in
// real implementations (WhisperKit, FluidAudio, AppKit, Apple Translation) and tests wire in fakes.

public typealias ProgressHandler = @Sendable (Double) -> Void

public struct TranscriptionRequest: Sendable, Equatable {
    /// ISO code, or nil for auto-detect.
    public var language: String?
    public var translate: Bool
    public var settings: TranscriptionSettings

    public init(language: String? = nil, translate: Bool = false, settings: TranscriptionSettings = .init()) {
        self.language = language
        self.translate = translate
        self.settings = settings
    }
}

public struct EngineResult: Sendable, Equatable {
    public var segments: [SpeechSegment]
    /// Detected or requested spoken language (ISO code).
    public var language: String

    public init(segments: [SpeechSegment], language: String) {
        self.segments = segments
        self.language = language
    }
}

/// A loaded speech-to-text model.
public protocol SpeechEngine: Sendable {
    func transcribe(samples: [Float], request: TranscriptionRequest, progress: @escaping ProgressHandler)
        async throws -> EngineResult
}

/// Storage and loading for one engine family (Whisper or Parakeet).
public protocol ModelProvider: Sendable {
    func folder(for model: ModelInfo) -> URL
    func isDownloaded(_ model: ModelInfo) -> Bool
    func download(_ model: ModelInfo, progress: @escaping ProgressHandler) async throws
    func delete(_ model: ModelInfo) throws
    func load(_ model: ModelInfo, compute: ComputeTarget) async throws -> any SpeechEngine
}

/// Decodes any audio/video file into 16 kHz mono Float32 samples.
public protocol AudioDecoding: Sendable {
    /// True when exotic containers (MKV, WebM, OGG…) are supported, i.e. ffmpeg is available.
    var supportsAllFormats: Bool { get }
    func decode(_ url: URL) async throws -> [Float]
}

/// On-device text translation.
@MainActor
public protocol Translating: AnyObject {
    func translate(_ texts: [String], from source: String, to target: String) async throws -> [String]
    /// Language identifiers that can be translated to.
    func supportedTargets() async -> [String]
}

/// Writes subtitle files to disk.
public protocol SubtitleWriting: Sendable {
    /// - Parameters:
    ///   - suffix: language suffix such as "en" → `name.en.srt`; nil → `name.srt`.
    ///   - folder: destination folder; nil saves next to `source`.
    func write(_ cues: [SubtitleCue], for source: URL, suffix: String?, folder: URL?) throws -> URL
}

/// Native file/folder pickers.
@MainActor
public protocol FilePicking {
    func pickMedia() -> [URL]
    func pickFolder() -> URL?
}

/// Abstracts waiting so timers can be tested without real delays.
public protocol Sleeper: Sendable {
    func sleep(seconds: Double) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}
    public func sleep(seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}
