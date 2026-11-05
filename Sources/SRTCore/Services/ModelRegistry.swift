import Foundation

/// Routes each model to the provider for its engine family.
public struct ModelRegistry: Sendable {
    public let whisper: any ModelProvider
    public let parakeet: any ModelProvider

    public init(whisper: any ModelProvider, parakeet: any ModelProvider) {
        self.whisper = whisper
        self.parakeet = parakeet
    }

    public func provider(for model: ModelInfo) -> any ModelProvider {
        switch model.engine {
        case .whisper: whisper
        case .parakeet: parakeet
        }
    }
}
