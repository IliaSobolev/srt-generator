import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import WhisperKit

struct Job: Identifiable, Hashable {
    enum Status: Hashable {
        case queued
        case downloadingModel(Double)
        case loadingModel
        case decoding
        case transcribing(Double)
        case translating(String)
        case done
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let url: URL
    var status: Status = .queued
    var outputs: [URL] = []
    var detectedLanguage: String?
    var warnings: [String] = []

    var isFinished: Bool {
        switch status {
        case .done, .failed, .cancelled: true
        default: false
        }
    }
}

enum OutputMode: String, CaseIterable, Identifiable {
    case original, english
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Original language"
        case .english: "Translate to English (Whisper)"
        }
    }
}

@MainActor @Observable
final class AppState {
    // MARK: Settings (persisted)
    var model: ModelInfo { didSet { defaults.set(model.id, forKey: "modelID") } }
    var languageCode: String { didSet { defaults.set(languageCode, forKey: "language") } } // "auto" or ISO
    var outputMode: OutputMode { didSet { defaults.set(outputMode.rawValue, forKey: "outputMode") } }
    var extraTargets: Set<String> { didSet { defaults.set(Array(extraTargets), forKey: "extraTargets") } }
    var outputFolder: URL? { didSet { defaults.set(outputFolder?.path, forKey: "outputFolder") } }

    // MARK: Runtime
    var jobs: [Job] = []
    var isRunning = false
    var downloadedModels: Set<String> = []
    var modelDownloads: [String: Double] = [:]
    var modelDownloadErrors: [String: String] = [:]
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    var translationTargets: [Locale.Language] = []
    var lastError: String?
    let translator = TranslationBridge()
    let ffmpegAvailable = AudioLoader.ffmpegURL != nil

    private let transcriber = Transcriber()
    private var runTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    static let whisperLanguages: [(name: String, code: String)] = Constants.languages
        .map { (name: $0.key.capitalized, code: $0.value) }
        .reduce(into: [String: String]()) { acc, item in acc[item.code] = acc[item.code] ?? item.name }
        .map { (name: $0.value, code: $0.key) }
        .sorted { $0.name < $1.name }

    init() {
        model = ModelCatalog.model(id: defaults.string(forKey: "modelID") ?? "") ?? ModelCatalog.model(id: ModelCatalog.defaultID)!
        languageCode = defaults.string(forKey: "language") ?? "auto"
        outputMode = OutputMode(rawValue: defaults.string(forKey: "outputMode") ?? "") ?? .original
        extraTargets = Set(defaults.stringArray(forKey: "extraTargets") ?? [])
        outputFolder = defaults.string(forKey: "outputFolder").map { URL(fileURLWithPath: $0) }
        refreshModels()
        Task { translationTargets = await TranslationBridge.supportedTargets() }
    }

    // MARK: Files

