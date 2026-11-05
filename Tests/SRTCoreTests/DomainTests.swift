import Foundation
@testable import SRTCore
import Testing

@Suite("Model catalog")
struct ModelCatalogTests {
    @Test("Mirrors HandyAI's six models in order")
    func handyAIList() {
        #expect(ModelCatalog.all.map(\.id) == [
            "small", "medium", "turbo", "large", "parakeet-tdt-0.6b-v2", "parakeet-tdt-0.6b-v3",
        ])
        #expect(ModelCatalog.defaultModel.id == ModelCatalog.defaultID)
        #expect(ModelCatalog.model(id: "turbo")?.name == "Whisper Turbo")
        #expect(ModelCatalog.model(id: "missing") == nil)
    }

    @Test("Size text uses MB below 1000 and GB above", arguments: [(486, "486 MB"), (1529, "1.5 GB"), (1000, "1.0 GB")])
    func sizeText(mb: Int, expected: String) {
        let m = ModelInfo(id: "x", name: "X", description: "", sizeMB: mb, engine: .whisper, accuracy: 0, speed: 0,
                          languages: "", supportsTranslation: false, supportsLanguageSelection: true,
                          whisperVariant: nil)
        #expect(m.sizeText == expected)
        #expect(m.id == "x")
    }

    @Test("Language support depends on selection flag and code list")
    func supportsLanguage() {
        #expect(Fixtures.whisper.supportsLanguage("uk"))
        #expect(Fixtures.parakeetV3.supportsLanguage("uk"))
        #expect(!Fixtures.parakeetV3.supportsLanguage("ja"))
        #expect(!Fixtures.parakeetV2.supportsLanguage("en"))
    }

    @Test("Engine titles", arguments: EngineType.allCases)
    func engineTitle(engine: EngineType) {
        #expect(engine.title == (engine == .whisper ? "Whisper" : "Parakeet"))
    }
}

@Suite("Transcription settings")
struct TranscriptionSettingsTests {
    @Test("Defaults")
    func defaults() {
        let s = TranscriptionSettings()
        #expect(s.customWords.isEmpty)
        #expect(s.unloadTimeout == .min5)
        #expect(s.compute == .neuralEngine)
        #expect(s.whisperVAD && s.whisperTemperatureFallback && s.whisperSuppressNonSpeech)
        #expect(s.cueBuilder == CueBuilder(maxLineLength: 42, maxDuration: 7))
    }

    @Test("Round-trips through UserDefaults")
    func roundTrip() {
        let d = Fixtures.defaults()
        #expect(TranscriptionSettings.load(d) == TranscriptionSettings())
        var s = TranscriptionSettings()
        s.customWords = ["Kyiv"]
        s.unloadTimeout = .hour1
        s.compute = .gpu
        s.whisperVAD = false
        s.whisperTemperatureFallback = false
        s.whisperSuppressNonSpeech = false
        s.maxLineLength = 30
        s.maxCueDuration = 4
        s.save(d)
        #expect(TranscriptionSettings.load(d) == s)
    }

    @Test("Missing keys fall back to defaults; corrupt data loads defaults")
    func tolerantDecoding() throws {
        let partial = try JSONDecoder().decode(TranscriptionSettings.self, from: Data(#"{"maxLineLength":30}"#.utf8))
        var expected = TranscriptionSettings()
        expected.maxLineLength = 30
        #expect(partial == expected)

        #expect(try JSONDecoder().decode(TranscriptionSettings.self, from: Data("{}".utf8)) == TranscriptionSettings())

        let d = Fixtures.defaults()
        d.set(Data("not json".utf8), forKey: TranscriptionSettings.key)
        #expect(TranscriptionSettings.load(d) == TranscriptionSettings())
    }

    @Test("Compute target titles", arguments: ComputeTarget.allCases)
    func computeTitles(target: ComputeTarget) {
        #expect(!target.title.isEmpty)
        #expect(target.id == target.rawValue)
    }

    @Test("Unload timeout titles", arguments: zip(UnloadTimeout.allCases, [
        "Never", "Immediately after a batch", "After 2 minutes", "After 5 minutes", "After 15 minutes", "After 1 hour",
    ]))
    func unloadTitles(timeout: UnloadTimeout, title: String) {
        #expect(timeout.title == title)
        #expect(timeout.id == timeout.rawValue)
    }
}

@Suite("Jobs and pipeline config")
struct JobTests {
    @Test("Finished and retryable states", arguments: [
        (Job.Status.queued, false, false), (.downloadingModel(0.5), false, false), (.loadingModel, false, false),
        (.decoding, false, false), (.transcribing(0.1), false, false), (.translating("German"), false, false),
        (.done, true, false), (.failed("x"), true, true), (.cancelled, true, true),
    ])
    func states(status: Job.Status, finished: Bool, retryable: Bool) {
        var job = Job(url: URL(fileURLWithPath: "/a.mp4"))
        job.status = status
        #expect(job.isFinished == finished)
        #expect(status.isRetryable == retryable)
    }

    @Test("Output modes")
    func outputModes() {
        #expect(OutputMode.allCases.map(\.id) == ["original", "english"])
        #expect(OutputMode.original.title == "Original language")
        #expect(OutputMode.english.title == "Translate to English (Whisper)")
    }

    @Test("Translation to English is dropped for models that cannot translate")
    func configTranslate() {
        #expect(PipelineConfig(model: Fixtures.whisper, translateToEnglish: true).translateToEnglish)
        #expect(!PipelineConfig(model: Fixtures.parakeetV3, translateToEnglish: true).translateToEnglish)
    }

    @Test("Error descriptions")
    func errors() {
        #expect(TranscriptionError.modelNotLoaded.errorDescription == "No model is loaded.")
        #expect(TranscriptionError.alreadyDownloading("X").errorDescription == "X is still downloading.")
        #expect(TranscriptionError.downloadIncomplete("X").errorDescription?.hasPrefix("X did not finish") == true)
        #expect(TranscriptionError.noSpeech.errorDescription == "No speech detected.")
        #expect(AudioLoader.LoadError.noAudioTrack.errorDescription == "The file has no audio track.")
        #expect(AudioLoader.LoadError.decodeFailed("x").errorDescription == "Could not decode audio: x")
    }
}

@Suite("Languages")
struct LanguagesTests {
    @Test("Options are de-duplicated by code, capitalized and sorted")
    func options() {
        let table = ["spanish": "es", "castilian": "es", "english": "en", "german": "de"]
        let options = Languages.options(from: table)
        #expect(options == [
            LanguageOption(name: "Castilian", code: "es"), LanguageOption(name: "English", code: "en"),
            LanguageOption(name: "German", code: "de"),
        ])
    }

    @Test("Options are filtered to what a model supports")
    func filtered() {
        let all = [LanguageOption(name: "English", code: "en"), LanguageOption(name: "Japanese", code: "ja")]
        #expect(Languages.options(all, for: Fixtures.whisper) == all)
        #expect(Languages.options(all, for: Fixtures.parakeetV3).map(\.code) == ["en"])
    }

    @Test("Display names are localized")
    func displayName() {
        let en = Locale(identifier: "en_US")
        #expect(Languages.displayName("de", locale: en) == "German")
        #expect(Languages.displayName("uk", locale: en) == "Ukrainian")
        #expect(Languages.displayName("", locale: en) == "")
    }

    @Test("Detects the dominant language of a transcript")
    func detect() {
        #expect(Languages.detect(in: "Guten Tag, dies ist ein Test des Untertitelgenerators.") == "de")
        #expect(Languages.detect(in: "", fallback: "xx") == "xx")
    }
}
