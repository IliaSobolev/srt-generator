import Foundation

/// A recognized word. `text` keeps its leading space when the language uses spaces,
/// so words can be concatenated back into the original text.
struct TimedWord: Sendable, Hashable {
    var text: String
    var start: Double
    var end: Double
}

/// A span of recognized speech (a Whisper segment, or a pause-delimited run for Parakeet).
struct SpeechSegment: Sendable {
    var start: Double
    var end: Double
    var text: String
    var words: [TimedWord]?
}

/// Turns recognized speech into readable subtitle cues (≤ 2 lines, ≤ `maxDuration` each).
struct CueBuilder {
    var maxLineLength = 42
    var maxDuration = 7.0
    var maxChars: Int { maxLineLength * 2 }

    func build(_ segments: [SpeechSegment]) -> [SubtitleCue] {
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
        // Enforce monotonic, non-overlapping, non-zero-length timing.
        var fixed: [SubtitleCue] = []
        for var cue in cues {
            if let prev = fixed.last, cue.start < prev.end { cue.start = prev.end }
            if cue.end <= cue.start + 0.2 { cue.end = cue.start + max(0.5, Double(cue.text.count) * 0.05) }
            cue.text = SRTWriter.wrap(cue.text, maxLine: maxLineLength)
            fixed.append(cue)
        }
        // Pull back any end time that now overlaps the following cue.
        for i in fixed.indices.dropLast() where fixed[i].end > fixed[i + 1].start {
            fixed[i].end = max(fixed[i].start + 0.1, fixed[i + 1].start)
        }
        return fixed
    }

    private func split(_ words: [TimedWord]) -> [SubtitleCue] {
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

    static func clean(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
