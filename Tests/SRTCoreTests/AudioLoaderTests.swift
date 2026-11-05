import AVFoundation
import Foundation
@testable import SRTCore
import Testing

@Suite("Audio loader")
struct AudioLoaderTests {
    let dir: URL

    init() throws { dir = try Fixtures.tempDir() }

    @Test("Finds the first executable ffmpeg candidate")
    func locate() throws {
        let fake = try MediaFixtures.fakeFFmpeg("exit 0", in: dir)
        let notExecutable = dir.appendingPathComponent("plain")
        try Data().write(to: notExecutable)
        #expect(AudioLoader.locateFFmpeg(candidates: ["/missing/ffmpeg", notExecutable.path, fake.path]) == fake)
        #expect(AudioLoader.locateFFmpeg(candidates: []) == nil)
        #expect(AudioLoader(ffmpegURL: fake).supportsAllFormats)
        #expect(!AudioLoader(ffmpegURL: nil).supportsAllFormats)
        _ = AudioLoader() // default init searches the standard locations
    }

    @Test("Decodes with AVFoundation when ffmpeg is unavailable")
    func avFoundation() async throws {
        let samples = try await AudioLoader(ffmpegURL: nil).decode(MediaFixtures.wav(seconds: 0.5, in: dir))
        #expect(samples.count == 8000)
        #expect(samples.contains { $0 > 0.4 })
    }

    @Test("AVFoundation rejects files without audio")
    func avNoAudio() async throws {
        let loader = AudioLoader(ffmpegURL: nil)
        let movie = try await MediaFixtures.videoOnlyMovie(in: dir)
        await #expect(throws: AudioLoader.LoadError.noAudioTrack) { try await loader.decode(movie) }
        let empty = try MediaFixtures.wav(seconds: 0, in: dir)
        await #expect(throws: AudioLoader.LoadError.self) { try await loader.decode(empty) }
    }

    @Test("Reader failures become decode errors")
    func readerStatus() throws {
        #expect(throws: Never.self) { try AudioLoader.check(.completed, nil) }
        #expect(throws: AudioLoader.LoadError.decodeFailed("unknown error")) { try AudioLoader.check(.failed, nil) }
        #expect(throws: AudioLoader.LoadError.decodeFailed("boom: x")) {
            try AudioLoader.check(.failed, TestError.boom("x"))
        }
    }

    @Test("Decodes ffmpeg's raw Float32 output")
    func ffmpegSuccess() async throws {
        let ffmpeg = try MediaFixtures.fakeFFmpeg(MediaFixtures.twoSamples, in: dir)
        let samples = try await AudioLoader(ffmpegURL: ffmpeg).decode(URL(fileURLWithPath: "/any/input.mkv"))
        #expect(samples == [1, 2])
    }

    @Test("Maps ffmpeg errors", arguments: [
        ("Output file #0 does not contain any stream", AudioLoader.LoadError.noAudioTrack),
        ("Stream map '0:a' matches no streams.", .noAudioTrack),
        ("  Invalid data found when processing input\n", .decodeFailed("Invalid data found when processing input")),
    ])
    func ffmpegErrors(message: String, expected: AudioLoader.LoadError) {
        #expect(AudioLoader.ffmpegError(message) == expected)
    }

    @Test("ffmpeg failures fall back to AVFoundation")
    func fallback() async throws {
        let ffmpeg = try MediaFixtures.fakeFFmpeg("echo 'Invalid data' >&2; exit 1", in: dir)
        let samples = try await AudioLoader(ffmpegURL: ffmpeg).decode(MediaFixtures.wav(in: dir))
        #expect(samples.count == 8000)
    }

    @Test("When both decoders fail, ffmpeg's error is reported")
    func bothFail() async throws {
        let text = dir.appendingPathComponent("notes.txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        let failing = try MediaFixtures.fakeFFmpeg("echo 'Invalid data' >&2; exit 1", in: dir)
        await #expect(throws: AudioLoader.LoadError.decodeFailed("Invalid data")) {
            try await AudioLoader(ffmpegURL: failing).decode(text)
        }
        let empty = try MediaFixtures.fakeFFmpeg(#": > "$out""#, in: dir)
        await #expect(throws: AudioLoader.LoadError.noAudioTrack) {
            try await AudioLoader(ffmpegURL: empty).decode(text)
        }
        let missing = dir.appendingPathComponent("no-such-ffmpeg")
        await #expect(throws: (any Error).self) { try await AudioLoader(ffmpegURL: missing).decode(text) }
    }

    @Test("Cancelling stops ffmpeg")
    func cancel() async throws {
        let slow = try MediaFixtures.fakeFFmpeg("sleep 10", in: dir)
        let wav = try MediaFixtures.wav(in: dir)
        let started = ContinuousClock.now
        let task = Task { try await AudioLoader(ffmpegURL: slow).decode(wav) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test("Raw bytes become floats")
    func floats() {
        let data = [Float(0.5), -1].withUnsafeBufferPointer { Data(buffer: $0) }
        #expect(AudioLoader.floats(data) == [0.5, -1])
    }
}
