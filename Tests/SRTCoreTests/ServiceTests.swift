import Foundation
import Synchronization
import Testing
@testable import SRTCore

@Suite("Model registry")
struct ModelRegistryTests {
    @Test("Routes each engine family to its provider")
    func routes() {
        let whisper = FakeProvider(downloaded: ["small"])
        let parakeet = FakeProvider(downloaded: ["parakeet-tdt-0.6b-v3"])
        let registry = ModelRegistry(whisper: whisper, parakeet: parakeet)
        #expect(registry.provider(for: Fixtures.whisper).isDownloaded(Fixtures.whisper))
        #expect(registry.provider(for: Fixtures.parakeetV3).isDownloaded(Fixtures.parakeetV3))
        #expect(!registry.provider(for: Fixtures.parakeetV2).isDownloaded(Fixtures.parakeetV2))
    }
}

@Suite("Transcription service")
struct TranscriptionServiceTests {
    @Test("Transcribing without a loaded model fails")
    func notLoaded() async {
        let service = TranscriptionService(registry: ModelRegistry(whisper: FakeProvider(), parakeet: FakeProvider()))
        #expect(await !service.isLoaded)
        await #expect(throws: TranscriptionError.modelNotLoaded) {
            try await service.transcribe(samples: [], request: .init()) { _ in }
        }
    }

    @Test("Loads once per model and compute target, reloads on change, unloads")
    func loading() async throws {
        let whisper = FakeProvider()
        let parakeet = FakeProvider()
        let service = TranscriptionService(registry: ModelRegistry(whisper: whisper, parakeet: parakeet))
        try await service.load(Fixtures.whisper, compute: .neuralEngine)
        try await service.load(Fixtures.whisper, compute: .neuralEngine)
        #expect(whisper.state.withLock { $0.loads.count } == 1)
        try await service.load(Fixtures.whisper, compute: .gpu)
        #expect(whisper.state.withLock { $0.loads.map(\.1) } == [.neuralEngine, .gpu])
        try await service.load(Fixtures.parakeetV3, compute: .gpu)
        #expect(parakeet.state.withLock { $0.loads.count } == 1)
        #expect(await service.isLoaded)
        await service.unload()
        #expect(await !service.isLoaded)
    }

    @Test("A failed load leaves nothing loaded")
    func loadError() async {
        let provider = FakeProvider()
        provider.state.withLock { $0.loadError = .boom("load") }
        let service = TranscriptionService(registry: ModelRegistry(whisper: provider, parakeet: provider))
        await #expect(throws: TestError.boom("load")) { try await service.load(Fixtures.whisper, compute: .gpu) }
        #expect(await !service.isLoaded)
    }

    @Test("Builds cues with the request's subtitle settings and forwards progress")
    func transcribe() async throws {
        let engine = FakeEngine()
        engine.state.withLock {
            $0.result = EngineResult(segments: [SpeechSegment(start: 0, end: 2, text: " one two three four")], language: "de")
            $0.progressValues = [0.3, 0.6]
        }
        let provider = FakeProvider(engine: engine)
        let service = TranscriptionService(registry: ModelRegistry(whisper: provider, parakeet: provider))
        try await service.load(Fixtures.whisper, compute: .neuralEngine)
        var settings = TranscriptionSettings()
        settings.maxLineLength = 10
        let progress = Mutex<[Double]>([])
        let request = TranscriptionRequest(language: "de", translate: true, settings: settings)
        let out = try await service.transcribe(samples: [1, 2, 3], request: request) { v in
            progress.withLock { $0.append(v) }
        }
        #expect(out == TranscriptionOutput(cues: [SubtitleCue(start: 0, end: 2, text: "one two\nthree four")], language: "de"))
        #expect(progress.withLock { $0 } == [0.3, 0.6])
        #expect(engine.state.withLock { $0.requests } == [request])
        #expect(engine.state.withLock { $0.sampleCounts } == [3])
    }
}

