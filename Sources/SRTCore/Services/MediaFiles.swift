import Foundation
import UniformTypeIdentifiers

public enum MediaFiles {
    /// Extensions ffmpeg handles that macOS may not classify as audio/video.
    public static let extraExtensions: Set<String> = ["mkv", "webm", "opus", "ogg", "flv", "wma", "ts", "mts", "m2ts"]

    public static func isMedia(_ url: URL) -> Bool {
        let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        return type?.conforms(to: .audiovisualContent) == true
            || extraExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Expands folders (recursively, skipping hidden files) into the media files they contain.
    public static func expand(_ urls: [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            guard isDirectory(url) else { return [url] }
            let e = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.contentTypeKey], options: [.skipsHiddenFiles])
            let files = (e?.allObjects ?? []).compactMap { $0 as? URL }
            return files.filter { !isDirectory($0) && isMedia($0) }.sorted { $0.path < $1.path }
        }
    }
}
