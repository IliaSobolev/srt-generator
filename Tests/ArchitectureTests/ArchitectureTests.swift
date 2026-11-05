import Foundation
import Testing

/// Structural rules from docs/ARCHITECTURE.md, checked by scanning the source tree.
/// These tests don't import app code; they read Sources/ and Tests/ as text.
@Suite("Architecture rules")
struct ArchitectureTests {
    // MARK: - Rules

    @Test("SRTCore imports only allowlisted system frameworks (no UI, no networking, no third-party)")
    func coreImports() throws {
        let allowed: Set = ["Foundation", "Observation", "AVFoundation", "NaturalLanguage", "Synchronization",
                            "UniformTypeIdentifiers", "CoreMedia"]
        let offenders = try Source.files(in: "Sources/SRTCore").flatMap { file in
            file.imports.filter { !allowed.contains($0) }.map { "\(file.path): import \($0)" }
        }
        #expect(offenders.isEmpty, "SRTCore must stay framework-light: \(offenders)")
    }

    @Test("Only SRTEngines imports the network-capable engine libraries")
    func engineLibrariesStayInAdapters() throws {
        let engineLibraries: Set = ["WhisperKit", "FluidAudio", "Hub", "ArgmaxCore", "Transformers", "Tokenizers"]
        let offenders = try Source.files(in: "Sources").filter { !$0.path.hasPrefix("Sources/SRTEngines/") }
            .flatMap { file in file.imports.filter(engineLibraries.contains).map { "\(file.path): import \($0)" } }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test("Every @Observable type is @MainActor (ViewModels are main-actor isolated)")
    func observablesAreMainActor() throws {
        let offenders = try Source.files(in: "Sources").flatMap { file in
            file.lines.enumerated().compactMap { index, line -> String? in
                guard line.contains("@Observable") else { return nil }
                let context = file.lines[max(0, index - 2)...index].joined(separator: " ")
                return context.contains("@MainActor") ? nil : "\(file.path):\(index + 1)"
            }
        }
        #expect(offenders.isEmpty, "Add @MainActor: \(offenders)")
    }

    @Test("Concrete adapters are only constructed in the composition root")
    func concreteTypesOnlyInCompositionRoot() throws {
        let concrete = ["WhisperProvider(", "ParakeetProvider(", "LiveEngines.", "TranslationBridge(",
                        "PanelFilePicker(", "AudioLoader("]
        let offenders = try Source.files(in: "Sources/SRTGenerator")
            .filter { $0.path != "Sources/SRTGenerator/LiveDependencies.swift" }
            .flatMap { file in concrete.filter(file.code.contains).map { "\(file.path): \($0)" } }
        #expect(offenders.isEmpty, "Inject through AppDependencies instead: \(offenders)")
    }

    @Test("LiveDependencies is only used by the app and CLI entry points")
    func compositionRootEntryPoints() throws {
        let entryPoints: Set = ["Sources/SRTGenerator/SRTGeneratorApp.swift", "Sources/SRTGenerator/CLI.swift",
                                "Sources/SRTGenerator/LiveDependencies.swift"]
        let offenders = try Source.files(in: "Sources").filter { $0.code.contains("LiveDependencies") }
            .map(\.path).filter { !entryPoints.contains($0) }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test("Views hold no business logic: no persistence, file system, processes or coding")
    func viewsHaveNoBusinessLogic() throws {
        let forbidden = ["FileManager", "UserDefaults", "JSONEncoder", "JSONDecoder", "Process(", "Task.sleep",
                         "DispatchQueue"]
        // Known violations, each with a ticket-style note. Remove the entry when it's fixed; don't add new ones.
        let baseline: Set = [
            // Creates the model folder before revealing it in Finder; belongs in ModelManager (needs approval).
            "Sources/SRTGenerator/SettingsView.swift: FileManager",
        ]
        let views = try Source.files(in: "Sources/SRTGenerator").filter { $0.path.hasSuffix("View.swift") }
        #expect(!views.isEmpty)
        let found = Set(views.flatMap { file in forbidden.filter(file.code.contains).map { "\(file.path): \($0)" } })
        #expect(found.subtracting(baseline).isEmpty, "Move this logic into SRTCore: \(found.subtracting(baseline))")
        #expect(baseline.subtracting(found).isEmpty, "Fixed! Remove from the baseline: \(baseline.subtracting(found))")
    }

    @Test("Tests never use the network: no networking APIs and no remote URLs")
    func testsAreOffline() throws {
        let apis = ["URLSession", "NWConnection", "URLRequest", "WKWebView"]
        let remoteURLs = ["http://", "https://"] // matched in raw text, since URLs live inside string literals
        let offenders = try Source.files(in: "Tests").filter { !$0.path.hasPrefix("Tests/ArchitectureTests/") }
            .flatMap { file in
                let raw = file.lines.joined(separator: "\n")
                return (apis.filter(file.code.contains) + remoteURLs.filter(raw.contains)).map { "\(file.path): \($0)" }
            }
        #expect(offenders.isEmpty, "Use fakes or a URLProtocol stub with file fixtures: \(offenders)")
    }

    // MARK: - Self-checks for the scanner

    @Test("Scanner strips comments and string literals before matching")
    func scannerIgnoresCommentsAndStrings() {
        let file = Source(path: "x.swift", text: """
        import Foundation // import SwiftUI
        /// Uses URLSession? No.
        let s = "FileManager"
        let real = FileManager.default
        """)
        #expect(file.imports == ["Foundation"])
        #expect(!file.code.contains("URLSession"))
        #expect(file.code.components(separatedBy: "FileManager").count == 2)
    }

    @Test("Scanner finds the package sources")
    func scannerSeesSources() throws {
        let core = try Source.files(in: "Sources/SRTCore")
        #expect(core.contains { $0.path == "Sources/SRTCore/AppState.swift" })
        #expect(core.allSatisfy { $0.path.hasSuffix(".swift") })
    }
}

/// A Swift source file with comments and string literals stripped, for simple structural checks.
struct Source {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    let path: String
    let lines: [String]
    /// The file with comments and string-literal contents removed.
    let code: String

    init(path: String, text: String) {
        self.path = path
        lines = text.components(separatedBy: "\n")
        code = Self.strip(text)
    }

    var imports: [String] {
        code.components(separatedBy: "\n").compactMap { line in
            let words = line.split(separator: " ").map(String.init).filter { !$0.hasPrefix("@") }
            return words.first == "import" && words.count > 1 ? words[1] : nil
        }
    }

    static func files(in directory: String) throws -> [Source] {
        let base = root.appendingPathComponent(directory)
        let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        let urls = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        return try urls.map { url in
            let relative = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            return try Source(path: relative, text: String(contentsOf: url, encoding: .utf8))
        }.sorted { $0.path < $1.path }
    }

    /// Removes `//` and `/* */` comments and the contents of string literals (keeps the quotes).
    /// One pass, so `//` inside a string (`"https://…"`) isn't mistaken for a comment.
    private static let literalsAndComments = #/"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"|/\*[\s\S]*?\*/|//[^\n]*/#

    private static func strip(_ text: String) -> String {
        text.replacing(literalsAndComments) { match in match.output.hasPrefix("\"") ? "\"\"" : "" }
    }
}
