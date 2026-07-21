import Testing
import Foundation
@testable import DotJSON

@MainActor
struct RecentFilesTests {

    @Test func initiallyEmpty() {
        let ws = WorkspaceViewModel()
        #expect(ws.recentFiles.isEmpty)
    }

    @Test func addRecentOnSave() throws {
        let ws = WorkspaceViewModel()
        let vm = EditorViewModel()
        vm.rawText = "{}"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_recent.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try vm.save(to: url)
        ws.addRecent(url)
        #expect(ws.recentFiles.count == 1)
        #expect(ws.recentFiles.first == url)
    }

    @Test func deduplicatesRecentFiles() throws {
        let ws = WorkspaceViewModel()
        let url1 = URL(fileURLWithPath: "/tmp/recent_a.json")
        let url2 = URL(fileURLWithPath: "/tmp/recent_b.json")

        ws.addRecent(url1)
        ws.addRecent(url2)
        ws.addRecent(url1)

        #expect(ws.recentFiles.count == 2)
        #expect(ws.recentFiles.first == url1)
    }

    @Test func maxRecentFiles() {
        let ws = WorkspaceViewModel()
        for i in 0..<15 {
            ws.addRecent(URL(fileURLWithPath: "/tmp/recent_\(i).json"))
        }
        #expect(ws.recentFiles.count == 10)
    }
}
