import Foundation

public struct SubtitleCue: Sendable, Hashable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum SRTWriter {
    public static func render(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { i, cue in
            "\(i + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    public static func timestamp(_ seconds: Double) -> String {
        let ms = max(0, Int((seconds * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    /// Wraps a cue's text into at most two lines of roughly `maxLine` characters.
    public static func wrap(_ text: String, maxLine: Int = 42) -> String {
        let words = text.split(separator: " ")
        guard text.count > maxLine, words.count > 1 else { return text }
        // Pick the split point that balances the two lines best.
        let best = (1..<words.count).min { a, b in
            longerHalf(words, at: a) < longerHalf(words, at: b)
        }!
        return words[..<best].joined(separator: " ") + "\n" + words[best...].joined(separator: " ")
    }

    private static func longerHalf(_ words: [Substring], at i: Int) -> Int {
        max(words[..<i].joined(separator: " ").count, words[i...].joined(separator: " ").count)
    }
}
