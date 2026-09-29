import Foundation
import Testing
@testable import DotJSON

struct DiffSideBindingTests {

    @Test func fileSideTracksDirtyAfterApply() throws {
        let directory = FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("diff-side-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let original = #"{"a":1}"#
        try original.write(to: url, atomically: true, encoding: .utf8)

        var side = DiffSideBinding.fromFile(url: url, text: original)
        #expect(!side.isFileDirty)

        side.inlineText = #"{"a":2}"#
        #expect(side.isFileDirty)

        let didWrite = try side.persistFileToDiskIfDirty()
        #expect(didWrite)
        #expect(!side.isFileDirty)

        let onDisk = try String(contentsOf: url, encoding: .utf8)
        #expect(onDisk == #"{"a":2}"#)

        let noop = try side.persistFileToDiskIfDirty()
        #expect(!noop)
    }

    @Test func tabSideTracksDirtyAfterEdit() {
        let tabID = UUID()
        var side = DiffSideBinding(
            source: .tab(tabID),
            label: "Tab",
            inlineText: "{}",
            applyTarget: .tab(tabID)
        )
        #expect(!side.isTabDirty)
        #expect(!side.showsUnsavedIndicator)

        side.inlineText = "{\"x\":1}"
        #expect(side.isTabDirty)
        #expect(side.showsUnsavedIndicator)
    }

    @Test func inlineSideNeverReportsFileDirty() {
        var side = DiffSideBinding(
            source: .inline,
            label: "x",
            inlineText: "{}",
            applyTarget: .inlineOnly
        )
        side.inlineText = "{\"changed\":true}"
        #expect(!side.isFileDirty)
    }
}
