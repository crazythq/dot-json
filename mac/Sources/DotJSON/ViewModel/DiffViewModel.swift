import AppKit
import Foundation
import Observation
import DotJSONCore

enum DiffSidePosition: Sendable {
    case left
    case right
}

/// JSON 对比会话：结构化 Diff、行级 Diff、路径合并与撤销。
@MainActor
@Observable
final class DiffViewModel {
    var left: DiffSideBinding
    var right: DiffSideBinding
    var indent: JSONFormatter.Indent = .fourSpaces

    private(set) var comparison: JSONDiff.Comparison?
    /// 合并/保存等操作错误（不隐藏编辑器）。
    private(set) var errorMessage: String?
    private(set) var leftParseError: String?
    private(set) var rightParseError: String?
    private(set) var canUndo = false

    private var leftRoot: JSONNode?
    private var rightRoot: JSONNode?
    private var undoLeftRoot: JSONNode?
    private var undoRightRoot: JSONNode?
    private var refreshDebounceTask: Task<Void, Never>?

    private static let refreshDebounceNanoseconds: UInt64 = 250_000_000

    init(left: DiffSideBinding, right: DiffSideBinding, indent: JSONFormatter.Indent = .fourSpaces) {
        self.left = left
        self.right = right
        self.indent = indent
        refresh()
    }

    var hasDirtyFileTargets: Bool {
        left.isFileDirty || right.isFileDirty
    }

    /// 丢弃未保存的文件侧改动：内存与已打开的同路径标签页恢复为 `savedSnapshot`（磁盘内容）。
    func revertDirtyFileTargetsToSavedSnapshot(workspace: WorkspaceViewModel) {
        revertSideIfDirty(&left, workspace: workspace)
        revertSideIfDirty(&right, workspace: workspace)
    }

    /// 保存 Diff 中所有脏的文件侧（Cmd+S 入口之一）。
    func saveDirtyFileTargets(workspace: WorkspaceViewModel) throws {
        if left.isFileDirty {
            try saveFileSide(.left, workspace: workspace)
        }
        if right.isFileDirty {
            try saveFileSide(.right, workspace: workspace)
        }
    }

    func reportError(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func clearOperationError() {
        errorMessage = nil
    }

    func reloadFromSources(workspace: WorkspaceViewModel) {
        cancelPendingRefresh()
        left.inlineText = resolveText(for: left, workspace: workspace)
        right.inlineText = resolveText(for: right, workspace: workspace)
        refresh(syncWorkspaceTargets: workspace)
    }

    /// 用户编辑 Diff 侧文本；立即更新绑定并防抖重算 Diff。
    func setInlineText(_ text: String, on position: DiffSidePosition, workspace: WorkspaceViewModel) {
        switch position {
        case .left:
            left.inlineText = text
        case .right:
            right.inlineText = text
        }
        scheduleDebouncedRefresh(workspace: workspace)
    }

    func refresh() {
        refresh(syncWorkspaceTargets: nil)
    }

    private func refresh(syncWorkspaceTargets workspace: WorkspaceViewModel?) {
        if let workspace {
            syncOpenTargetsFromInlineText(workspace: workspace)
        }

        leftParseError = nil
        rightParseError = nil
        comparison = nil
        leftRoot = nil
        rightRoot = nil

        let parsedLeft = parseSideText(left.inlineText)
        let parsedRight = parseSideText(right.inlineText)

        if let error = parsedLeft.error {
            leftParseError = "Invalid JSON: \(error.localizedDescription)"
        }
        if let error = parsedRight.error {
            rightParseError = "Invalid JSON: \(error.localizedDescription)"
        }

        guard let leftNode = parsedLeft.node, let rightNode = parsedRight.node else { return }

        leftRoot = leftNode
        rightRoot = rightNode
        comparison = JSONDiff.compare(
            left: leftNode,
            right: rightNode,
            leftText: left.inlineText,
            rightText: right.inlineText,
            indent: indent
        )
    }

    private func scheduleDebouncedRefresh(workspace: WorkspaceViewModel) {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: Self.refreshDebounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.refresh(syncWorkspaceTargets: workspace)
        }
    }

