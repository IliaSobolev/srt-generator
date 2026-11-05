import Foundation
import Observation

/// All live dependencies, injected once at app start (see the composition root in the app target).
public struct AppDependencies {
    public var registry: ModelRegistry
    public var decoder: any AudioDecoding
    public var writer: any SubtitleWriting
    public var translator: (any Translating)?
    public var picker: any FilePicking
    public var sleeper: any Sleeper
    public var defaults: UserDefaults
    /// Spoken-language table (`name → ISO code`), e.g. WhisperKit's `Constants.languages`.
    public var languageTable: [String: String]

    public init(
        registry: ModelRegistry, decoder: any AudioDecoding, writer: any SubtitleWriting = SubtitleFileWriter(),
        translator: (any Translating)?, picker: any FilePicking, sleeper: any Sleeper = TaskSleeper(),
        defaults: UserDefaults = .standard, languageTable: [String: String]
    ) {
        self.registry = registry
        self.decoder = decoder
        self.writer = writer
        self.translator = translator
        self.picker = picker
        self.sleeper = sleeper
        self.defaults = defaults
        self.languageTable = languageTable
    }
}

/// App-wide coordinator: persisted user preferences plus the model and job services the views use.
@MainActor @Observable
public final class AppState {
    enum Keys {
        static let model = "modelID"
        static let language = "language"
        static let outputMode = "outputMode"
        static let extraTargets = "extraTargets"
        static let outputFolder = "outputFolder"
    }

    // MARK: Preferences (persisted)

    public var model: ModelInfo {
        didSet {
            defaults.set(model.id, forKey: Keys.model)
            if languageCode != "auto", !model.supportsLanguage(languageCode) { languageCode = "auto" }
            if !model.supportsTranslation, outputMode == .english { outputMode = .original }
        }
    }
    /// "auto" or an ISO code.
    public var languageCode: String { didSet { defaults.set(languageCode, forKey: Keys.language) } }
    public var outputMode: OutputMode { didSet { defaults.set(outputMode.rawValue, forKey: Keys.outputMode) } }
    public var extraTargets: Set<String> { didSet { defaults.set(extraTargets.sorted(), forKey: Keys.extraTargets) } }
    public var outputFolder: URL? { didSet { defaults.set(outputFolder?.path, forKey: Keys.outputFolder) } }
    public var settings: TranscriptionSettings { didSet { settings.save(defaults) } }

    // MARK: Services

    public let models: ModelManager
    public let queue: JobQueue
    public let translator: (any Translating)?
    public let languageOptions: [LanguageOption]
    public let supportsAllFormats: Bool
    public private(set) var translationTargets: [String] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let picker: any FilePicking

    public init(_ deps: AppDependencies) {
        defaults = deps.defaults
        picker = deps.picker
        translator = deps.translator
        supportsAllFormats = deps.decoder.supportsAllFormats
        languageOptions = Languages.options(from: deps.languageTable)
        models = ModelManager(registry: deps.registry)
        queue = JobQueue(
            transcription: TranscriptionService(registry: deps.registry), models: models, decoder: deps.decoder,
            writer: deps.writer, translator: deps.translator, sleeper: deps.sleeper)

        let d = deps.defaults
        model = ModelCatalog.model(id: d.string(forKey: Keys.model) ?? "") ?? ModelCatalog.defaultModel
        languageCode = d.string(forKey: Keys.language) ?? "auto"
        outputMode = OutputMode(rawValue: d.string(forKey: Keys.outputMode) ?? "") ?? .original
        extraTargets = Set(d.stringArray(forKey: Keys.extraTargets) ?? [])
        outputFolder = d.string(forKey: Keys.outputFolder).map { URL(fileURLWithPath: $0) }
        settings = TranscriptionSettings.load(d)
    }

    /// Spoken-language hint the active model can actually use (nil = auto-detect).
    public var effectiveLanguage: String? {
        languageCode == "auto" || !model.supportsLanguage(languageCode) ? nil : languageCode
    }

    /// Spoken languages the active model accepts.
    public var languageChoices: [LanguageOption] { Languages.options(languageOptions, for: model) }

    public var pipelineConfig: PipelineConfig {
        PipelineConfig(
            model: model, language: effectiveLanguage, translateToEnglish: outputMode == .english,
            extraTargets: extraTargets.sorted(), outputFolder: outputFolder, settings: settings)
    }

    @discardableResult
    public func start() -> Task<Void, Never>? { queue.start(pipelineConfig) }

    public func loadTranslationTargets() async {
        let targets = await translator?.supportedTargets() ?? []
        translationTargets = targets.sorted { Languages.displayName($0) < Languages.displayName($1) }
    }

    public func setTarget(_ id: String, enabled: Bool) {
        if enabled { extraTargets.insert(id) } else { extraTargets.remove(id) }
    }

    public func presentOpenPanel() { queue.add(picker.pickMedia()) }

    public func chooseOutputFolder() {
        if let url = picker.pickFolder() { outputFolder = url }
    }

    /// One-click "download if needed, then use" for a model.
    @discardableResult
    public func use(_ model: ModelInfo) -> Task<Void, Never>? {
        models.downloadAndUse(model) { [weak self] in self?.model = $0 }
    }
}
