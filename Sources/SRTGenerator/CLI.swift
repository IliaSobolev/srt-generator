import Foundation

/// Headless mode: `SRTGenerator --cli [--model small] [--language auto|xx] [--english] [-o dir] files...`
enum CLI {
    static func run(_ args: [String]) async {
        var model = WhisperModel.turboCompact
        var language: String?
        var english = false
        var outDir: URL?
        var files: [URL] = []

        var it = args.makeIterator()
        while let a = it.next() {
            switch a {
            case "--model", "-m":
                let v = it.next() ?? ""
                guard let m = WhisperModel.allCases.first(where: { $0.rawValue.hasSuffix(v) || $0.rawValue == v }) else {
                    fail("Unknown model '\(v)'. Options: tiny, base, small, 626MB, turbo, large-v3")
                }
                model = m
            case "--language", "-l":
                let v = it.next() ?? "auto"
                language = v == "auto" ? nil : v
            case "--english", "-e": english = true
            case "--output", "-o": outDir = it.next().map { URL(fileURLWithPath: $0, isDirectory: true) }
            case "--help", "-h":
                print("Usage: SRTGenerator --cli [--model tiny|base|small|626MB|turbo|large-v3] [--language auto|<iso>] [--english] [-o dir] <files...>")
                exit(0)
            default: files.append(URL(fileURLWithPath: a))
            }
        }
        guard !files.isEmpty else { fail("No input files.") }

        do {
            if !Transcriber.isDownloaded(model) {
                FileHandle.standardError.write("Downloading \(model.title)…\n")
                try await Transcriber.download(model) { _ in }
            }
            FileHandle.standardError.write("Loading \(model.title)…\n")
            let t = Transcriber()
            try await t.load(model)
            for file in files {
                FileHandle.standardError.write("→ \(file.lastPathComponent)\n")
                let samples = try await AudioLoader.load(file)
                let out = try await t.transcribe(samples: samples, language: language, translate: english) { _ in }
                let dir = outDir ?? file.deletingLastPathComponent()
                let dest = dir.appendingPathComponent(file.deletingPathExtension().lastPathComponent + (english ? ".en" : ""))
                    .appendingPathExtension("srt")
                try SRTWriter.render(out.cues).write(to: dest, atomically: true, encoding: .utf8)
                print("\(dest.path)  [\(out.language), \(out.cues.count) cues]")
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func fail(_ msg: String) -> Never {
        FileHandle.standardError.write("error: \(msg)\n")
        exit(1)
    }
}

extension FileHandle {
    func write(_ s: String) { write(Data(s.utf8)) }
}
