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

    /// 通过 Workspace 重命名后，标签页标题更新为自定义名称。
    @Test func renameTabUpdatesTitle() {
        let ws = WorkspaceViewModel()
        let countBefore = ws.tabs.count
        ws.newTab()

        ws.renameTab(at: countBefore, to: "业务配置")

        #expect(ws.tabs[countBefore].documentTitle == "业务配置")
    }

    /// 关闭其他页后只保留目标标签页。
    @Test func closeOtherTabsKeepsOnlyTarget() {
        let ws = WorkspaceViewModel()
        let countBefore = ws.tabs.count
        ws.newTab()
        ws.newTab()
        ws.newTab()
        let targetIndex = countBefore + 1
        let target = ws.tabs[targetIndex]

        ws.closeOtherTabs(at: targetIndex)

        #expect(ws.tabs.count == 1)
        #expect(ws.tabs.first === target)
    }

    /// 关闭所有页后标签页为空。
    @Test func closeAllTabsClosesEverything() {
        let ws = WorkspaceViewModel()
        ws.newTab()
        ws.newTab()

        ws.closeAllTabs()

        #expect(ws.tabs.isEmpty)
        #expect(ws.activeTabIndex == -1)
    }

    /// 复制标签页生成内容相同的新标签页并激活。
    @Test func duplicateTabCreatesNewTabWithSameContent() {
        let ws = WorkspaceViewModel()
        let countBefore = ws.tabs.count
        ws.newTab()
        ws.tabs[countBefore].rawText = #"{"k":1}"#

        ws.duplicateTab(at: countBefore)

        let duplicated = ws.tabs[countBefore + 1]
        #expect(ws.tabs.count == countBefore + 2)
        #expect(duplicated.rawText == #"{"k":1}"#)
        #expect(duplicated.treeRoot != nil)
        #expect(duplicated.hasValidJSONContent)
        #expect(duplicated.fileURL == nil)
        #expect(duplicated.isModified)
        #expect(duplicated.untitledNumber > 0)
        #expect(ws.activeTabIndex == countBefore + 1)
    }

    /// 复制文件标签页时，新页是未命名副本而非绑定同一文件。
    @Test func duplicateFileTabCreatesUntitledCopy() throws {
        let ws = WorkspaceViewModel()
        let countBefore = ws.tabs.count
        ws.newTab()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t_dup.json")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"f":1}"#.write(to: url, atomically: true, encoding: .utf8)
        try ws.tabs[countBefore].load(from: url)

        ws.duplicateTab(at: countBefore)

        let duplicated = ws.tabs[countBefore + 1]
        #expect(duplicated.rawText == #"{"f":1}"#)
        #expect(duplicated.fileURL == nil)
        #expect(duplicated.documentTitle.hasPrefix("Untitled"))
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

    // MARK: - Open documents

    @Test func openDocumentsOpensMultipleFiles() throws {
        let ws = WorkspaceViewModel()
        ws.closeAllTabs()
        ws.newTab()

        let dir = FileManager.default.temporaryDirectory
        let urls = (0..<3).map { i in
            dir.appendingPathComponent("multi_open_\(i).json")
        }
        for (index, url) in urls.enumerated() {
            try #"{"i":\#(index)}"#.write(to: url, atomically: true, encoding: .utf8)
        }
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

        ws.openDocuments(urls)

        #expect(ws.tabs.count == 3)
        #expect(Set(ws.tabs.compactMap(\.fileURL)) == Set(urls))
    }

    @Test func openDocumentWithDirtyUntitledAlwaysCreatesNewTab() throws {
        let ws = WorkspaceViewModel()
        let countBefore = ws.tabs.count
        ws.newTab()
        let dirtyIndex = countBefore
        ws.tabs[dirtyIndex].rawText = #"{"dirty":true}"#

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t_dirty_new_tab.json")
        try #"{"file":1}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        ws.openDocument(from: url)

        #expect(ws.tabs.count == countBefore + 2)
        #expect(ws.tabs.last?.fileURL == url)
    }

    @Test func tabLimitBlocksNewTabAndFiresHook() {
        let ws = WorkspaceViewModel()
        var limitAlerts = 0
        ws.onTabLimitReached = { limitAlerts += 1 }

        while ws.tabs.count < WorkspaceViewModel.maxTabs {
            ws.newTab()
        }
        ws.newTab()

        #expect(ws.tabs.count == WorkspaceViewModel.maxTabs)
        #expect(limitAlerts == 1)
    }

    @Test func tabLimitStopsFurtherOpensInOneOperation() throws {
        let ws = WorkspaceViewModel()
        var limitAlerts = 0
        ws.onTabLimitReached = { limitAlerts += 1 }

        while ws.tabs.count < WorkspaceViewModel.maxTabs - 1 {
            ws.newTab()
        }

        let dir = FileManager.default.temporaryDirectory
        let urls = (0..<2).map { i in dir.appendingPathComponent("limit_batch_\(i).json") }
        for url in urls {
            try #"{"k":1}"#.write(to: url, atomically: true, encoding: .utf8)
        }
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

        ws.openDocuments(urls)

        #expect(ws.tabs.count == WorkspaceViewModel.maxTabs)
        #expect(limitAlerts == 1)
    }

    @Test func openFileOnDiffSideLoadsSideAndMainTab() throws {
        let ws = WorkspaceViewModel()
        ws.presentDiffFromMenu()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t_diff_drop.json")
        try #"{"diff":true}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        ws.openFileOnDiffSide(url, position: .left)

        #expect(ws.diffViewModel?.left.label == url.lastPathComponent)
        #expect(ws.diffViewModel?.left.inlineText.contains("diff") == true)
        #expect(ws.tabs.contains { $0.fileURL == url })
    }

    @Test func rejectDiffMultiFileDropFiresHook() {
        let ws = WorkspaceViewModel()
        var rejected = false
        ws.onDiffMultiFileDropRejected = { rejected = true }

        ws.rejectDiffMultiFileDrop()

        #expect(rejected)
    }

    @Test func diffMultiFileDropUsesLockedCompareTipString() {
        #expect(
            WorkspaceViewModel.diffMultiFileDropAlertMessage
                == "Drop one file at a time while Compare is open."
        )
    }

    @Test func openFileOnDiffSideDoesNotOpenTabWhenLoadFails() throws {
        let ws = WorkspaceViewModel()
        ws.presentDiffFromMenu()
        let leftBefore = ws.diffViewModel?.left.label
        let tabCountBefore = ws.tabs.count

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t_diff_reject.xml")
        try "<not json>".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        ws.openFileOnDiffSide(url, position: .left)

        #expect(ws.tabs.count == tabCountBefore)
        #expect(ws.diffViewModel?.left.label == leftBefore)
        #expect(ws.diffViewModel?.errorMessage != nil)
    }

    @Test func openFileOnDiffSideDoesNotClobberExistingModifiedTab() throws {
        let ws = WorkspaceViewModel()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t_diff_preserve.json")
        try "{'a':1}".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        ws.openDocument(from: url)
        guard let tab = ws.tabs.first(where: { $0.fileURL == url }) else {
            Issue.record("Expected tab for opened file")
            return
        }
        let formattedInTab = tab.rawText
        #expect(tab.isModified)

        ws.presentDiffFromMenu()
        ws.openFileOnDiffSide(url, position: .left)

        #expect(tab.rawText == formattedInTab)
        #expect(tab.isModified)
        #expect(ws.diffViewModel?.left.inlineText == "{'a':1}")
        #expect(ws.activeTabIndex == ws.tabs.firstIndex(where: { $0.fileURL == url }))
    }

    // MARK: - Tab reorder

    /// Reordering updates tab array order and persists active selection by tab id.
    @Test func moveTabReordersTabs() {
        let ws = WorkspaceViewModel()
        ws.closeAllTabs()
        ws.newTab()
        ws.newTab()
        ws.newTab()
        let ids = ws.tabs.map(\.id)
        #expect(ids.count == 3)

        ws.moveTab(from: 0, to: 3)

        #expect(ws.tabs.map(\.id) == [ids[1], ids[2], ids[0]])
    }

    /// When a non-dragged tab stays active, reorder must not change which document is active.
    @Test func moveTabKeepsActiveTabByIdWhenDraggingOtherTab() {
        let ws = WorkspaceViewModel()
        ws.closeAllTabs()
        ws.newTab()
        ws.newTab()
        ws.newTab()
        ws.activateTab(at: 0)
        let activeId = ws.tabs[0].id

        ws.moveTab(from: 2, to: 0)

        #expect(ws.activeDocument === ws.tabs.first { $0.id == activeId })
        #expect(ws.tabs[ws.activeTabIndex].id == activeId)
    }

    /// Moving the active tab must keep that tab active after drop.
    @Test func moveTabKeepsActiveWhenDraggingActiveTab() {
        let ws = WorkspaceViewModel()
        ws.closeAllTabs()
        ws.newTab()
        ws.newTab()
        ws.activateTab(at: 1)
        let activeId = ws.tabs[1].id

        ws.moveTab(from: 1, to: 0)

        #expect(ws.tabs[ws.activeTabIndex].id == activeId)
        #expect(ws.activeTabIndex == 0)
    }

    @Test func moveTabNoOpForInvalidOrSameDestination() {
        let ws = WorkspaceViewModel()
        ws.closeAllTabs()
        ws.newTab()
        ws.newTab()
        let before = ws.tabs.map(\.id)

        ws.moveTab(from: -1, to: 0)
        ws.moveTab(from: 0, to: 99)
        ws.moveTab(from: 0, to: 1)
        ws.moveTab(from: 0, to: 0)

        #expect(ws.tabs.map(\.id) == before)
    }

    @Test func openFileOnDiffSideAtTabLimitDoesNotUpdateDiffSide() throws {
        let ws = WorkspaceViewModel()
        var limitAlerts = 0
        ws.onTabLimitReached = { limitAlerts += 1 }

        while ws.tabs.count < WorkspaceViewModel.maxTabs {
            ws.newTab()
        }

        ws.presentDiffFromMenu()
        let leftLabelBefore = ws.diffViewModel?.left.label
        let leftTextBefore = ws.diffViewModel?.left.inlineText

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t_diff_limit_block.json")
        try #"{"blocked":true}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        ws.openFileOnDiffSide(url, position: .left)

        #expect(limitAlerts == 1)
        #expect(ws.tabs.count == WorkspaceViewModel.maxTabs)
        #expect(!ws.tabs.contains { $0.fileURL == url })
        #expect(ws.diffViewModel?.left.label == leftLabelBefore)
        #expect(ws.diffViewModel?.left.inlineText == leftTextBefore)
    }
}
