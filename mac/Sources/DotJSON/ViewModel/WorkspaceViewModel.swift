import Foundation
import AppKit
import Observation
import DotJSONCore

/// 管理多标签页、激活文档、最近文件和会话持久化。
@MainActor
@Observable
final class WorkspaceViewModel {

    private enum Key {
        static let workspaceState = "dotjson.workspaceState"
    }

    private struct SessionSnapshot: Codable {
        let fileURLs: [String]
        let activeIndex: Int
        let recentFiles: [String]
    }

    nonisolated(unsafe) static weak var shared: WorkspaceViewModel?

    private(set) var tabs: [EditorViewModel] = []
    var activeTabIndex: Int = -1
    var recentFiles: [URL] = []
    var diffViewModel: DiffViewModel?
    var isDiffPresented = false
    private var isRestoringSession = true
    /// 下一个未命名标签页使用的序号（本次运行内单调递增）。
    private var nextUntitledNumber = 1

    var activeDocument: EditorViewModel? {
        guard tabs.indices.contains(activeTabIndex) else { return nil }
        return tabs[activeTabIndex]
    }

    var activeErrorLineNumber: Int { activeDocument?.errorLineNumber ?? 0 }
    var activeErrorMessage: String? { activeDocument?.errorMessage }

    init() {
        Self.shared = self
        restoreSession()
    }

    // MARK: - Tab Management

    func newTab() {
        let vm = EditorViewModel()
        vm.untitledNumber = nextUntitledNumber
        nextUntitledNumber += 1
        tabs.append(vm)
        activeTabIndex = tabs.count - 1
        persistSession()
    }

