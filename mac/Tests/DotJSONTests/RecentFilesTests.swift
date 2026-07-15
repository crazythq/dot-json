import Testing
import Foundation
@testable import DotJSON

@MainActor
struct RecentFilesTests {

    @Test func initiallyEmpty() {
        let vm = EditorViewModel()
        #expect(vm.recentFiles.isEmpty)
    }

    @Test func addRecentOnSave() throws {
        let vm = EditorViewModel()
        vm.rawText = "{}"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_recent.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try vm.save(to: url)
        #expect(vm.recentFiles.count == 1)
        #expect(vm.recentFiles.first == url)
    }

    @Test func addRecentOnLoad() throws {
        let vm = EditorViewModel()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_recent_load.json")
        try #"{"x":1}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        try vm.load(from: url)
        #expect(vm.recentFiles.count == 1)
        #expect(vm.recentFiles.first == url)
    }

    @Test func deduplicatesRecentFiles() throws {
        let vm = EditorViewModel()
        vm.rawText = "{}"
        let url1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent_a.json")
        let url2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent_b.json")
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        try vm.save(to: url1)
        try vm.save(to: url2)
        try vm.save(to: url1) // save to url1 again → moves to top, no dup
        #expect(vm.recentFiles.count == 2)
        #expect(vm.recentFiles.first == url1)
    }

    @Test func maxRecentFiles() throws {
        let vm = EditorViewModel()
        vm.rawText = "{}"
        let urls = (0..<15).map {
            FileManager.default.temporaryDirectory.appendingPathComponent("recent_\($0).json")
        }
        defer { for u in urls { try? FileManager.default.removeItem(at: u) } }

        for u in urls { try vm.save(to: u) }
        #expect(vm.recentFiles.count == 10) // max 10
    }
}