    func add(_ urls: [URL]) {
        let existing = Set(jobs.map(\.url))
        for url in urls where !existing.contains(url) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                add(mediaFiles(in: url))
            } else {
                jobs.append(Job(url: url))
            }
        }
    }

    private func mediaFiles(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.contentTypeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        return e.compactMap { $0 as? URL }.filter { url in
            guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
            return type.conforms(to: .audiovisualContent)
                || ["mkv", "webm", "opus", "ogg", "flv", "wma", "ts", "mts", "m2ts"].contains(url.pathExtension.lowercased())
        }.sorted { $0.path < $1.path }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose audio or video files (any format)"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK { outputFolder = panel.url }
    }

    func remove(_ job: Job) { jobs.removeAll { $0.id == job.id } }
    func clearFinished() { jobs.removeAll { $0.isFinished } }

    // MARK: Models

    func refreshModels() {
        downloadedModels = Set(ModelCatalog.all.filter(Transcriber.isDownloaded).map(\.id))
    }

    func download(_ m: ModelInfo) async throws {
        guard modelDownloads[m.id] == nil else { return }
        modelDownloads[m.id] = 0
        defer { modelDownloads[m.id] = nil; refreshModels() }
        try await Transcriber.download(m) { p in
            Task { @MainActor in if self.modelDownloads[m.id] != nil { self.modelDownloads[m.id] = p } }
        }
    }

    /// One-click flow: download the model if needed, then make it the active model.
    func downloadAndUse(_ m: ModelInfo) {
        modelDownloadErrors[m.id] = nil
        if downloadedModels.contains(m.id) {
            model = m
            return
        }
        guard downloadTasks[m.id] == nil else { return }
        downloadTasks[m.id] = Task {
            defer { downloadTasks[m.id] = nil }
            do {
                try await download(m)
                try Task.checkCancellation()
                if downloadedModels.contains(m.id) { model = m }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { modelDownloadErrors[m.id] = error.localizedDescription }
            }
        }
    }

    func cancelDownload(_ m: ModelInfo) {
        downloadTasks[m.id]?.cancel()
        downloadTasks[m.id] = nil
        modelDownloads[m.id] = nil
    }

    func deleteModel(_ m: ModelInfo) {
        try? Transcriber.delete(m)
        refreshModels()
    }

    // MARK: Pipeline

    func start() {
        guard !isRunning else { return }
        for i in jobs.indices where jobs[i].status == .cancelled || { if case .failed = jobs[i].status { true } else { false } }() {
            jobs[i].status = .queued
        }
        isRunning = true
        runTask = Task {
            await runQueue()
            isRunning = false
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    private func set(_ id: UUID, _ update: (inout Job) -> Void) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { update(&jobs[i]) }
    }

    private func runQueue() async {
        while let job = jobs.first(where: { $0.status == .queued }) {
            if Task.isCancelled {
                for i in jobs.indices where jobs[i].status == .queued { jobs[i].status = .cancelled }
                return
            }
            await process(job)
        }
    }

    private func process(_ job: Job) async {
        let id = job.id
        let model = model
        do {
            if !Transcriber.isDownloaded(model) {
                set(id) { $0.status = .downloadingModel(0) }
                let observer = Task {
                    while !Task.isCancelled {
                        if let p = modelDownloads[model.id] { set(id) { $0.status = .downloadingModel(p) } }
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                }
                defer { observer.cancel() }
                try await download(model)
            }
            set(id) { $0.status = .loadingModel }
            try await transcriber.load(model)

            set(id) { $0.status = .decoding }
            let samples = try await Task.detached(priority: .userInitiated) {
                try await AudioLoader.load(job.url)
            }.value
            try Task.checkCancellation()

            set(id) { $0.status = .transcribing(0) }
            let translate = outputMode == .english && model.supportsTranslation
            let output = try await transcriber.transcribe(
                samples: samples,
                language: languageCode == "auto" ? nil : languageCode,
                translate: translate
            ) { p in
                Task { @MainActor in self.set(id) { if case .transcribing = $0.status { $0.status = .transcribing(p) } } }
            }
            let spoken = output.language
            set(id) { $0.detectedLanguage = spoken }

            guard !output.cues.isEmpty else {
                set(id) { $0.status = .failed("No speech detected.") }
                return
            }

            let textLanguage = translate ? "en" : spoken
            let primary = try write(output.cues, for: job.url, suffix: translate ? "en" : nil)
            set(id) { $0.outputs.append(primary) }

            // Extra translations via Apple's on-device Translation framework.
            let source = Locale.Language(identifier: textLanguage)
            for target in extraTargets.sorted() where Locale.Language(identifier: target).languageCode != source.languageCode {
                try Task.checkCancellation()
                let targetLang = Locale.Language(identifier: target)
                set(id) { $0.status = .translating(TranslationBridge.displayName(targetLang)) }
                do {
                    let texts = output.cues.map { $0.text.replacingOccurrences(of: "\n", with: " ") }
                    let translated = try await translator.translate(texts, from: source, to: targetLang)
                    let cues = zip(output.cues, translated).map {
                        SubtitleCue(start: $0.start, end: $0.end, text: SRTWriter.wrap(CueBuilder.clean($1)))
                    }
                    let url = try write(cues, for: job.url, suffix: target)
                    set(id) { $0.outputs.append(url) }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let name = TranslationBridge.displayName(targetLang)
                    set(id) { $0.warnings.append("\(name): \(error.localizedDescription)") }
                }
            }
            set(id) { $0.status = .done }
        } catch is CancellationError {
            set(id) { $0.status = .cancelled }
        } catch {
            set(id) { $0.status = Task.isCancelled ? .cancelled : .failed(error.localizedDescription) }
        }
    }

    private func write(_ cues: [SubtitleCue], for source: URL, suffix: String?) throws -> URL {
        let folder = outputFolder ?? source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent + (suffix.map { ".\($0)" } ?? "")
        var url = folder.appendingPathComponent(stem).appendingPathExtension("srt")
        var n = 1
        // Never clobber an existing subtitle file.
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stem) (\(n))").appendingPathExtension("srt")
            n += 1
        }
        try SRTWriter.render(cues).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
