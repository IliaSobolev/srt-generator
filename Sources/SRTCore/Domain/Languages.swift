import Foundation
import NaturalLanguage

public struct LanguageOption: Hashable, Sendable {
    public let name: String
    public let code: String

    public init(name: String, code: String) {
        self.name = name
        self.code = code
    }
}

public enum Languages {
    /// Builds a sorted, de-duplicated picker list from a `name → code` table
    /// (e.g. WhisperKit's `Constants.languages`, which has aliases such as "castilian" → "es").
    public static func options(from table: [String: String]) -> [LanguageOption] {
        var byCode: [String: String] = [:]
        for (name, code) in table.sorted(by: { $0.key < $1.key }) where byCode[code] == nil {
            byCode[code] = name.capitalized
        }
        return byCode.map { LanguageOption(name: $0.value, code: $0.key) }.sorted { $0.name < $1.name }
    }

    /// The options a given model accepts.
    public static func options(_ all: [LanguageOption], for model: ModelInfo) -> [LanguageOption] {
        guard let codes = model.languageCodes else { return all }
        return all.filter { codes.contains($0.code) }
    }

    /// Localized name for a language identifier such as "de" or "pt-BR".
    public static func displayName(_ identifier: String, locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// Best-guess language of a transcript, for engines that do not report one.
    public static func detect(in text: String, fallback: String = "en") -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? fallback
    }
}