    /// 关闭指定标签页；若内容符合 JSON 格式且有未保存修改，先弹窗二次确认。
    func requestCloseTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs[index]
        guard needsCloseConfirmation(tab) else {
            closeTab(at: index)
            return
        }
        presentCloseConfirmation(for: tab, at: index)
    }

    /// 关闭当前激活的标签页（Cmd+W 入口）。
    func closeActiveTab() {
        guard tabs.indices.contains(activeTabIndex) else { return }
        // 确认弹窗打开时忽略重复的 ⌘W，避免叠出多个弹窗。
        if let window = NSApp.keyWindow, window.attachedSheet != nil { return }
        requestCloseTab(at: activeTabIndex)
    }

    /// 判断关闭标签页是否需要二次确认：仅当内容可解析为 JSON 且存在未保存修改时。
    func needsCloseConfirmation(_ tab: EditorViewModel) -> Bool {
        tab.isModified && tab.hasValidJSONContent
    }

    /// 以警告弹窗确认后关闭标签页；优先以 sheet 形式挂在当前窗口上。
    private func presentCloseConfirmation(for tab: EditorViewModel, at index: Int) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "关闭“\(tab.documentTitle)”？"
        alert.informativeText = "该标签页包含符合 JSON 格式且尚未保存的内容，关闭后将丢失。"
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "取消")

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                self.closeTab(at: index)
            }
        } else {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            closeTab(at: index)
        }
    }

    func openTab(from url: URL) throws {
        if let existingIndex = tabs.firstIndex(where: { $0.fileURL == url }) {
            activeTabIndex = existingIndex
            return
        }

        let vm = EditorViewModel()
        try vm.loadDocument(from: url)
        tabs.append(vm)
        activeTabIndex = tabs.count - 1
        addRecent(url)
        persistSession()
    }

    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].cancelBackgroundTasks()
        tabs.remove(at: index)
        if tabs.isEmpty {
            activeTabIndex = -1
        } else if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        } else if activeTabIndex > index {
            activeTabIndex -= 1
        }
        persistSession()
    }

    func activateTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeTabIndex = index
        persistSession()
    }

    /// 重命名指定标签页的显示标题。
    func renameTab(at index: Int, to title: String) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].rename(to: title)
    }

    /// 关闭除指定标签页外的所有标签页；含未保存内容时统一弹窗确认一次。
    func closeOtherTabs(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        closeTabs(at: Array(tabs.indices.filter { $0 != index }))
    }

    /// 关闭所有标签页；含未保存内容时统一弹窗确认一次。
    func closeAllTabs() {
        closeTabs(at: Array(tabs.indices))
    }

    /// 复制指定标签页为新标签页：内容与原页相同，作为未命名标签页插入并激活。
    func duplicateTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let source = tabs[index]
        let vm = EditorViewModel()
        vm.untitledNumber = nextUntitledNumber
        nextUntitledNumber += 1
        vm.indent = source.indent
        vm.rawText = source.rawText
        tabs.append(vm)
        activeTabIndex = tabs.count - 1
        persistSession()
    }

    /// 批量关闭标签页；任一目标含未保存的有效 JSON 内容时先统一确认。
    private func closeTabs(at targets: [Int]) {
        guard !targets.isEmpty else { return }
        let confirmedCount = targets.filter { needsCloseConfirmation(tabs[$0]) }.count
        guard confirmedCount > 0 else {
            closeTabsDirectly(at: targets)
            return
        }
        presentBatchCloseConfirmation(
            targetCount: targets.count,
            confirmedCount: confirmedCount
        ) {
            self.closeTabsDirectly(at: targets)
        }
    }

    /// 从高索引到低索引依次关闭，避免索引失效。
    private func closeTabsDirectly(at targets: [Int]) {
        for index in targets.sorted(by: >) {
            closeTab(at: index)
        }
    }

    /// 批量关闭的确认弹窗；优先以 sheet 形式挂在当前窗口上。
    private func presentBatchCloseConfirmation(
        targetCount: Int,
        confirmedCount: Int,
        completion: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = targetCount == 1
            ? "关闭标签页？"
            : "关闭 \(targetCount) 个标签页？"
        alert.informativeText = "其中 \(confirmedCount) 个标签页包含符合 JSON 格式且尚未保存的内容，关闭后将丢失。"
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "取消")

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                completion()
            }
        } else {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            completion()
        }
    }

    // MARK: - JSON Diff

    /// 菜单入口：以当前标签页为左侧，右侧待选。
    func presentDiffFromMenu() {
        let leftBinding = activeDocument.map { tab in
            DiffSideBinding(
                source: .tab(tab.id),
                label: tab.documentTitle,
                inlineText: tab.rawText,
                applyTarget: .tab(tab.id)
            )
        } ?? DiffSideBinding(
            source: .inline,
            label: "左侧",
            inlineText: "{}",
            applyTarget: .inlineOnly
        )
        let rightBinding = DiffSideBinding(
            source: .inline,
            label: "右侧",
            inlineText: "{}",
            applyTarget: .inlineOnly
        )
        let indent = activeDocument?.indent ?? .fourSpaces
        diffViewModel = DiffViewModel(left: leftBinding, right: rightBinding, indent: indent)
        isDiffPresented = true
    }

    /// 标签页右键：聚焦页 = 左，被右键页 = 右。
    func presentDiff(focusedTabIndex: Int, otherTabIndex: Int) {
        guard tabs.indices.contains(focusedTabIndex),
              tabs.indices.contains(otherTabIndex),
              focusedTabIndex != otherTabIndex else { return }
        let leftTab = tabs[focusedTabIndex]
        let rightTab = tabs[otherTabIndex]
        diffViewModel = DiffViewModel(
            left: DiffSideBinding(
                source: .tab(leftTab.id),
                label: leftTab.documentTitle,
                inlineText: leftTab.rawText,
                applyTarget: .tab(leftTab.id)
            ),
            right: DiffSideBinding(
                source: .tab(rightTab.id),
                label: rightTab.documentTitle,
                inlineText: rightTab.rawText,
                applyTarget: .tab(rightTab.id)
            ),
            indent: leftTab.indent
        )
        isDiffPresented = true
    }

    func dismissDiff() {
        isDiffPresented = false
        diffViewModel = nil
    }

    // MARK: - Document Operations

    func openDocument(from url: URL) {
        if let existingIndex = tabs.firstIndex(where: { $0.fileURL == url }) {
            activeTabIndex = existingIndex
            return
        }

        if tabs.count == 1, tabs[0].fileURL == nil, !tabs[0].isModified {
            do {
                let vm = tabs[0]
                try vm.loadDocument(from: url)
                addRecent(url)
                persistSession()
                return
            } catch {
                tabs[0].reportFileError(error)
                return
            }
        }

        do {
            try openTab(from: url)
        } catch {
            if let active = activeDocument {
                active.reportFileError(error)
            }
        }
    }

    func saveActiveDocument() {
        guard let doc = activeDocument else { return }
        if let url = doc.fileURL {
            do {
                try doc.save(to: url)
                persistSession()
            } catch {
                doc.reportFileError(error)
            }
        }
    }

    func saveActiveDocumentAs() {
        guard let doc = activeDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let title = doc.documentTitle
        panel.nameFieldStringValue = title.lowercased().hasSuffix(".json")
            ? title
            : "\(title).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try doc.save(to: url)
                self.addRecent(url)
                self.persistSession()
            } catch {
                doc.reportFileError(error)
            }
        }
    }

    // MARK: - Recent Files

    func addRecent(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > 10 { recentFiles = Array(recentFiles.prefix(10)) }
        persistSession()
    }

    func clearRecentFiles() {
        recentFiles = []
        persistSession()
    }

    // MARK: - Persistence

    /// 持久化当前会话到 UserDefaults。
    func persistSession() {
        guard !isRestoringSession else { return }
        let snapshot = SessionSnapshot(
            fileURLs: tabs.map { $0.fileURL?.path ?? "" },
            activeIndex: activeTabIndex,
            recentFiles: recentFiles.map { $0.path }
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Key.workspaceState)
        }
    }

    /// 从 UserDefaults 恢复上次会话。
    private func restoreSession() {
        defer { isRestoringSession = false }

        guard let data = UserDefaults.standard.data(forKey: Key.workspaceState),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data) else {
            newTab()
            return
        }

        recentFiles = snapshot.recentFiles.compactMap { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        let urls = snapshot.fileURLs.map { URL(fileURLWithPath: $0) }
            .filter { !$0.path.isEmpty && FileManager.default.fileExists(atPath: $0.path) }

        if urls.isEmpty {
            newTab()
            return
        }

        for url in urls {
            let vm = EditorViewModel()
            do {
                try vm.loadDocument(from: url)
                tabs.append(vm)
            } catch {
                // 文件已被删除或不可读，跳过。
            }
        }

        if tabs.isEmpty {
            newTab()
        } else {
            activeTabIndex = min(max(snapshot.activeIndex, 0), tabs.count - 1)
        }
    }
}
