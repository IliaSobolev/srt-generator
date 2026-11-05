import Foundation

struct SubtitleCue: Sendable, Hashable {
    var start: Double
    var end: Double
    var text: String
}

enum SRTWriter {
    static func render(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { i, cue in
            "\(i + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    static func timestamp(_ seconds: Double) -> String {
        let ms = max(0, Int((seconds * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    /// Wraps a cue's text into at most two lines of roughly `maxLine` characters.
    static func wrap(_ text: String, maxLine: Int = 42) -> String {
        guard text.count > maxLine else { return text }
        let words = text.split(separator: " ")
        guard words.count > 1 else { return text }
        // Pick the split point that balances the two lines best.
        var best = 1, bestScore = Int.max
        for i in 1..<words.count {
            let a = words[..<i].joined(separator: " ").count
            let b = words[i...].joined(separator: " ").count
            let score = max(a, b)
            if score < bestScore { bestScore = score; best = i }
        }
        return words[..<best].joined(separator: " ") + "\n" + words[best...].joined(separator: " ")
    }
}
