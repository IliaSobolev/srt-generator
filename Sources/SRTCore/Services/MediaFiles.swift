import Foundation
import UniformTypeIdentifiers

public enum MediaFiles {
    /// Extensions ffmpeg handles that macOS may not classify as audio/video.
    public static let extraExtensions: Set<String> = ["mkv", "webm", "opus", "ogg", "flv", "wma", "ts", "mts", "m2ts"]

    public static func isMedia(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return UTType(filenameExtension: ext)?.conforms(to: .audiovisualContent) == true
            || extraExtensions.contains(ext)
    }

    public static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Expands folders (recursively, skipping hidden files) into the media files they contain.
    /// Unreadable folders contribute nothing.
    public static func expand(_ urls: [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            guard isDirectory(url) else { return [url] }
            let paths = (try? FileManager.default.subpathsOfDirectory(atPath: url.path)) ?? []
            return paths
                .filter { !$0.split(separator: "/").contains { $0.hasPrefix(".") } }
                .map { url.appendingPathComponent($0) }
                .filter { !isDirectory($0) && isMedia($0) }
                .sorted { $0.path < $1.path }
        }
    }
}
