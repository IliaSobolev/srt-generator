import AVFoundation
import CoreVideo
import Foundation

enum FixtureError: Error { case setup }

enum MediaFixtures {
    /// A mono 16 kHz WAV containing a 440 Hz tone.
    static func wav(seconds: Double = 0.5, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("tone-\(UUID().uuidString).wav")
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else { throw FixtureError.setup }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 16_000)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frames, 1)),
              let channel = buffer.floatChannelData?[0] else { throw FixtureError.setup }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { channel[i] = sin(Float(i) * 2 * .pi * 440 / 16_000) * 0.5 }
        if frames > 0 { try file.write(from: buffer) }
        return url
    }

    /// A QuickTime movie with a single video frame and no audio track.
    static func videoOnlyMovie(in dir: URL) async throws -> URL {
        let url = dir.appendingPathComponent("silent-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        guard let pixelBuffer else { throw FixtureError.setup }
        adaptor.append(pixelBuffer, withPresentationTime: .zero)
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    /// An executable shell script standing in for ffmpeg. The output path is ffmpeg's last argument.
    static func fakeFFmpeg(_ body: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("ffmpeg-\(UUID().uuidString)")
        try "#!/bin/sh\nfor a in \"$@\"; do out=\"$a\"; done\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Writes two little-endian Float32 samples: 1.0 and 2.0.
    static let twoSamples = #"printf '\000\000\200\077\000\000\000\100' > "$out""#
}
