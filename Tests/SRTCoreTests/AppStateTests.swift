import Foundation
import Testing
@testable import SRTCore

@MainActor
@Suite("App state")
struct AppStateTests {
    let defaults = Fixtures.defaults()
    let provider = FakeProvider(downloaded: ["small"])
    let picker = FakePicker()
    let translator = FakeTranslator()
    let languageTable = ["english": "en", "ukrainian": "uk", "japanese": "ja", "german": "de"]

    func makeState(translator: FakeTranslator?? = nil) -> AppState {
        AppState(AppDependencies(
            registry: ModelRegistry(whisper: provider, parakeet: provider),
            decoder: FakeDecoder(supportsAllFormats: false),
            writer: FakeWriter(),
            translator: translator ?? self.translator,
            picker: picker,
            sleeper: ImmediateSleeper(),
            defaults: defaults,
            languageTable: languageTable))
    }

    @Test("Fresh install uses defaults")
    func defaultsOnFirstLaunch() {
        let state = makeState()
        #expect(state.model == ModelCatalog.defaultModel)
        #expect(state.languageCode == "auto")
        #expect(state.outputMode == .original)
        #expect(state.extraTargets.isEmpty)
        #expect(state.outputFolder == nil)
        #expect(state.settings == TranscriptionSettings())
        #expect(!state.supportsAllFormats)
        #expect(state.languageOptions.map(\.code) == ["en", "de", "ja", "uk"])
        #expect(state.models.downloaded == ["small"])
    }

    @Test("Every preference persists and is restored")
    func persistence() {
        let state = makeState()
        state.model = ModelCatalog.model(id: "turbo")!
        state.languageCode = "uk"
        state.outputMode = .english
        state.extraTargets = ["de", "fr"]
        state.outputFolder = URL(fileURLWithPath: "/tmp/subs")
        state.settings.maxLineLength = 30

        let restored = makeState()
        #expect(restored.model.id == "turbo")
        #expect(restored.languageCode == "uk")
        #expect(restored.outputMode == .english)
        #expect(restored.extraTargets == ["de", "fr"])
        #expect(restored.outputFolder == URL(fileURLWithPath: "/tmp/subs"))
        #expect(restored.settings.maxLineLength == 30)
    }

    @Test("An unknown saved model falls back to the default")
    func unknownModel() {
        defaults.set("gone", forKey: AppState.Keys.model)
        #expect(makeState().model == ModelCatalog.defaultModel)
    }

    @Test("Switching models drops options the new model cannot use")
    func modelSwitch() {
        let state = makeState()
        state.languageCode = "ja"
        state.outputMode = .english
        state.model = Fixtures.parakeetV3
        #expect(state.languageCode == "auto")
        #expect(state.outputMode == .original)

        state.languageCode = "uk"
        state.model = Fixtures.whisper
        #expect(state.languageCode == "uk")
    }

    @Test("Language hint and choices follow the active model")
    func languages() {
        let state = makeState()
        #expect(state.effectiveLanguage == nil)
        state.languageCode = "ja"
        #expect(state.effectiveLanguage == "ja")
        #expect(state.languageChoices.count == 4)
        state.model = Fixtures.parakeetV3
        #expect(state.languageChoices.map(\.code) == ["en", "de", "uk"])
    }

    @Test("Builds the pipeline configuration from preferences")
    func config() {
        let state = makeState()
        state.languageCode = "de"
        state.outputMode = .english
        state.extraTargets = ["fr", "ja"]
        state.outputFolder = URL(fileURLWithPath: "/o")
        #expect(state.pipelineConfig == PipelineConfig(
            model: Fixtures.whisper, language: "de", translateToEnglish: true, extraTargets: ["fr", "ja"],
            outputFolder: URL(fileURLWithPath: "/o"), settings: TranscriptionSettings()))
    }

    @Test("Start runs the queue")
    func start() async {
        let state = makeState()
        state.queue.add([URL(fileURLWithPath: "/m/a.mp4")])
        await state.start()?.value
        #expect(state.queue.jobs[0].status == .done)
    }

    @Test("Translation targets are loaded and sorted by name; none without a translator")
    func targets() async {
        translator.targets = ["ja", "de", "fr"]
        let state = makeState()
        await state.loadTranslationTargets()
        #expect(state.translationTargets == ["fr", "de", "ja"].sorted {
            Languages.displayName($0) < Languages.displayName($1)
        })
        let none = makeState(translator: .some(nil))
        await none.loadTranslationTargets()
        #expect(none.translationTargets.isEmpty)
        #expect(none.translator == nil)
    }

    @Test("Toggling extra translation targets")
    func toggleTargets() {
        let state = makeState()
        state.setTarget("de", enabled: true)
        state.setTarget("fr", enabled: true)
        state.setTarget("de", enabled: false)
        #expect(state.extraTargets == ["fr"])
    }

    @Test("File and folder pickers feed the queue and output folder")
    func pickers() {
        let state = makeState()
        picker.media = [URL(fileURLWithPath: "/m/a.mp4"), URL(fileURLWithPath: "/m/b.wav")]
        state.presentOpenPanel()
        #expect(state.queue.jobs.count == 2)

        state.chooseOutputFolder()
        #expect(state.outputFolder == nil)
        picker.folder = URL(fileURLWithPath: "/chosen")
        state.chooseOutputFolder()
        #expect(state.outputFolder == URL(fileURLWithPath: "/chosen"))
    }

    @Test("Using a model downloads it if needed, then activates it")
    func useModel() async {
        let state = makeState()
        #expect(state.use(Fixtures.whisper) == nil)
        await state.use(Fixtures.parakeetV2)?.value
        #expect(state.model == Fixtures.parakeetV2)
    }

    @Test("Default dependency arguments")
    func dependencyDefaults() {
        let deps = AppDependencies(
            registry: ModelRegistry(whisper: provider, parakeet: provider), decoder: FakeDecoder(),
            translator: nil, picker: picker, languageTable: [:])
        #expect(deps.writer is SubtitleFileWriter)
        #expect(deps.sleeper is TaskSleeper)
        #expect(deps.defaults == .standard)
        #expect(deps.translator == nil)
    }
}
