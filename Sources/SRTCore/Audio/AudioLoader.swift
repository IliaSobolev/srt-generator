import AVFoundation
import Foundation

/// Decodes any audio/video file into 16 kHz mono Float32 PCM, as the speech models expect.
/// Uses ffmpeg when available (covers practically every container/codec: mkv, webm, avi, flv, ogg, opus,
/// wma, …) and falls back to AVFoundation (mp4, mov, m4a, mp3, wav, aiff, caf, …).
public struct AudioLoader: AudioDecoding {
    public static let sampleRate = 16_000
    public static let ffmpegCandidates = [
        "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg", "/opt/local/bin/ffmpeg",
    ]

    public enum LoadError: LocalizedError, Equatable {
        case noAudioTrack
        case decodeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noAudioTrack: "The file has no audio track."
            case .decodeFailed(let msg): "Could not decode audio: \(msg)"
            }
        }
    }

    public let ffmpegURL: URL?

    public init(ffmpegURL: URL? = AudioLoader.locateFFmpeg()) {
        self.ffmpegURL = ffmpegURL
    }

    public static func locateFFmpeg(candidates: [String] = ffmpegCandidates) -> URL? {
        candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public var supportsAllFormats: Bool { ffmpegURL != nil }

    public func decode(_ url: URL) async throws -> [Float] {
        guard let ffmpeg = ffmpegURL else { return try await Self.decodeWithAVFoundation(url) }
        do {
            return try await Self.decodeWithFFmpeg(url, ffmpeg: ffmpeg)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Fall back to AVFoundation for anything ffmpeg chokes on; report ffmpeg's error otherwise.
            if let samples = try? await Self.decodeWithAVFoundation(url) { return samples }
            throw error
        }
    }

    // MARK: ffmpeg

    static func decodeWithFFmpeg(_ url: URL, ffmpeg: URL) async throws -> [Float] {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("f32")
        defer { try? FileManager.default.removeItem(at: out) }

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                             "-i", url.path, "-vn", "-ac", "1", "-ar", "\(sampleRate)",
                             "-f", "f32le", "-acodec", "pcm_f32le", out.path]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in cont.resume() }
                do { try process.run() } catch { cont.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()

        guard process.terminationStatus == 0 else {
            // Lossy decoding on purpose: show whatever ffmpeg printed, even if it isn't valid UTF-8.
            // swiftlint:disable:next optional_data_string_conversion
            throw ffmpegError(String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        let data = try Data(contentsOf: out)
        guard !data.isEmpty else { throw LoadError.noAudioTrack }
        return floats(data)
    }

    static func ffmpegError(_ message: String) -> LoadError {
        let noAudio = ["does not contain any stream", "matches no streams"]
        if noAudio.contains(where: message.contains) { return .noAudioTrack }
        return .decodeFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: AVFoundation

    static func decodeWithAVFoundation(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw LoadError.noAudioTrack
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        reader.startReading()
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            if let block = buffer.dataBuffer { try samples += floats(block.dataBytes()) }
        }
        try check(reader.status, reader.error)
        return samples
    }

    static func check(_ status: AVAssetReader.Status, _ error: Error?) throws {
        if status == .failed { throw LoadError.decodeFailed(error?.localizedDescription ?? "unknown error") }
    }

    static func floats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
