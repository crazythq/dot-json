import AppKit
import Foundation
import Testing
@testable import DotJSON

struct FileDropPasteboardTests {

    @Test func fileURLsReadsNSURLObjectsFromPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DotJSONTests.FileDropNSURL"))
        pasteboard.clearContents()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drag-target.json")
        pasteboard.writeObjects([url as NSURL])

        let urls = FileDropPasteboard.fileURLs(from: pasteboard)

        #expect(urls == [url])
        #expect(FileDropPasteboard.containsFileURL(pasteboard))
    }

    @Test func fileURLsReadsFileURLStringPasteboardType() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DotJSONTests.FileDropString"))
        pasteboard.clearContents()
        let path = "/tmp/example.json"
        pasteboard.setString(path, forType: .fileURL)

        let urls = FileDropPasteboard.fileURLs(from: pasteboard)

        #expect(urls.count == 1)
        #expect(urls.first?.path == path)
    }
}