@MainActor
@Suite("Model manager")
struct ModelManagerTests {
    let provider = FakeProvider(downloaded: ["small"])
    var manager: ModelManager { ModelManager(registry: ModelRegistry(whisper: provider, parakeet: provider)) }

    @Test("Reads download state and folders from providers")
    func state() {
        let m = manager
        #expect(m.catalog == ModelCatalog.all)
        #expect(m.downloaded == ["small"])
        #expect(m.isDownloaded(Fixtures.whisper))
        #expect(!m.isDownloading(Fixtures.whisper))
        #expect(m.folder(for: Fixtures.parakeetV2).lastPathComponent == "parakeet-tdt-0.6b-v2")
    }

    @Test("Download reports progress, then refreshes")
    func download() async throws {
        let m = manager
        var seen: [Double] = []
        let task = Task { try await m.download(Fixtures.parakeetV3) { seen.append($0) } }
        await settle(5)
        #expect(m.isDownloading(Fixtures.parakeetV3))
        try await task.value
        #expect(seen == [0.25, 0.75])
        #expect(m.downloaded.contains("parakeet-tdt-0.6b-v3"))
        #expect(m.progress.isEmpty)
    }

    @Test("A second concurrent download of the same model is rejected")
    func duplicate() async throws {
        let m = manager
        provider.state.withLock { $0.downloadDelay = .milliseconds(100) }
        let first = Task { try await m.download(Fixtures.parakeetV2) }
        await settle(5)
        await #expect(throws: TranscriptionError.alreadyDownloading("Parakeet V2")) {
            try await m.download(Fixtures.parakeetV2)
        }
        try await first.value
    }

    @Test("A download that leaves files missing is reported as incomplete")
    func incomplete() async {
        provider.state.withLock { $0.markDownloaded = false }
        await #expect(throws: TranscriptionError.downloadIncomplete("Whisper Turbo")) {
            try await manager.download(ModelCatalog.model(id: "turbo")!)
        }
    }

    @Test("One-click use of an already downloaded model is immediate")
    func useDownloaded() {
        var used: ModelInfo?
        #expect(manager.downloadAndUse(Fixtures.whisper) { used = $0 } == nil)
        #expect(used == Fixtures.whisper)
    }

    @Test("One-click use downloads first, and repeated clicks share the download")
    func useAfterDownload() async {
        let m = manager
        provider.state.withLock { $0.downloadDelay = .milliseconds(50) }
        var used: [ModelInfo] = []
        let task = m.downloadAndUse(Fixtures.parakeetV3) { used.append($0) }
        let again = m.downloadAndUse(Fixtures.parakeetV3) { used.append($0) }
        #expect(task != nil && task == again)
        await task?.value
        #expect(used == [Fixtures.parakeetV3])
        #expect(provider.state.withLock { $0.downloads } == ["parakeet-tdt-0.6b-v3"])
    }

    @Test("Download failures are shown per model and cleared on retry")
    func useFailure() async {
        let m = manager
        provider.state.withLock { $0.downloadError = .boom("network") }
        await m.downloadAndUse(Fixtures.parakeetV2) { _ in Issue.record("must not be used") }?.value
        #expect(m.errors["parakeet-tdt-0.6b-v2"] == "boom: network")
        provider.state.withLock { $0.downloadError = nil }
        await m.downloadAndUse(Fixtures.parakeetV2) { _ in }?.value
        #expect(m.errors["parakeet-tdt-0.6b-v2"] == nil)
    }

    @Test("Cancelling a download hides progress, ignores late progress and does not use the model")
    func cancel() async {
        let m = manager
        provider.state.withLock {
            $0.downloadDelay = .milliseconds(80)
            $0.progressAfterDelay = [0.9]
        }
        let task = m.downloadAndUse(Fixtures.parakeetV2) { _ in Issue.record("must not be used") }
        await settle(10)
        m.cancelDownload(Fixtures.parakeetV2)
        #expect(!m.isDownloading(Fixtures.parakeetV2))
        await task?.value
        #expect(m.progress["parakeet-tdt-0.6b-v2"] == nil)
        #expect(m.errors.isEmpty)
    }

    @Test("Cancellation that surfaces as an error is not reported")
    func cancelWithError() async {
        let m = manager
        provider.state.withLock {
            $0.downloadDelay = .milliseconds(60)
            $0.downloadError = .boom("cancelled")
        }
        let task = m.downloadAndUse(Fixtures.parakeetV2) { _ in }
        await settle(10)
        task?.cancel()
        await task?.value
        #expect(m.errors.isEmpty)
    }

    @Test("Delete removes the model, or reports why it could not")
    func delete() {
        let m = manager
        m.delete(Fixtures.whisper)
        #expect(!m.downloaded.contains("small"))
        provider.state.withLock { $0.deleteError = .boom("locked") }
        m.delete(Fixtures.parakeetV2)
        #expect(m.errors["parakeet-tdt-0.6b-v2"] == "boom: locked")
    }
}

