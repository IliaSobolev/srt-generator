import Foundation
import Observation
import SRTCore
import SwiftUI
import Translation

/// Bridges Apple's on-device Translation framework (which hands out sessions via a SwiftUI
/// modifier) to SRTCore's `Translating` protocol. All translation runs locally on the Mac.
@MainActor @Observable
final class TranslationBridge: Translating {
    var configuration: TranslationSession.Configuration?
    private var pending: (texts: [String], continuation: CheckedContinuation<[String], Error>)?

    func translate(_ texts: [String], from source: String, to target: String) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        let source = Locale.Language(identifier: source)
        let target = Locale.Language(identifier: target)
        return try await withCheckedThrowingContinuation { continuation in
            pending = (texts, continuation)
            if configuration?.source == source, configuration?.target == target {
                configuration?.invalidate()
            } else {
                configuration = .init(source: source, target: target)
            }
        }
    }

    func supportedTargets() async -> [String] {
        let langs = await LanguageAvailability().supportedLanguages
        return Array(Set(langs.map(\.minimalIdentifier)))
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
}

/// Invisible view that receives Translation sessions for the bridge.
struct TranslationHost: View {
    @Bindable var bridge: TranslationBridge

    var body: some View {
        Color.clear.translationTask(bridge.configuration) { session in
            await bridge.run(session)
        }
    }
}