    private func cancelPendingRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
    }

    func apply(row: JSONDiff.Row, direction: JSONDiff.ApplyDirection, workspace: WorkspaceViewModel) {
        guard let leftNode = leftRoot, let rightNode = rightRoot else { return }
        captureUndoIfNeeded()
        do {
            let result = try JSONDiff.apply(row: row, direction: direction, left: leftNode, right: rightNode)
            commitRoots(left: result.left, right: result.right, workspace: workspace, writeDirection: direction)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyAll(direction: JSONDiff.ApplyDirection, workspace: WorkspaceViewModel) {
        guard let rows = comparison?.rows, !rows.isEmpty,
              let leftNode = leftRoot, let rightNode = rightRoot else { return }
        captureUndoIfNeeded()
        do {
            let result = try JSONDiff.applyAll(
                rows: rows,
                direction: direction,
                left: leftNode,
                right: rightNode
            )
            commitRoots(left: result.left, right: result.right, workspace: workspace, writeDirection: direction)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undo(workspace: WorkspaceViewModel) {
        guard let undoLeftRoot, let undoRightRoot else { return }
        commitRoots(
            left: undoLeftRoot,
            right: undoRightRoot,
            workspace: workspace,
            writeDirection: nil
        )
        self.undoLeftRoot = nil
        self.undoRightRoot = nil
        canUndo = false
    }

    func pickFile(for position: DiffSidePosition, workspace: WorkspaceViewModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let binding = DiffSideBinding.fromFile(url: url, text: text)
            switch position {
            case .left: self.left = binding
            case .right: self.right = binding
            }
            self.cancelPendingRefresh()
            self.refresh()
        }
    }

    func useClipboard(for position: DiffSidePosition, workspace: WorkspaceViewModel) {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        switch position {
        case .left:
            left = DiffSideBinding(
                source: .clipboard,
                label: "Clipboard",
                inlineText: text,
                applyTarget: .clipboard
            )
        case .right:
            right = DiffSideBinding(
                source: .clipboard,
                label: "Clipboard",
                inlineText: text,
                applyTarget: .clipboard
            )
        }
        cancelPendingRefresh()
        refresh()
    }

    func useTab(_ tab: EditorViewModel, for position: DiffSidePosition) {
        let binding = DiffSideBinding(
            source: .tab(tab.id),
            label: tab.documentTitle,
            inlineText: tab.rawText,
            applyTarget: .tab(tab.id)
        )
        switch position {
        case .left: left = binding
        case .right: right = binding
        }
        cancelPendingRefresh()
        refresh(syncWorkspaceTargets: nil)
    }

    // MARK: - Private

    private struct ParsedSide {
        let node: JSONNode?
        let error: Error?
    }

    private func parseSideText(_ text: String) -> ParsedSide {
        do {
            return ParsedSide(node: try JSONParser.parse(text), error: nil)
        } catch {
            return ParsedSide(node: nil, error: error)
        }
    }

    /// 将 Diff 内联文本同步到已打开的标签页（文件/标签目标），不写入磁盘或剪贴板。
    private func syncOpenTargetsFromInlineText(workspace: WorkspaceViewModel) {
        syncBindingTargetToWorkspace(left, workspace: workspace)
        syncBindingTargetToWorkspace(right, workspace: workspace)
    }

    private func syncBindingTargetToWorkspace(_ side: DiffSideBinding, workspace: WorkspaceViewModel) {
        switch side.applyTarget {
        case .tab(let id):
            workspace.tabs.first(where: { $0.id == id })?.applyExternalContent(side.inlineText)
        case .file(let url):
            workspace.tabs.first(where: { $0.fileURL == url })?.applyExternalContent(side.inlineText)
        case .clipboard, .inlineOnly:
            break
        }
    }

    private func revertSideIfDirty(_ side: inout DiffSideBinding, workspace: WorkspaceViewModel) {
        guard side.isFileDirty, case .file(let url) = side.applyTarget else { return }
        side.inlineText = side.savedSnapshot
        if let tab = workspace.tabs.first(where: { $0.fileURL == url }) {
            tab.applyExternalContent(side.savedSnapshot)
            tab.acknowledgePersistedToDisk()
        }
    }

    private func saveFileSide(_ position: DiffSidePosition, workspace: WorkspaceViewModel) throws {
        switch position {
        case .left:
            var binding = left
            guard try binding.persistFileToDiskIfDirty() else { return }
            left = binding
            if let url = left.fileApplyURL {
                syncOpenTab(for: url, workspace: workspace)
            }
        case .right:
            var binding = right
            guard try binding.persistFileToDiskIfDirty() else { return }
            right = binding
            if let url = right.fileApplyURL {
                syncOpenTab(for: url, workspace: workspace)
            }
        }
    }

    private func syncOpenTab(for url: URL, workspace: WorkspaceViewModel) {
        guard let tab = workspace.tabs.first(where: { $0.fileURL == url }) else { return }
        tab.acknowledgePersistedToDisk()
    }

    private func captureUndoIfNeeded() {
        guard !canUndo, let leftRoot, let rightRoot else { return }
        undoLeftRoot = leftRoot
        undoRightRoot = rightRoot
        canUndo = true
    }

    private func commitRoots(
        left leftNode: JSONNode,
        right rightNode: JSONNode,
        workspace: WorkspaceViewModel,
        writeDirection: JSONDiff.ApplyDirection?
    ) {
        leftRoot = leftNode
        rightRoot = rightNode
        switch writeDirection {
        case .toLeft:
            writeNode(leftNode, to: .left, workspace: workspace)
        case .toRight:
            writeNode(rightNode, to: .right, workspace: workspace)
        case nil:
            writeNode(leftNode, to: .left, workspace: workspace)
            writeNode(rightNode, to: .right, workspace: workspace)
        }
        left.inlineText = (try? JSONFormatter.format(leftNode, indent: indent)) ?? JSONParser.serialize(leftNode)
        right.inlineText = (try? JSONFormatter.format(rightNode, indent: indent)) ?? JSONParser.serialize(rightNode)
        comparison = JSONDiff.compare(
            left: leftNode,
            right: rightNode,
            leftText: left.inlineText,
            rightText: right.inlineText,
            indent: indent
        )
    }

    private func writeNode(_ node: JSONNode, to position: DiffSidePosition, workspace: WorkspaceViewModel) {
        let text = (try? JSONFormatter.format(node, indent: indent)) ?? JSONParser.serialize(node)
        switch position {
        case .left:
            left.inlineText = text
            applyText(text, target: left.applyTarget, workspace: workspace)
        case .right:
            right.inlineText = text
            applyText(text, target: right.applyTarget, workspace: workspace)
        }
    }

    private func applyText(_ text: String, target: DiffSideBinding.ApplyTarget, workspace: WorkspaceViewModel) {
        switch target {
        case .tab(let id):
            workspace.tabs.first(where: { $0.id == id })?.applyExternalContent(text)
        case .file(let url):
            workspace.tabs.first(where: { $0.fileURL == url })?.applyExternalContent(text)
        case .clipboard:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .inlineOnly:
            break
        }
    }

    private func resolveText(for side: DiffSideBinding, workspace: WorkspaceViewModel) -> String {
        switch side.source {
        case .tab(let id):
            return workspace.tabs.first(where: { $0.id == id })?.rawText ?? side.inlineText
        case .file:
            return side.inlineText
        case .clipboard:
            return NSPasteboard.general.string(forType: .string) ?? side.inlineText
        case .inline:
            return side.inlineText
        }
    }
}