@Suite("Subtitle file writer")
struct SubtitleFileWriterTests {
    @Test("Writes next to the source or into a folder, never overwriting")
    func writes() throws {
        let dir = try Fixtures.tempDir()
        let source = dir.appendingPathComponent("talk.mkv")
        let cues = [SubtitleCue(start: 0, end: 1, text: "Hi")]
        let writer = SubtitleFileWriter()

        let first = try writer.write(cues, for: source, suffix: nil, folder: nil)
        #expect(first.lastPathComponent == "talk.srt")
        #expect(try String(contentsOf: first, encoding: .utf8) == SRTWriter.render(cues))
        #expect(try writer.write(cues, for: source, suffix: nil, folder: nil).lastPathComponent == "talk (1).srt")
        #expect(try writer.write(cues, for: source, suffix: nil, folder: nil).lastPathComponent == "talk (2).srt")

        let out = try Fixtures.tempDir()
        let translated = try writer.write(cues, for: source, suffix: "de", folder: out)
        #expect(translated == out.appendingPathComponent("talk.de.srt"))
    }

    @Test("Reports write errors")
    func failure() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(throws: (any Error).self) {
            try SubtitleFileWriter().write([], for: missing.appendingPathComponent("a.mp4"), suffix: nil, folder: nil)
        }
    }
}

@Suite("Media files")
struct MediaFilesTests {
    @Test("Recognizes media by type or by ffmpeg-only extension")
    func isMedia() {
        #expect(MediaFiles.isMedia(URL(fileURLWithPath: "/x/a.mp4")))
        #expect(MediaFiles.isMedia(URL(fileURLWithPath: "/x/a.MKV")))
        #expect(!MediaFiles.isMedia(URL(fileURLWithPath: "/x/a.txt")))
    }

    @Test("Expands folders recursively, skipping hidden and non-media files")
    func expand() throws {
        let dir = try Fixtures.tempDir()
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for name in ["b.mp3", "a.webm", "notes.txt", ".hidden.mp3", "sub/c.mov"] {  // .hidden/ files skipped too
            try Data().write(to: dir.appendingPathComponent(name))
        }
        let loose = URL(fileURLWithPath: "/elsewhere/clip.mp4")
        let result = MediaFiles.expand([dir, loose]).map(\.lastPathComponent)
        #expect(result == ["a.webm", "b.mp3", "c.mov", "clip.mp4"])
        #expect(MediaFiles.isDirectory(dir))
        #expect(!MediaFiles.isDirectory(loose))
    }

    @Test("Unreadable folders contribute nothing")
    func unreadable() throws {
        let dir = try Fixtures.tempDir()
        try Data().write(to: dir.appendingPathComponent("a.mp3"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        #expect(MediaFiles.expand([dir]).isEmpty)
    }
}

@Suite("Sleeper")
struct SleeperTests {
    @Test("TaskSleeper sleeps and honors cancellation")
    func sleeps() async {
        await #expect(throws: Never.self) { try await TaskSleeper().sleep(seconds: 0.001) }
        let task = Task { try await TaskSleeper().sleep(seconds: 60) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
