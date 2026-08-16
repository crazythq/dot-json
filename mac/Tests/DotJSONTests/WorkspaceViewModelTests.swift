import Testing
import Foundation
@testable import DotJSON

@MainActor
struct WorkspaceViewModelTests {

    // MARK: - 未命名标签页命名

    /// 连续新建的未命名标签页获得单调递增的序号，且标题包含序号。
    @Test func newTabsGetSequentialUntitledNumbers() {
        let ws = WorkspaceViewModel()
        let countBefore = ws.tabs.count

        ws.newTab()
        ws.newTab()

        let first = ws.tabs[countBefore]
        let second = ws.tabs[countBefore + 1]
        #expect(second.untitledNumber == first.untitledNumber + 1)
        #expect(first.documentTitle == "Untitled \(first.untitledNumber)")
        #expect(second.documentTitle == "Untitled \(second.untitledNumber)")
    }

    // MARK: - 关闭二次确认

    /// 未命名标签页包含可解析 JSON 时视为有未保存内容，需要确认。
    @Test func confirmationRequiredForUntitledTabWithValidJSON() {
        let ws = WorkspaceViewModel()
        let vm = EditorViewModel()
        vm.rawText = #"{"k":1}"#
        #expect(ws.needsCloseConfirmation(vm))
    }

    /// 空标签页无需确认。
    @Test func noConfirmationForEmptyTab() {
        let ws = WorkspaceViewModel()
        let vm = EditorViewModel()
        #expect(!ws.needsCloseConfirmation(vm))
    }

    /// 内容不是可解析 JSON 时无需确认（不满足“符合格式”）。
    @Test func noConfirmationForInvalidJSON() {
        let ws = WorkspaceViewModel()
        let vm = EditorViewModel()
        vm.rawText = "{bad"
        #expect(!ws.needsCloseConfirmation(vm))
    }

    /// 已保存且未修改的文件标签页无需确认。
    @Test func noConfirmationForSavedUnmodifiedFile() throws {
        let ws = WorkspaceViewModel()
        let vm = EditorViewModel()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t_unmodified.json")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"k":1}"#.write(to: url, atomically: true, encoding: .utf8)
        try vm.load(from: url)
        #expect(!ws.needsCloseConfirmation(vm))
    }

    /// 文件标签页存在未保存修改时也需要确认。
    @Test func confirmationRequiredForModifiedFileTab() throws {
        let ws = WorkspaceViewModel()
        let vm = EditorViewModel()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t_modified.json")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"k":1}"#.write(to: url, atomically: true, encoding: .utf8)
        try vm.load(from: url)

        vm.rawText = #"{"k":2}"#

        #expect(ws.needsCloseConfirmation(vm))
    }
}
