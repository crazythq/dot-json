import SwiftUI
import AppKit
import DotJSONCore

struct TreeView: NSViewRepresentable {
    @Environment(EditorViewModel.self) private var viewModel

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.indentationPerLevel = 16
        outlineView.rowHeight = 22
        outlineView.usesAutomaticRowHeights = true
        outlineView.backgroundColor = NSColor(hex: "#252526")
        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.menu = context.coordinator.buildMenu()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TreeColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)

        context.coordinator.outlineView = outlineView
        scrollView.documentView = outlineView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.reloadIfNeeded(viewModel: viewModel)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        weak var outlineView: NSOutlineView?
        private var lastTreeRoot: JSONNode?
        private var lastSearchResults: [SearchResult] = []
        private var lastActiveSearchIndex: Int = 0

        func buildMenu() -> NSMenu {
            let menu = NSMenu()
            let copyPathItem = NSMenuItem(
                title: "Copy JSON Path",
                action: #selector(copyJSONPath),
                keyEquivalent: ""
            )
            copyPathItem.target = self
            menu.addItem(copyPathItem)
            return menu
        }

        @objc private func copyJSONPath() {
            guard let outlineView,
                  let item = outlineView.item(atRow: outlineView.clickedRow) as? JSONTree.Item else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.jsonPath, forType: .string)
        }

        func reloadIfNeeded(viewModel: EditorViewModel) {
            guard let treeRoot = viewModel.treeRoot else {
                if lastTreeRoot != nil {
                    // 清空也必须先更新数据源状态，否则 reloadData() 会再次读取旧根节点。
                    lastTreeRoot = nil
                    lastSearchResults = viewModel.searchResults
                    lastActiveSearchIndex = viewModel.activeSearchIndex
                    outlineView?.reloadData()
                }
                return
            }
            let tree = JSONTree(root: treeRoot)
            let searchChanged = lastSearchResults != viewModel.searchResults
                || lastActiveSearchIndex != viewModel.activeSearchIndex
            lastSearchResults = viewModel.searchResults
            lastActiveSearchIndex = viewModel.activeSearchIndex
            if treeRoot != lastTreeRoot {
                // 数据源回调发生在 reloadData() 内部，必须先发布新根节点。
                lastTreeRoot = treeRoot
                outlineView?.reloadData()
                if let rootItem = outlineView?.item(atRow: 0) {
                    outlineView?.expandItem(rootItem)
                } else {
                    outlineView?.expandItem(tree.child(of: nil, at: 0))
                }
            } else if searchChanged {
                outlineView?.reloadData()
            }
            if !viewModel.searchResults.isEmpty {
                // 搜索时展开子树，保证命中的原文值和 key 不被折叠层级藏住。
                outlineView?.expandItem(nil, expandChildren: true)
            }
            selectAndScrollToActiveSearchResult(viewModel.activeSearchResult)
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let root = lastTreeRoot else { return 0 }
            return JSONTree(root: root).numberOfChildren(of: item as? JSONTree.Item)
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let root = lastTreeRoot else { return "" }
            return JSONTree(root: root).child(of: item as? JSONTree.Item, at: index) ?? ""
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let root = lastTreeRoot, let item = item as? JSONTree.Item else { return false }
            return JSONTree(root: root).isExpandable(item)
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? JSONTree.Item else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("TreeCell")
            var cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            if cell == nil {
                cell = NSTableCellView()
                cell!.identifier = identifier
                let tf = NSTextField()
                tf.isEditable = false
                tf.isBordered = false
                tf.drawsBackground = false
                tf.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                tf.lineBreakMode = .byWordWrapping
                tf.maximumNumberOfLines = 0
                tf.translatesAutoresizingMaskIntoConstraints = false
                cell!.addSubview(tf)
                cell!.textField = tf
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                    tf.topAnchor.constraint(equalTo: cell!.topAnchor, constant: 3),
                    tf.bottomAnchor.constraint(equalTo: cell!.bottomAnchor, constant: -3),
                ])
            }
            cell!.textField?.attributedStringValue = attributedText(for: item)
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            guard let item = item as? JSONTree.Item else { return outlineView.rowHeight }
            let levelInset = CGFloat(max(outlineView.level(forItem: item), 0))
                * outlineView.indentationPerLevel
            let availableWidth = max(outlineView.bounds.width - levelInset - 28, 80)
            let bounds = attributedText(for: item).boundingRect(
                with: NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return max(22, ceil(bounds.height) + 8)
        }

        private func attributedText(for item: JSONTree.Item) -> NSAttributedString {
            let keyColor = NSColor(hex: "#9cdcfe")
            let valueColor: NSColor = {
                switch item.node {
                case .string: return NSColor(hex: "#ce9178")
                case .number: return NSColor(hex: "#b5cea8")
                case .bool, .null: return NSColor(hex: "#569cd6")
                default: return NSColor(hex: "#d4d4d4")
                }
            }()
            let result = NSMutableAttributedString()
            result.append(NSAttributedString(
                string: "\(item.key): ", attributes: [.foregroundColor: keyColor]))
            result.append(NSAttributedString(
                string: item.node.summary, attributes: [.foregroundColor: valueColor]))
            highlightSearchMatches(in: result, item: item)
            return result
        }

        /// 在树节点文本中标出搜索命中，并突出当前活动命中。
        ///
        /// - Parameters:
        ///   - text: 当前树节点的富文本。
        ///   - item: 富文本对应的树节点。
        private func highlightSearchMatches(in text: NSMutableAttributedString, item: JSONTree.Item) {
            guard let query = lastSearchResults.first?.matchedText, !query.isEmpty else { return }
            let fullText = text.string as NSString
            var searchRange = NSRange(location: 0, length: fullText.length)
            while true {
                let matchRange = fullText.range(of: query, options: [], range: searchRange)
                guard matchRange.location != NSNotFound else { break }
                let color = isItemMatchingActiveSearchResult(item)
                    ? JSONTextView.activeSearchMatchColor
                    : JSONTextView.searchMatchColor
                text.addAttribute(.backgroundColor, value: color, range: matchRange)
                let nextLocation = NSMaxRange(matchRange)
                searchRange = NSRange(
                    location: nextLocation,
                    length: fullText.length - nextLocation
                )
            }
        }

        /// 选中并滚动到当前搜索命中对应的可见树行。
        ///
        /// - Parameter result: 当前活动搜索结果；没有结果时清除树选择。
        private func selectAndScrollToActiveSearchResult(_ result: SearchResult?) {
            guard let outlineView else { return }
            guard let result else {
                outlineView.deselectAll(nil)
                return
            }

            for row in 0..<outlineView.numberOfRows {
                guard let item = outlineView.item(atRow: row) as? JSONTree.Item,
                      isItem(item, matching: result) else {
                    continue
                }
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                return
            }
        }

        /// 判断树节点是否包含活动搜索命中。
        ///
        /// - Parameter item: 待检查的树节点。
        /// - Returns: 当前节点包含活动命中时返回 `true`。
        private func isItemMatchingActiveSearchResult(_ item: JSONTree.Item) -> Bool {
            guard lastSearchResults.indices.contains(lastActiveSearchIndex) else { return false }
            return isItem(item, matching: lastSearchResults[lastActiveSearchIndex])
        }

        /// 判断搜索命中应该落在哪个树节点上。
        ///
        /// - Parameters:
        ///   - item: 待检查的树节点。
        ///   - result: 当前搜索命中。
        /// - Returns: key 命中匹配节点 key，值命中匹配节点摘要。
        private func isItem(_ item: JSONTree.Item, matching result: SearchResult) -> Bool {
            if result.isKey {
                return item.key.contains(result.matchedText)
            }
            return item.node.summary.contains(result.matchedText)
        }
    }
}
