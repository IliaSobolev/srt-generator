import Foundation
import SRTCore

/// Headless mode: `SRTGenerator --cli [--model <id>] [--language auto|xx] [--english] [-o dir] files...`
/// Runs the same JobQueue pipeline as the app, without touching the app's saved preferences.
@MainActor
enum CLI {
    static func run(_ args: [String]) async -> Int32 {
        var model = ModelCatalog.defaultModel
        var language: String?
        var english = false
        var outDir: URL?
        var files: [URL] = []

        var it = args.makeIterator()
        while let a = it.next() {
            switch a {
            case "--model", "-m":
                let v = it.next() ?? ""
                guard let m = ModelCatalog.model(id: v) else {
                    return fail("Unknown model '\(v)'. Options: " + ModelCatalog.all.map(\.id).joined(separator: ", "))
                }
                model = m
            case "--language", "-l":
                let v = it.next() ?? "auto"
                language = v == "auto" ? nil : v
            case "--english", "-e": english = true
            case "--output", "-o": outDir = it.next().map { URL(fileURLWithPath: $0, isDirectory: true) }
            case "--help", "-h":
                print("Usage: SRTGenerator --cli [--model <id>] [--language auto|<iso>] [--english] [-o dir] <files...>")
                print("Models: " + ModelCatalog.all.map(\.id).joined(separator: ", "))
                return 0
            default: files.append(URL(fileURLWithPath: a))
            }
        }
        guard !files.isEmpty else { return fail("No input files.") }

        let deps = LiveDependencies.make(translation: false)
        let state = AppState(deps)
        let config = PipelineConfig(
            model: model, language: language, translateToEnglish: english,
            outputFolder: outDir, settings: TranscriptionSettings.load(deps.defaults))
        state.queue.add(files)
        FileHandle.standardError.write(Data("Transcribing with \(model.name)…\n".utf8))
        await state.queue.start(config)?.value

        var failed = false
        for job in state.queue.jobs {
            switch job.status {
            case .done:
                print(job.outputs.map(\.path).joined(separator: "\n") + "  [\(job.detectedLanguage ?? "?")]")
            default:
                failed = true
                FileHandle.standardError.write(Data("✗ \(job.url.lastPathComponent): \(job.status)\n".utf8))
            }
        }
        return failed ? 1 : 0
    }

    private static func fail(_ msg: String) -> Int32 {
        FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
        return 1
    }
}
