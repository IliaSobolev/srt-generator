import Foundation
import Observation

/// Download state for the model catalog; drives the Settings → Models UI.
@MainActor @Observable
public final class ModelManager {
    public let catalog: [ModelInfo]
    public private(set) var downloaded: Set<String> = []
    /// Download progress (0...1) for models currently downloading.
    public private(set) var progress: [String: Double] = [:]
    public private(set) var errors: [String: String] = [:]

    @ObservationIgnored private let registry: ModelRegistry
    @ObservationIgnored private var tasks: [String: (token: UUID, task: Task<Void, Never>)] = [:]

    public init(registry: ModelRegistry, catalog: [ModelInfo] = ModelCatalog.all) {
        self.registry = registry
        self.catalog = catalog
        refresh()
    }

    public func refresh() {
        downloaded = Set(catalog.filter { registry.provider(for: $0).isDownloaded($0) }.map(\.id))
    }

    public func isDownloaded(_ model: ModelInfo) -> Bool {
        registry.provider(for: model).isDownloaded(model)
    }

    public func isDownloading(_ model: ModelInfo) -> Bool { progress[model.id] != nil }

    public func folder(for model: ModelInfo) -> URL { registry.provider(for: model).folder(for: model) }

    /// Downloads a model, reporting progress both to `progress` and to `onProgress`.
    public func download(_ model: ModelInfo, onProgress: (@MainActor (Double) -> Void)? = nil) async throws {
        guard progress[model.id] == nil else { throw TranscriptionError.alreadyDownloading(model.name) }
        progress[model.id] = 0
        defer {
            progress[model.id] = nil
            refresh()
        }
        try await registry.provider(for: model).download(model) { value in
            Task { @MainActor in self.report(value, for: model.id, onProgress) }
        }
        guard isDownloaded(model) else { throw TranscriptionError.downloadIncomplete(model.name) }
    }

    private func report(_ value: Double, for id: String, _ onProgress: (@MainActor (Double) -> Void)?) {
        guard progress[id] != nil else { return }
        progress[id] = value
        onProgress?(value)
    }

    /// One-click flow: download the model if needed, then hand it to `use`.
    /// Returns the download task (nil when the model was already available).
    @discardableResult
    public func downloadAndUse(_ model: ModelInfo, use: @escaping @MainActor (ModelInfo) -> Void) -> Task<Void, Never>? {
        errors[model.id] = nil
        if downloaded.contains(model.id) {
            use(model)
            return nil
        }
        if let existing = tasks[model.id] { return existing.task }
        let token = UUID()
        let task = Task {
            defer { if tasks[model.id]?.token == token { tasks[model.id] = nil } }
            do {
                try await download(model)
                try Task.checkCancellation()
                use(model)
            } catch {
                if !Task.isCancelled { errors[model.id] = error.localizedDescription }
            }
        }
        tasks[model.id] = (token, task)
        return task
    }

    public func cancelDownload(_ model: ModelInfo) {
        tasks.removeValue(forKey: model.id)?.task.cancel()
        progress[model.id] = nil
    }

    public func delete(_ model: ModelInfo) {
        do {
            try registry.provider(for: model).delete(model)
            errors[model.id] = nil
        } catch {
            errors[model.id] = error.localizedDescription
        }
        refresh()
    }
}
