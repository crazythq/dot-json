import SwiftUI
import AppKit
import DotJSONCore

/// 支持精确右键定位和焦点感知 Cmd+F 的树视图。
final class ContextMenuOutlineView: NSOutlineView {
    /// 最近一次右键弹出时对应的行号；存在有效行时为 >= 0。
    var contextMenuRow: Int = -1

    /// 树拥有焦点并收到 Cmd+F 时调用。
    var onRequestFind: (() -> Void)?

    /// 树拥有焦点并收到 Cmd+C 时调用。
    var onCopyValue: (() -> Void)?

    /// 允许大纲成为第一响应者，使搜索快捷键能按左右面板焦点正确分流。
    override var acceptsFirstResponder: Bool {
        true
    }

    /// 鼠标选择树行前先明确取得键盘焦点。
    ///
    /// 原生查找栏关闭后 AppKit 会把第一响应者还给左侧文本视图；仅改变大纲选择项
    /// 不保证转移焦点，因此必须在真实鼠标事件入口完成切换。
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    /// 根据右键事件坐标定位行，避免读取尚未更新的 `clickedRow`。
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        contextMenuRow = row
        guard row >= 0, row < numberOfRows else { return nil }
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return super.menu(for: event)
    }

    /// 仅在树自身持有键盘焦点时拦截 Cmd+F / Cmd+C。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let key = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        guard let responder = window?.firstResponder as? NSView,
              self === responder || responder.isDescendant(of: self) else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "f":
            onRequestFind?()
            return true
        case "c":
            onCopyValue?()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

/// AppKit JSON 树包装器。
struct TreeView: NSViewRepresentable {
    @Environment(EditorViewModel.self) private var viewModel

