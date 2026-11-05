import Foundation
import Observation
import Translation

/// Bridges Apple's on-device Translation framework (which hands out sessions via a SwiftUI
/// modifier) to plain async calls. All translation runs locally on the Mac.
@MainActor @Observable
final class TranslationBridge {
    var configuration: TranslationSession.Configuration?
    private var pending: (texts: [String], continuation: CheckedContinuation<[String], Error>)?

    func translate(_ texts: [String], from source: Locale.Language?, to target: Locale.Language) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            pending = (texts, continuation)
            if configuration?.source == source, configuration?.target == target {
                configuration?.invalidate()
            } else {
                configuration = .init(source: source, target: target)
            }
        }
    }

    func run(_ session: TranslationSession) async {
        guard let job = pending else { return }
        pending = nil
        do {
            try await session.prepareTranslation()
            let requests = job.texts.enumerated().map {
                TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
            }
            var out = job.texts
            for response in try await session.translations(from: requests) {
                if let id = response.clientIdentifier, let i = Int(id) { out[i] = response.targetText }
            }
            job.continuation.resume(returning: out)
        } catch {
            job.continuation.resume(throwing: error)
        }
    }

    static func supportedTargets() async -> [Locale.Language] {
        let langs = await LanguageAvailability().supportedLanguages
        var seen = Set<String>()
        return langs
            .filter { seen.insert($0.minimalIdentifier).inserted }
            .sorted { displayName($0) < displayName($1) }
    }

    static func displayName(_ lang: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: lang.maximalIdentifier)
            ?? Locale.current.localizedString(forIdentifier: lang.minimalIdentifier)
            ?? lang.minimalIdentifier
    }
}
