import AVFoundation
import Foundation

/// Decodes any audio/video file into 16 kHz mono Float32 PCM, as Whisper expects.
/// Uses ffmpeg when available (covers practically every container/codec: mkv, webm, avi,
/// flv, ogg, opus, wma, ...), and falls back to AVFoundation (mp4, mov, m4a, mp3, wav, aiff, caf, ...).
enum AudioLoader {
    static let sampleRate = 16_000

    enum LoadError: LocalizedError {
        case noAudioTrack
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: "The file has no audio track."
            case .decodeFailed(let msg): "Could not decode audio: \(msg)"
            }
        }
    }

    static var ffmpegURL: URL? {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg", "/opt/local/bin/ffmpeg"]
        if let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) { return bundled }
        return candidates.map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func load(_ url: URL) async throws -> [Float] {
        if let ffmpeg = ffmpegURL {
            do { return try await loadWithFFmpeg(url, ffmpeg: ffmpeg) } catch {
                // Fall through to AVFoundation for anything ffmpeg chokes on.
                if let samples = try? await loadWithAVFoundation(url) { return samples }
                throw error
            }
        }
        return try await loadWithAVFoundation(url)
    }

    // MARK: ffmpeg

    private static func loadWithFFmpeg(_ url: URL, ffmpeg: URL) async throws -> [Float] {
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
        } onCancel: { process.terminate() }

        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if msg.contains("does not contain any stream") || msg.contains("Output file does not contain") {
                throw LoadError.noAudioTrack
            }
            throw LoadError.decodeFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let data = try Data(contentsOf: out)
        guard !data.isEmpty else { throw LoadError.noAudioTrack }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    // MARK: AVFoundation

    private static func loadWithAVFoundation(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw LoadError.noAudioTrack
        }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else {
            throw LoadError.decodeFailed(reader.error?.localizedDescription ?? "unknown")
        }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            chunk.withUnsafeMutableBytes { ptr in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
            }
            samples.append(contentsOf: chunk)
        }
        if reader.status == .failed {
            throw LoadError.decodeFailed(reader.error?.localizedDescription ?? "unknown")
        }
        guard !samples.isEmpty else { throw LoadError.noAudioTrack }
        return samples
    }
}