    /// 右侧树请求显示搜索框时执行。
    let onRequestFind: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let outlineView = ContextMenuOutlineView()
        outlineView.headerView = nil
        outlineView.indentationPerLevel = 16
        outlineView.rowHeight = 22
        outlineView.usesAutomaticRowHeights = true
        outlineView.backgroundColor = NSColor(hex: "#252526")
        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.menu = context.coordinator.buildMenu()
        outlineView.onRequestFind = onRequestFind
        outlineView.onCopyValue = { [weak coordinator = context.coordinator] in
            coordinator?.copySelectedValue()
        }
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.doubleClicked(_:))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TreeColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)

        context.coordinator.outlineView = outlineView
        scrollView.documentView = outlineView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let outlineView = (context.coordinator.outlineView as? ContextMenuOutlineView)
        outlineView?.onRequestFind = onRequestFind
        outlineView?.onCopyValue = { [weak coordinator = context.coordinator] in
            coordinator?.copySelectedValue()
        }
        context.coordinator.reloadIfNeeded(viewModel: viewModel)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// 负责数据源、搜索呈现和用户展开状态的 AppKit 协调器。
    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        weak var outlineView: NSOutlineView?

        private var lastTreeRoot: JSONNode?
        private var lastTreeSearchMatches: [TreeSearchMatch] = []
        private var lastActiveTreeSearchIndex = 0
        private var lastTreeSearchQuery = ""
        private var expansionState = TreeExpansionState()

        /// 最近一次已经应用到大纲的展开集合，用于把结果切换限制为 O(路径深度)。
        private var lastAppliedExpandedIDs: Set<TreeNodeID> = []

        /// 程序化展开/收起期间为 true，防止 delegate 回调污染用户状态。
        private var isApplyingSystemExpansion = false

        /// 创建树节点右键菜单。
        ///
        /// - Returns: 包含 Copy Key、Copy Value 和 Copy JSON Path 的菜单。
        func buildMenu() -> NSMenu {
            let menu = NSMenu()

            let copyKeyItem = NSMenuItem(
                title: "Copy Key",
                action: #selector(copyNodeKey),
                keyEquivalent: ""
            )
            copyKeyItem.target = self
            menu.addItem(copyKeyItem)

            let copyValueItem = NSMenuItem(
                title: "Copy Value",
                action: #selector(copyNodeValue),
                keyEquivalent: ""
            )
            copyValueItem.target = self
            menu.addItem(copyValueItem)

            menu.addItem(.separator())

            let copyPathItem = NSMenuItem(
                title: "Copy JSON Path",
                action: #selector(copyJSONPath),
                keyEquivalent: ""
            )
            copyPathItem.target = self
            menu.addItem(copyPathItem)
            return menu
        }

        /// 双击容器行时按用户操作切换展开状态。
        @objc func doubleClicked(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0,
                  let item = sender.item(atRow: row),
                  sender.isExpandable(item) else {
                return
            }
            if sender.isItemExpanded(item) {
                sender.collapseItem(item)
            } else {
                sender.expandItem(item)
            }
        }

        @objc private func copyNodeKey() {
            guard let item = contextMenuItem() else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.key, forType: .string)
        }

        @objc private func copyNodeValue() {
            guard let item = contextMenuItem() else { return }
            copyValue(of: item)
        }

        /// 复制当前选中行的值（Cmd+C 快捷键入口）。
        func copySelectedValue() {
            guard let outlineView,
                  outlineView.selectedRow >= 0,
                  let item = outlineView.item(atRow: outlineView.selectedRow) as? JSONTree.Item else {
                return
            }
            copyValue(of: item)
        }

        private func copyValue(of item: JSONTree.Item) {
            let valueString: String
            if case .string(let value) = item.node {
                valueString = value
            } else {
                valueString = JSONParser.serialize(item.node)
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(valueString, forType: .string)
        }

        @objc private func copyJSONPath() {
            guard let item = contextMenuItem() else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.jsonPath, forType: .string)
        }

        /// 返回最近一次右键命中的真实树项。
        private func contextMenuItem() -> JSONTree.Item? {
            guard let contextView = outlineView as? ContextMenuOutlineView,
                  contextView.contextMenuRow >= 0 else {
                return nil
            }
            return contextView.item(atRow: contextView.contextMenuRow) as? JSONTree.Item
        }

        /// 把最新树结构和搜索状态增量同步到 NSOutlineView。
        ///
        /// - Parameter viewModel: 当前编辑器状态。
        func reloadIfNeeded(viewModel: EditorViewModel) {
            guard let treeRoot = viewModel.treeRoot else {
                if lastTreeRoot != nil {
                    lastTreeRoot = nil
                    lastTreeSearchMatches = []
                    lastActiveTreeSearchIndex = 0
                    lastTreeSearchQuery = ""
                    expansionState = TreeExpansionState()
                    lastAppliedExpandedIDs = []
                    outlineView?.reloadData()
                }
                return
            }

            let tree = JSONTree(root: treeRoot)
            let treeChanged = treeRoot != lastTreeRoot
            let queryChanged = viewModel.treeSearchQuery != lastTreeSearchQuery
            let resultsChanged = viewModel.treeSearchMatches != lastTreeSearchMatches
            let indexChanged = viewModel.activeTreeSearchIndex != lastActiveTreeSearchIndex

            if treeChanged {
                lastTreeRoot = treeRoot
                lastTreeSearchMatches = []
                lastActiveTreeSearchIndex = 0
                lastTreeSearchQuery = ""
                expansionState = TreeExpansionState()
                lastAppliedExpandedIDs = []
                expansionState.recordUserExpanded(.root)
                outlineView?.reloadData()
                applyEffectiveExpansion(tree: tree)
            }

            updateSearchSession(
                query: viewModel.treeSearchQuery,
                activeMatch: viewModel.activeTreeSearchMatch,
                queryChanged: queryChanged,
                resultsChanged: resultsChanged,
                indexChanged: indexChanged,
                tree: tree
            )

            lastTreeSearchQuery = viewModel.treeSearchQuery
            lastTreeSearchMatches = viewModel.treeSearchMatches
            lastActiveTreeSearchIndex = viewModel.activeTreeSearchIndex

            selectAndScroll(
                to: viewModel.activeTreeSearchMatch,
                tree: tree
            )
            reloadVisibleRowsHighlightOnly()
        }

        /// 更新搜索会话和当前结果的系统临时展开路径。
        private func updateSearchSession(
            query: String,
            activeMatch: TreeSearchMatch?,
            queryChanged: Bool,
            resultsChanged: Bool,
            indexChanged: Bool,
            tree: JSONTree
        ) {
            if query.isEmpty {
                if !lastTreeSearchQuery.isEmpty {
                    expansionState.endSearchSession()
                    applyEffectiveExpansion(tree: tree)
                }
                return
            }

            if lastTreeSearchQuery.isEmpty || queryChanged {
                expansionState.beginSearchSession()
            }
            guard queryChanged || resultsChanged || indexChanged else { return }

            expansionState.replaceSystemExpansion(
                with: activeMatch?.ancestorIDs ?? []
            )
            applyEffectiveExpansion(tree: tree)
        }

        /// 让 NSOutlineView 精确呈现“用户状态 ∪ 当前系统临时状态”。
        private func applyEffectiveExpansion(tree: JSONTree) {
            guard let outlineView else { return }
            let desiredExpandedIDs = expansionState.effectiveExpandedIDs
            let removedExpandedIDs =
                lastAppliedExpandedIDs.subtracting(desiredExpandedIDs)
            let addedExpandedIDs =
                desiredExpandedIDs.subtracting(lastAppliedExpandedIDs)
            isApplyingSystemExpansion = true
            defer { isApplyingSystemExpansion = false }

            // 只撤销集合差异，避免大 JSON 每次切换结果都扫描全部大纲行。
            for nodeID in removedExpandedIDs.sorted(
                by: { $0.components.count > $1.components.count }
            ) {
                guard let item = tree.item(for: nodeID) else { continue }
                outlineView.collapseItem(item)
            }

            // 再按深度从浅到深展开，保证子节点出现前祖先已经可见。
            for nodeID in addedExpandedIDs.sorted(
                by: { $0.components.count < $1.components.count }
            ) {
                guard let item = tree.item(for: nodeID) else { continue }
                outlineView.expandItem(item)
            }
            lastAppliedExpandedIDs = desiredExpandedIDs
        }

        /// 只刷新可见行的富文本，避免展开大数组时遍历全部行。
        private func reloadVisibleRowsHighlightOnly() {
            guard let outlineView else { return }
            let visibleRows = outlineView.rows(in: outlineView.visibleRect)
            guard visibleRows.location != NSNotFound, visibleRows.length > 0 else { return }

            for row in visibleRows.location..<NSMaxRange(visibleRows) {
                guard row < outlineView.numberOfRows,
                      let cell = outlineView.view(
                        atColumn: 0,
                        row: row,
                        makeIfNecessary: false
                      ) as? NSTableCellView,
                      let item = outlineView.item(atRow: row) as? JSONTree.Item else {
                    continue
                }
                cell.textField?.attributedStringValue = attributedText(for: item)
            }
        }

        // MARK: - NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let root = lastTreeRoot else { return 0 }
            return JSONTree(root: root).numberOfChildren(of: item as? JSONTree.Item)
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let root = lastTreeRoot else { return "" }
            return JSONTree(root: root).child(of: item as? JSONTree.Item, at: index) ?? ""
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let root = lastTreeRoot,
                  let item = item as? JSONTree.Item else {
                return false
            }
            return JSONTree(root: root).isExpandable(item)
        }

        // MARK: - NSOutlineViewDelegate

        /// 把真实用户展开写入用户状态；系统展开由 guard 排除。
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !isApplyingSystemExpansion,
                  let item = notification.userInfo?["NSObject"] as? JSONTree.Item else {
                return
            }
            expansionState.recordUserExpanded(item.id)
            lastAppliedExpandedIDs.insert(item.id)
        }

        /// 把真实用户收起写入用户状态，并阻止本次搜索再次强行展开。
        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isApplyingSystemExpansion,
                  let item = notification.userInfo?["NSObject"] as? JSONTree.Item else {
                return
            }
            expansionState.recordUserCollapsed(item.id)
            lastAppliedExpandedIDs.remove(item.id)
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let item = item as? JSONTree.Item else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("TreeCell")
            var cell = outlineView.makeView(
                withIdentifier: identifier,
                owner: self
            ) as? NSTableCellView
            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = identifier
                let textField = NSTextField()
                textField.isEditable = false
                textField.isBordered = false
                textField.drawsBackground = false
                textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                textField.lineBreakMode = .byWordWrapping
                textField.maximumNumberOfLines = 0
                textField.translatesAutoresizingMaskIntoConstraints = false
                cell?.addSubview(textField)
                cell?.textField = textField
                if let cell {
                    NSLayoutConstraint.activate([
                        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                        textField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 3),
                        textField.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -3),
                    ])
                }
            }
            cell?.textField?.attributedStringValue = attributedText(for: item)
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            guard let item = item as? JSONTree.Item else { return outlineView.rowHeight }
            let levelInset = CGFloat(max(outlineView.level(forItem: item), 0))
                * outlineView.indentationPerLevel
            let availableWidth = max(outlineView.bounds.width - levelInset - 28, 80)
            let bounds = attributedText(for: item).boundingRect(
                with: NSSize(
                    width: availableWidth,
                    height: CGFloat.greatestFiniteMagnitude
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return max(22, ceil(bounds.height) + 8)
        }

        /// 用户状态优先：若用户收起当前临时祖先，保持收起，不由搜索立即反向展开。
        func outlineView(
            _ outlineView: NSOutlineView,
            shouldCollapseItem item: Any
        ) -> Bool {
            true
        }

        /// 为节点生成类型着色和搜索范围高亮后的文本。
        private func attributedText(for item: JSONTree.Item) -> NSAttributedString {
            let keyColor = NSColor(hex: "#9cdcfe")
            let valueColor: NSColor
            switch item.node {
            case .string:
                valueColor = NSColor(hex: "#ce9178")
            case .number:
                valueColor = NSColor(hex: "#b5cea8")
            case .bool, .null:
                valueColor = NSColor(hex: "#569cd6")
            default:
                valueColor = NSColor(hex: "#d4d4d4")
            }

            let result = NSMutableAttributedString()
            result.append(NSAttributedString(
                string: "\(item.key): ",
                attributes: [.foregroundColor: keyColor]
            ))
            result.append(NSAttributedString(
                string: item.node.summary,
                attributes: [.foregroundColor: valueColor]
            ))
            applySearchHighlights(to: result, item: item)
            return result
        }

        /// 只对索引明确属于当前节点的精确范围应用背景色。
        private func applySearchHighlights(
            to text: NSMutableAttributedString,
            item: JSONTree.Item
        ) {
            let valueOffset = (item.key as NSString).length + 2
            for (index, match) in lastTreeSearchMatches.enumerated()
            where match.nodeID == item.id {
                let offset = match.field == .key ? 0 : valueOffset
                let range = NSRange(
                    location: offset + match.matchRange.location,
                    length: match.matchRange.length
                )
                guard NSMaxRange(range) <= text.length else { continue }
                let color = index == lastActiveTreeSearchIndex
                    ? JSONTextView.activeSearchMatchColor
                    : JSONTextView.searchMatchColor
                text.addAttribute(.backgroundColor, value: color, range: range)
            }
        }

        /// 选中并滚动到稳定节点身份对应的可见行。
        private func selectAndScroll(
            to match: TreeSearchMatch?,
            tree: JSONTree
        ) {
            guard let outlineView else { return }
            guard let match,
                  let item = tree.item(for: match.nodeID) else {
                outlineView.deselectAll(nil)
                return
            }

            var row = outlineView.row(forItem: item)
            if row < 0 {
                // AppKit 在少数桥接场景下不会用 Hashable 身份匹配新值，回退扫描可见行。
                row = (0..<outlineView.numberOfRows).first { candidate in
                    (outlineView.item(atRow: candidate) as? JSONTree.Item)?.id == match.nodeID
                } ?? -1
            }
            guard row >= 0 else { return }
            outlineView.selectRowIndexes(
                IndexSet(integer: row),
                byExtendingSelection: false
            )
            outlineView.scrollRowToVisible(row)
        }
    }
}
