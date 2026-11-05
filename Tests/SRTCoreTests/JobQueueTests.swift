import Foundation
@testable import SRTCore
import Testing

/// A JobQueue wired to fakes, with handles to every dependency.
@MainActor
struct QueueHarness {
    let engine = FakeEngine()
    let provider: FakeProvider
    let decoder = FakeDecoder()
    let writer = FakeWriter()
    let translator: FakeTranslator?
    let transcription: TranscriptionService
    let models: ModelManager
    let queue: JobQueue

    init(downloaded: Set<String> = ["small", "parakeet-tdt-0.6b-v3"], withTranslator: Bool = true,
         sleeper: any Sleeper = ImmediateSleeper()) {
        provider = FakeProvider(downloaded: downloaded, engine: engine)
        let translator = withTranslator ? FakeTranslator() : nil
        self.translator = translator
        let registry = ModelRegistry(whisper: provider, parakeet: provider)
        transcription = TranscriptionService(registry: registry)
        models = ModelManager(registry: registry)
        queue = JobQueue(transcription: transcription, models: models, decoder: decoder, writer: writer,
                         translator: translator, sleeper: sleeper)
    }

    nonisolated static let a = URL(fileURLWithPath: "/media/a.mp4")
    nonisolated static let b = URL(fileURLWithPath: "/media/b.mkv")

    func run(_ config: PipelineConfig = PipelineConfig(model: Fixtures.whisper), urls: [URL] = [a]) async -> [Job] {
        queue.add(urls)
        await queue.start(config)?.value
        return queue.jobs
    }
}

@MainActor
@Suite("Job queue")
struct JobQueueTests {
    @Test("Editing the queue: duplicates ignored, remove, clear finished, pending work")
    func editing() async {
        let h = QueueHarness()
        h.queue.add([QueueHarness.a, QueueHarness.b, QueueHarness.a])
        #expect(h.queue.jobs.map(\.url) == [QueueHarness.a, QueueHarness.b])
        #expect(h.queue.hasPendingWork)
        h.queue.remove(h.queue.jobs[1])
        #expect(h.queue.jobs.count == 1)
        _ = await h.run()
        #expect(!h.queue.hasPendingWork)
        h.queue.clearFinished()
        #expect(h.queue.jobs.isEmpty)
    }

    @Test("Happy path: transcribes, writes the SRT and reports progress")
    func happyPath() async {
        let h = QueueHarness()
        let folder = URL(fileURLWithPath: "/out")
        var settings = TranscriptionSettings()
        settings.compute = .gpu
        let config = PipelineConfig(model: Fixtures.whisper, language: "en", outputFolder: folder, settings: settings)
        h.queue.add([QueueHarness.a])
        let task = h.queue.start(config)
        #expect(h.queue.isRunning)
        var sawProgress = false
        while !h.queue.jobs[0].isFinished {
            if case .transcribing(let p) = h.queue.jobs[0].status, p == 0.5 { sawProgress = true }
            await Task.yield()
        }
        await task?.value
        let job = h.queue.jobs[0]
        #expect(job.status == .done)
        #expect(sawProgress)
        #expect(!h.queue.isRunning)
        #expect(job.detectedLanguage == "en")
        #expect(job.outputs == [URL(fileURLWithPath: "/out/a.srt")])
        let write = h.writer.writes.withLock { $0 }[0]
        #expect(write.cues == [SubtitleCue(start: 0, end: 1.5, text: "Hello world.")])
        #expect(write.suffix == nil && write.folder == folder)
        #expect(h.engine.state.withLock { $0.requests } == [TranscriptionRequest(language: "en", settings: settings)])
        #expect(h.provider.state.withLock { $0.loads.map(\.1) } == [.gpu])
        #expect(h.translator?.calls.isEmpty == true)
    }

    @Test("Downloads a missing model first, showing download progress")
    func downloadsModel() async throws {
        let h = QueueHarness(downloaded: [])
        h.provider.state.withLock {
            $0.downloadDelay = .milliseconds(150) // hold at 75% so it is observable
            $0.loadDelay = .milliseconds(150) // hold .loadingModel too; polling can miss a transient state
        }
        h.queue.add([QueueHarness.a])
        let task = h.queue.start(PipelineConfig(model: Fixtures.parakeetV2))
        var seen: [Job.Status] = []
        while !h.queue.jobs[0].isFinished {
            if seen.last != h.queue.jobs[0].status { seen.append(h.queue.jobs[0].status) }
            await Task.yield()
        }
        await task?.value
        let at75 = try #require(seen.firstIndex(of: .downloadingModel(0.75)))
        let loading = try #require(seen.firstIndex(of: .loadingModel))
        #expect(at75 < loading)
        #expect(h.queue.jobs[0].status == .done)
        #expect(h.provider.state.withLock { $0.downloads } == ["parakeet-tdt-0.6b-v2"])
    }

