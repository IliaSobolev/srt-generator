import Foundation

/// A recognized word. `text` keeps its leading space when the language uses spaces,
/// so words can be concatenated back into the original text.
public struct TimedWord: Sendable, Hashable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A span of recognized speech (a Whisper segment, or a pause-delimited run for Parakeet).
public struct SpeechSegment: Sendable, Hashable {
    public var start: Double
    public var end: Double
    public var text: String
    public var words: [TimedWord]?

    public init(start: Double, end: Double, text: String, words: [TimedWord]? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }

    /// Groups a continuous word stream into segments, splitting at pauses longer than `pause` seconds.
    /// Falls back to a single segment of `fallbackText` when the engine returned no word timings.
    public static func group(
        _ words: [TimedWord], pause: Double = 0.8, fallbackText: String, duration: Double
    ) -> [SpeechSegment] {
        guard !words.isEmpty else {
            let text = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [SpeechSegment(start: 0, end: duration, text: text)]
        }
        var result: [SpeechSegment] = []
        var run: [TimedWord] = [words[0]]
        for word in words.dropFirst() {
            if word.start - run[run.count - 1].end > pause {
                result.append(SpeechSegment(run))
                run = []
            }
            run.append(word)
        }
        result.append(SpeechSegment(run))
        return result
    }

    private init(_ run: [TimedWord]) {
        self.init(start: run[0].start, end: run[run.count - 1].end, text: run.map(\.text).joined(), words: run)
    }
}

/// Turns recognized speech into readable subtitle cues (≤ 2 lines, ≤ `maxDuration` each).
public struct CueBuilder: Sendable, Equatable {
    public var maxLineLength: Int
    public var maxDuration: Double
    public var maxChars: Int { maxLineLength * 2 }

    public init(maxLineLength: Int = 42, maxDuration: Double = 7.0) {
        self.maxLineLength = maxLineLength
        self.maxDuration = maxDuration
    }

    public func build(_ segments: [SpeechSegment]) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for seg in segments {
            let text = Self.clean(seg.text)
            guard !text.isEmpty else { continue }
            let tooLong = text.count > maxChars || seg.end - seg.start > maxDuration
            if tooLong, let words = seg.words, words.count > 1 {
                cues.append(contentsOf: split(words))
            } else {
                cues.append(SubtitleCue(start: seg.start, end: seg.end, text: text))
            }
        }
        return normalizeTiming(cues)
    }

    /// Enforces monotonic, non-overlapping, non-zero-length timing and wraps text.
    func normalizeTiming(_ cues: [SubtitleCue]) -> [SubtitleCue] {
        var fixed: [SubtitleCue] = []
        for var cue in cues {
            if let prev = fixed.last, cue.start < prev.end { cue.start = prev.end }
            if cue.end <= cue.start + 0.2 { cue.end = cue.start + max(0.5, Double(cue.text.count) * 0.05) }
            cue.text = SRTWriter.wrap(cue.text, maxLine: maxLineLength)
            fixed.append(cue)
        }
        return fixed
    }

    func split(_ words: [TimedWord]) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var current: [TimedWord] = []

        func joined() -> String { current.map(\.text).joined() }
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = Self.clean(joined())
            if !text.isEmpty { cues.append(SubtitleCue(start: first.start, end: last.end, text: text)) }
            current.removeAll()
        }

        for word in words {
            if let first = current.first, let last = current.last {
                let overflow = (joined() + word.text).trimmingCharacters(in: .whitespaces).count > maxChars
                    || word.end - first.start > maxDuration
                let pause = word.start - last.end > 1.0
                if overflow || pause { flush() }
            }
            current.append(word)
            // Prefer breaking at sentence ends once the cue has some substance.
            let w = word.text.trimmingCharacters(in: .whitespaces)
            if let ch = w.last, ".!?。！？".contains(ch), joined().count > maxChars / 3 { flush() }
        }
        flush()
        return cues
    }

    public static func clean(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whisper prompt text that biases decoding toward the user's custom words, or nil if there are none.
    public static func customWordsPrompt(_ words: [String]) -> String? {
        let cleaned = words.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : " " + cleaned.joined(separator: ", ")
    }
}
