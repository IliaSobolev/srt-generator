import Foundation
@testable import SRTCore
import Synchronization

enum TestError: Error, Equatable, LocalizedError {
    case boom(String)
    var errorDescription: String? {
        switch self {
        case .boom(let what): "boom: \(what)"
        }
    }
}

/// Lets the main actor run `Task { @MainActor … }` hops scheduled by the code under test.
func settle(_ ms: Int = 30) async {
    try? await Task.sleep(for: .milliseconds(ms))
}

// MARK: - Speech engine

final class FakeEngine: SpeechEngine {
    struct State {
        var result = EngineResult(
            segments: [SpeechSegment(start: 0, end: 1.5, text: " Hello world.")], language: "en"
        )
        var error: TestError?
        var cancellable = false
        var delay: Duration?
        var progressValues: [Double] = [0.5]
        var requests: [TranscriptionRequest] = []
        var sampleCounts: [Int] = []
    }

    let state = Mutex(State())

    func transcribe(samples: [Float], request: TranscriptionRequest, progress: @escaping ProgressHandler)
        async throws -> EngineResult {
        let (values, delay, error, result) = state.withLock { s in
            s.requests.append(request)
            s.sampleCounts.append(samples.count)
            return (s.progressValues, s.delay, s.error, s.result)
        }
        for value in values { progress(value) }
        await settle()
        if let delay { try await Task.sleep(for: delay) }
        if let error { throw error }
        return result
    }
}

// MARK: - Model provider

final class FakeProvider: ModelProvider {
    struct State {
        var downloaded: Set<String> = []
        var downloadError: TestError?
        var loadError: TestError?
        var deleteError: TestError?
        var markDownloaded = true
        var progressSteps: [Double] = [0.25, 0.75]
        /// Waits this long before finishing a download, ignoring cancellation.
        var downloadDelay: Duration?
        /// Waits this long (cancellably) before finishing a download.
        var cancellableDelay: Duration?
        var progressAfterDelay: [Double] = []
        var downloads: [String] = []
        var loads: [(String, ComputeTarget)] = []
        var deletes: [String] = []
    }

    let state: Mutex<State>
    let engine: FakeEngine

    init(downloaded: Set<String> = [], engine: FakeEngine = FakeEngine()) {
        state = Mutex(State(downloaded: downloaded))
        self.engine = engine
    }

    func folder(for model: ModelInfo) -> URL { URL(fileURLWithPath: "/tmp/fake-models/\(model.id)") }

    func isDownloaded(_ model: ModelInfo) -> Bool { state.withLock { $0.downloaded.contains(model.id) } }

    func download(_ model: ModelInfo, progress: @escaping ProgressHandler) async throws {
        let s = state.withLock { s in
            s.downloads.append(model.id)
            return s
        }
        for step in s.progressSteps { progress(step) }
        await settle()
        if let delay = s.cancellableDelay { try await Task.sleep(for: delay) }
        if let delay = s.downloadDelay { try? await Task.sleep(for: delay) }
        for step in s.progressAfterDelay { progress(step) }
        await settle()
        if let error = s.downloadError { throw error }
        if s.markDownloaded { _ = state.withLock { $0.downloaded.insert(model.id) } }
    }

    func delete(_ model: ModelInfo) throws {
        try state.withLock { s in
            if let error = s.deleteError { throw error }
            s.deletes.append(model.id)
            s.downloaded.remove(model.id)
        }
    }

    func load(_ model: ModelInfo, compute: ComputeTarget) async throws -> any SpeechEngine {
        try state.withLock { s in
            s.loads.append((model.id, compute))
            if let error = s.loadError { throw error }
        }
        return engine
    }
}

// MARK: - Audio decoder

final class FakeDecoder: AudioDecoding {
    struct State {
        var samples: [Float] = Array(repeating: 0, count: 16_000)
        var error: TestError?
        var delay: Duration?
        var decoded: [URL] = []
    }

    let supportsAllFormats: Bool
    let state = Mutex(State())

    init(supportsAllFormats: Bool = true) { self.supportsAllFormats = supportsAllFormats }

    func decode(_ url: URL) async throws -> [Float] {
        let s = state.withLock { s in
            s.decoded.append(url)
            return s
        }
        if let delay = s.delay { try await Task.sleep(for: delay) }
        if let error = s.error { throw error }
        return s.samples
    }
}

// MARK: - Subtitle writer

final class FakeWriter: SubtitleWriting {
    struct Write: Equatable {
        var cues: [SubtitleCue]
        var source: URL
        var suffix: String?
        var folder: URL?
    }

    let writes = Mutex<[Write]>([])
    let failingSuffix = Mutex<String??>(nil)

    func write(_ cues: [SubtitleCue], for source: URL, suffix: String?, folder: URL?) throws -> URL {
        if let failing = failingSuffix.withLock({ $0 }), failing == suffix { throw TestError.boom("write") }
        writes.withLock { $0.append(Write(cues: cues, source: source, suffix: suffix, folder: folder)) }
        let name = source.deletingPathExtension().lastPathComponent + (suffix.map { ".\($0)" } ?? "") + ".srt"
        return (folder ?? source.deletingLastPathComponent()).appendingPathComponent(name)
    }
}

// MARK: - Translator

@MainActor
final class FakeTranslator: Translating {
    var targets: [String] = ["fr", "de", "ja"]
    var errors: [String: Error] = [:]
    var calls: [(texts: [String], source: String, target: String)] = []

    func translate(_ texts: [String], from source: String, to target: String) async throws -> [String] {
        calls.append((texts, source, target))
        if let error = errors[target] { throw error }
        return texts.map { "[\(target)] \($0)" }
    }

    func supportedTargets() async -> [String] { targets }
}

// MARK: - Picker and sleepers

@MainActor
final class FakePicker: FilePicking {
    var media: [URL] = []
    var folder: URL?
    func pickMedia() -> [URL] { media }
    func pickFolder() -> URL? { folder }
}

struct ImmediateSleeper: Sleeper {
    func sleep(seconds: Double) async throws {}
}

struct LongSleeper: Sleeper {
    func sleep(seconds: Double) async throws { try await Task.sleep(for: .seconds(60)) }
}

// MARK: - Fixtures

enum Fixtures {
    static let whisper = ModelCatalog.model(id: "small")!
    static let parakeetV2 = ModelCatalog.model(id: "parakeet-tdt-0.6b-v2")!
    static let parakeetV3 = ModelCatalog.model(id: "parakeet-tdt-0.6b-v3")!

    static func defaults() -> UserDefaults {
        let name = "SRTCoreTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SRTCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