    @Test("English translation plus on-device translations, skipping the source language")
    func translations() async throws {
        let h = QueueHarness()
        let translator = try #require(h.translator)
        translator.errors["fr"] = TestError.boom("offline")
        var settings = TranscriptionSettings()
        settings.maxLineLength = 10
        let config = PipelineConfig(model: Fixtures.whisper, translateToEnglish: true,
                                    extraTargets: ["de", "en-GB", "fr"], settings: settings)
        let job = await h.run(config)[0]
        #expect(job.status == .done)
        #expect(job.outputs.map(\.lastPathComponent) == ["a.en.srt", "a.de.srt"])
        #expect(job.warnings == ["\(Languages.displayName("fr")): boom: offline"])
        #expect(translator.calls.map(\.target) == ["de", "fr"])
        #expect(translator.calls[0].source == "en")
        #expect(h.engine.state.withLock { $0.requests[0].translate })
        let german = h.writer.writes.withLock { $0 }.first { $0.suffix == "de" }
        #expect(german?.cues.map(\.text) == ["[de] Hello\nworld."])
    }

    @Test("Without a translator, extra targets are skipped")
    func noTranslator() async {
        let h = QueueHarness(withTranslator: false)
        let job = await h.run(PipelineConfig(model: Fixtures.whisper, extraTargets: ["de"]))[0]
        #expect(job.status == .done)
        #expect(job.outputs.count == 1)
    }

    @Test("Failures at each stage mark the job failed", arguments: [
        "download", "load", "decode", "silence", "noSpeech", "transcribe", "write",
    ])
    func failures(stage: String) async {
        let h = QueueHarness(downloaded: stage == "download" ? [] : ["small"])
        switch stage {
        case "download": h.provider.state.withLock { $0.downloadError = .boom(stage) }
        case "load": h.provider.state.withLock { $0.loadError = .boom(stage) }
        case "decode": h.decoder.state.withLock { $0.error = .boom(stage) }
        case "silence": h.decoder.state.withLock { $0.samples = [] }
        case "noSpeech": h.engine.state.withLock { $0.result = EngineResult(segments: [], language: "en") }
        case "transcribe": h.engine.state.withLock { $0.error = .boom(stage) }
        default: h.writer.failingSuffix.withLock { $0 = .some(nil) }
        }
        let expected = switch stage {
        case "silence": "The file has no audio track."
        case "noSpeech": "No speech detected."
        default: "boom: \(stage)"
        }
        #expect(await h.run()[0].status == .failed(expected))
    }

    @Test("A cancelled translation cancels the job")
    func translationCancelled() async throws {
        let h = QueueHarness()
        try #require(h.translator).errors["de"] = CancellationError()
        let job = await h.run(PipelineConfig(model: Fixtures.whisper, extraTargets: ["de"]))[0]
        #expect(job.status == .cancelled)
    }

    @Test("Stopping cancels the current job and everything still queued")
    func stop() async {
        let h = QueueHarness()
        h.decoder.state.withLock { $0.delay = .seconds(30) }
        h.queue.add([QueueHarness.a, QueueHarness.b])
        let task = h.queue.start(PipelineConfig(model: Fixtures.whisper))
        while h.queue.jobs[0].status != .decoding { await Task.yield() }
        h.queue.cancel()
        await task?.value
        #expect(h.queue.jobs.map(\.status) == [.cancelled, .cancelled])
    }

    @Test("Starting twice is ignored; failed and stopped jobs are retried next run")
    func restart() async {
        let h = QueueHarness()
        h.decoder.state.withLock { $0.error = .boom("x") }
        h.queue.add([QueueHarness.a])
        let first = h.queue.start(PipelineConfig(model: Fixtures.whisper))
        #expect(h.queue.start(PipelineConfig(model: Fixtures.whisper)) == nil)
        await first?.value
        #expect(h.queue.jobs[0].status == .failed("boom: x"))
        h.decoder.state.withLock { $0.error = nil }
        await h.queue.start(PipelineConfig(model: Fixtures.whisper))?.value
        #expect(h.queue.jobs[0].status == .done)
    }

    @Test("The model is unloaded after the idle timeout, unless set to never")
    func unload() async {
        let h = QueueHarness()
        var settings = TranscriptionSettings()
        settings.unloadTimeout = .immediately
        _ = await h.run(PipelineConfig(model: Fixtures.whisper, settings: settings))
        await h.queue.unloadTask?.value
        #expect(await !h.transcription.isLoaded)

        settings.unloadTimeout = .never
        let again = QueueHarness()
        _ = await again.run(PipelineConfig(model: Fixtures.whisper, settings: settings))
        #expect(again.queue.unloadTask == nil)
        #expect(await again.transcription.isLoaded)
    }

    @Test("Starting a new run cancels a pending unload")
    func unloadCancelled() async {
        let h = QueueHarness(sleeper: LongSleeper())
        _ = await h.run()
        let pending = h.queue.unloadTask
        h.queue.add([QueueHarness.b])
        await h.queue.start(PipelineConfig(model: Fixtures.whisper))?.value
        await pending?.value
        #expect(await h.transcription.isLoaded)
        h.queue.unloadTask?.cancel()
    }
}
