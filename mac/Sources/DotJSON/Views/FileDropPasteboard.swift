import AppKit

/// Shared helpers for Finder file drags (must load file contents, never paste path strings into editors).
enum FileDropPasteboard {

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            return urls
        }
        if let raw = pasteboard.string(forType: .fileURL),
           let url = URL(string: raw),
           url.isFileURL {
            return [url]
        }
        return []
    }

    static func containsFileURL(_ pasteboard: NSPasteboard) -> Bool {
        !fileURLs(from: pasteboard).isEmpty
    }
}
