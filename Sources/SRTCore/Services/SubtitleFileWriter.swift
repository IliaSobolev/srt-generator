import Foundation

/// Writes `.srt` files, never overwriting an existing file (adds " (1)", " (2)"… instead).
public struct SubtitleFileWriter: SubtitleWriting {
    public init() {}

    public func write(_ cues: [SubtitleCue], for source: URL, suffix: String?, folder: URL?) throws -> URL {
        let folder = folder ?? source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent + (suffix.map { ".\($0)" } ?? "")
        var url = folder.appendingPathComponent(stem).appendingPathExtension("srt")
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stem) (\(n))").appendingPathExtension("srt")
            n += 1
        }
        try SRTWriter.render(cues).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
