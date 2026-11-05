import Foundation
import Synchronization
import Testing
@testable import SRTCore

@Suite("SRT writer")
struct SRTWriterTests {
    @Test("Timestamps", arguments: [
        (0.0, "00:00:00,000"), (1.2344, "00:00:01,234"), (61.5, "00:01:01,500"), (3723.004, "01:02:03,004"),
        (-5, "00:00:00,000"),
    ])
    func timestamp(seconds: Double, expected: String) {
        #expect(SRTWriter.timestamp(seconds) == expected)
    }

    @Test("Renders numbered cues separated by blank lines")
    func render() {
        let srt = SRTWriter.render([
            SubtitleCue(start: 0, end: 1, text: "One"), SubtitleCue(start: 1.5, end: 2, text: "Two\nlines"),
        ])
        #expect(srt == "1\n00:00:00,000 --> 00:00:01,000\nOne\n\n2\n00:00:01,500 --> 00:00:02,000\nTwo\nlines\n")
        #expect(SRTWriter.render([]) == "")
    }

    @Test("Wrapping keeps short text, single long words, and balances two lines")
    func wrap() {
        #expect(SRTWriter.wrap("Short line") == "Short line")
        let long = String(repeating: "x", count: 60)
        #expect(SRTWriter.wrap(long) == long)
        #expect(SRTWriter.wrap("one two three four five six", maxLine: 10) == "one two three\nfour five six")
    }
}

@Suite("Cue builder")
struct CueBuilderTests {
    let builder = CueBuilder(maxLineLength: 20, maxDuration: 5)

    @Test("Short segments become one cue each; blank segments are skipped")
    func shortSegments() {
        let cues = builder.build([
            SpeechSegment(start: 0, end: 2, text: " Hello there. "),
            SpeechSegment(start: 2, end: 3, text: "<|0.00|>  "),
            SpeechSegment(start: 3, end: 4, text: "Bye"),
        ])
        #expect(cues == [SubtitleCue(start: 0, end: 2, text: "Hello there."), SubtitleCue(start: 3, end: 4, text: "Bye")])
        #expect(builder.maxChars == 40)
    }

    @Test("Long segments without enough words stay whole")
    func longWithoutWords() {
        let text = "This sentence is much longer than forty characters in total."
        let noWords = builder.build([SpeechSegment(start: 0, end: 3, text: text)])
        #expect(noWords.count == 1)
        let oneWord = builder.build([SpeechSegment(start: 0, end: 9, text: "Hi",
                                                    words: [TimedWord(text: " Hi", start: 0, end: 9)])])
        #expect(oneWord == [SubtitleCue(start: 0, end: 9, text: "Hi")])
    }

    @Test("Long segments split on length, duration, pauses and sentence ends")
    func splitting() {
        func w(_ t: String, _ s: Double, _ e: Double) -> TimedWord { TimedWord(text: t, start: s, end: e) }
        let words = [
            w(" Alpha", 0, 0.5), w(" beta", 0.5, 1), w(" gamma", 1, 1.5), w(" delta", 1.5, 2),
            w(" epsilon.", 2, 2.5), // sentence end, cue long enough → break
            w(" zeta", 2.6, 3), w(" eta", 4.5, 5), // pause > 1 s → break
            w(" theta", 5, 9), w(" iota", 9, 12), // exceeds 5 s → break
            w(" kappakappakappa", 12, 12.2), w(" lambdalambdalam", 12.2, 12.4), // 36 chars: still fits
            w(" mumumumumumu", 12.4, 12.6), // would exceed 40 chars → break
            w("   ", 12.6, 12.7), // blank word at the end does not create a cue on its own
        ]
        let text = words.map(\.text).joined()
        let cues = builder.build([SpeechSegment(start: 0, end: 12.7, text: text, words: words)])
        #expect(cues.map(\.text) == [
            "Alpha beta gamma\ndelta epsilon.", "zeta", "eta theta", "iota kappakappakappa\nlambdalambdalam",
            "mumumumumumu",
        ])
        #expect(cues.first?.start == 0)
        #expect(cues.first?.end == 2.5)
    }

    @Test("Text ending on a sentence boundary does not produce an empty trailing cue")
    func endsOnSentence() {
        let words = [TimedWord(text: " Fifteen chars", start: 0, end: 1), TimedWord(text: " end.", start: 1, end: 2)]
        #expect(builder.split(words) == [SubtitleCue(start: 0, end: 2, text: "Fifteen chars end.")])
    }

    @Test("A cue made only of whitespace words is dropped")
    func blankFlush() {
        let words = [TimedWord(text: " ", start: 0, end: 3), TimedWord(text: " ", start: 3, end: 7)]
        #expect(builder.split(words).isEmpty)
    }

    @Test("Timing is made monotonic and never zero-length")
    func timing() {
        let cues = builder.normalizeTiming([
            SubtitleCue(start: 1, end: 1, text: "Zero length"),
            SubtitleCue(start: 1.2, end: 3, text: "Overlaps the previous cue"),
        ])
        #expect(cues[0].start == 1)
        #expect(cues[0].end == 1.55) // max(0.5, 11 chars × 0.05)
        #expect(cues[1].start == 1.55)
        #expect(cues[1].text == "Overlaps the\nprevious cue")
    }

    @Test("Cleans Whisper special tokens and whitespace")
    func clean() {
        #expect(CueBuilder.clean("<|en|><|0.00|> Hello \n  world <|1.00|>") == "Hello world")
    }

    @Test("Custom words become a Whisper prompt")
    func customWords() {
        #expect(CueBuilder.customWordsPrompt([]) == nil)
        #expect(CueBuilder.customWordsPrompt([" ", ""]) == nil)
        #expect(CueBuilder.customWordsPrompt([" Kyiv ", "", "SRT"]) == " Kyiv, SRT")
    }
}

@Suite("Speech segment grouping")
struct SpeechSegmentTests {
    @Test("Groups words at pauses")
    func groups() {
        let words = [
            TimedWord(text: " a", start: 0, end: 0.5), TimedWord(text: " b", start: 0.6, end: 1),
            TimedWord(text: " c", start: 2, end: 2.5),
        ]
        let segments = SpeechSegment.group(words, fallbackText: "", duration: 3)
        #expect(segments == [
            SpeechSegment(start: 0, end: 1, text: " a b", words: Array(words[0...1])),
            SpeechSegment(start: 2, end: 2.5, text: " c", words: [words[2]]),
        ])
    }

    @Test("Falls back to the plain transcript when there are no word timings")
    func fallback() {
        #expect(SpeechSegment.group([], fallbackText: " Hi ", duration: 3) == [SpeechSegment(start: 0, end: 3, text: "Hi")])
        #expect(SpeechSegment.group([], fallbackText: "  ", duration: 3).isEmpty)
    }
}

@Suite("Progress tracker")
struct ProgressTrackerTests {
    @Test("Reports the furthest timestamp as a fraction capped at 0.99")
    func reports() async {
        let values = Mutex<[Double]>([])
        let tracker = ProgressTracker(duration: 10) { v in values.withLock { $0.append(v) } }
        tracker.update([2, 5])
        tracker.update([3]) // older chunk reported later: progress never goes backwards
        tracker.update([])
        tracker.update([20])
        #expect(values.withLock { $0 } == [0.5, 0.5, 0.99])
        #expect(tracker.duration == 10)
    }

    @Test("Ignores updates when the duration is unknown")
    func zeroDuration() {
        let called = Mutex(false)
        ProgressTracker(duration: 0) { _ in called.withLock { $0 = true } }.update([1])
        #expect(!called.withLock { $0 })
    }
}
