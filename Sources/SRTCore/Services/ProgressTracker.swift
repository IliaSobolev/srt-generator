import Foundation
import Synchronization

/// Converts "furthest transcribed timestamp" reports from concurrent workers into a 0...0.99 fraction.
public final class ProgressTracker: Sendable {
    private let maxEnd = Mutex<Double>(0)
    public let duration: Double
    private let report: @Sendable (Double) -> Void

    public init(duration: Double, report: @escaping @Sendable (Double) -> Void) {
        self.duration = duration
        self.report = report
    }

    public func update(_ ends: [Double]) {
        guard duration > 0, let end = ends.max() else { return }
        let value = maxEnd.withLock { current in
            current = max(current, end)
            return min(0.99, current / duration)
        }
        report(value)
    }
}
