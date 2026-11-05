import Foundation
import Observation

/// The batch pipeline: download model → load → decode → transcribe → write SRT → translate.
@MainActor @Observable
public final class JobQueue {
    public private(set) var jobs: [Job] = []
    public private(set) var isRunning = false

    @ObservationIgnored private let transcription: TranscriptionService
    @ObservationIgnored private let models: ModelManager
    @ObservationIgnored private let decoder: any AudioDecoding
    @ObservationIgnored private let writer: any SubtitleWriting
    @ObservationIgnored private let translator: (any Translating)?
    @ObservationIgnored private let sleeper: any Sleeper
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private(set) var unloadTask: Task<Void, Never>?

    public init(
        transcription: TranscriptionService, models: ModelManager, decoder: any AudioDecoding,
        writer: any SubtitleWriting, translator: (any Translating)?, sleeper: any Sleeper
    ) {
        self.transcription = transcription
        self.models = models
        self.decoder = decoder
        self.writer = writer
        self.translator = translator
        self.sleeper = sleeper
    }

    // MARK: Queue editing

    /// Adds files (folders are expanded to the media they contain); duplicates are ignored.
    public func add(_ urls: [URL]) {
        for url in MediaFiles.expand(urls) where !jobs.contains(where: { $0.url == url }) {
            jobs.append(Job(url: url))
        }
    }

    public func remove(_ job: Job) { jobs.removeAll { $0.id == job.id } }
    public func clearFinished() { jobs.removeAll(where: \.isFinished) }

    /// True when at least one job still needs (re)processing.
    public var hasPendingWork: Bool { jobs.contains { $0.status != .done } }

    // MARK: Running

    /// Processes every queued job (failed and stopped jobs are retried). Returns the run's task.
    @discardableResult
    public func start(_ config: PipelineConfig) -> Task<Void, Never>? {
        guard !isRunning else { return nil }
        for i in jobs.indices where jobs[i].status.isRetryable { jobs[i].status = .queued }
        isRunning = true
        unloadTask?.cancel()
        let task = Task {
            await runQueue(config)
            isRunning = false
            scheduleUnload(after: config.settings.unloadTimeout)
        }
        runTask = task
        return task
    }

    public func cancel() { runTask?.cancel() }

    /// Frees model memory after the configured idle time (HandyAI's "model unload timeout").
    func scheduleUnload(after timeout: UnloadTimeout) {
        unloadTask?.cancel()
        guard timeout != .never else { return }
        unloadTask = Task {
            try? await sleeper.sleep(seconds: Double(timeout.rawValue))
            guard !Task.isCancelled, !isRunning else { return }
            await transcription.unload()
        }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { change(&jobs[i]) }
    }

    private func runQueue(_ config: PipelineConfig) async {
        while let job = jobs.first(where: { $0.status == .queued }) {
            guard !Task.isCancelled else {
                for i in jobs.indices where jobs[i].status == .queued { jobs[i].status = .cancelled }
                return
            }
            await process(job, config)
        }
    }

    private func process(_ job: Job, _ config: PipelineConfig) async {
        let id = job.id
        do {
            try await prepareModel(for: id, config)

            update(id) { $0.status = .decoding }
            let samples = try await decoder.decode(job.url)
            try Task.checkCancellation()
            guard !samples.isEmpty else { throw AudioLoader.LoadError.noAudioTrack }

            update(id) { $0.status = .transcribing(0) }
            let request = TranscriptionRequest(
                language: config.language, translate: config.translateToEnglish, settings: config.settings)
            let output = try await transcription.transcribe(samples: samples, request: request) { value in
                Task { @MainActor in
                    self.update(id) { if case .transcribing = $0.status { $0.status = .transcribing(value) } }
                }
            }
            update(id) { $0.detectedLanguage = output.language }
            guard !output.cues.isEmpty else { throw TranscriptionError.noSpeech }

            let primary = try writer.write(
                output.cues, for: job.url, suffix: config.translateToEnglish ? "en" : nil, folder: config.outputFolder)
            update(id) { $0.outputs.append(primary) }

            let textLanguage = config.translateToEnglish ? "en" : output.language
            try await translate(output.cues, from: textLanguage, job: job, config)
            update(id) { $0.status = .done }
        } catch {
            let cancelled = error is CancellationError || Task.isCancelled
            update(id) { $0.status = cancelled ? .cancelled : .failed(error.localizedDescription) }
        }
    }

    private func prepareModel(for id: UUID, _ config: PipelineConfig) async throws {
        if !models.isDownloaded(config.model) {
            update(id) { $0.status = .downloadingModel(0) }
            try await models.download(config.model) { value in
                self.update(id) { $0.status = .downloadingModel(value) }
            }
        }
        update(id) { $0.status = .loadingModel }
        try await transcription.load(config.model, compute: config.settings.compute)
    }

    /// Extra subtitle files via on-device translation. Failures become per-job warnings.
    private func translate(_ cues: [SubtitleCue], from source: String, job: Job, _ config: PipelineConfig) async throws {
        guard let translator else { return }
        let sourceCode = Locale.Language(identifier: source).languageCode
        let texts = cues.map { $0.text.replacingOccurrences(of: "\n", with: " ") }
        for target in config.extraTargets where Locale.Language(identifier: target).languageCode != sourceCode {
            try Task.checkCancellation()
            let name = Languages.displayName(target)
            update(job.id) { $0.status = .translating(name) }
            do {
                let translated = try await translator.translate(texts, from: source, to: target)
                let lineLength = config.settings.maxLineLength
                let out = zip(cues, translated).map {
                    SubtitleCue(start: $0.start, end: $0.end,
                                text: SRTWriter.wrap(CueBuilder.clean($1), maxLine: lineLength))
                }
                let url = try writer.write(out, for: job.url, suffix: target, folder: config.outputFolder)
                update(job.id) { $0.outputs.append(url) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                update(job.id) { $0.warnings.append("\(name): \(error.localizedDescription)") }
            }
        }
    }
}
