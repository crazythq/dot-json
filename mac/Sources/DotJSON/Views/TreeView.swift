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
                    outlineView?.reloadData()
                }
                return
            }
            let tree = JSONTree(root: treeRoot)
            if treeRoot != lastTreeRoot {
                // 数据源回调发生在 reloadData() 内部，必须先发布新根节点。
                lastTreeRoot = treeRoot
                outlineView?.reloadData()
                if let rootItem = outlineView?.item(atRow: 0) {
                    outlineView?.expandItem(rootItem)
                } else {
                    outlineView?.expandItem(tree.child(of: nil, at: 0))
                }
            }
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
                tf.lineBreakMode = .byTruncatingTail
                tf.translatesAutoresizingMaskIntoConstraints = false
                cell!.addSubview(tf)
                cell!.textField = tf
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                    tf.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                ])
            }
            cell!.textField?.attributedStringValue = attributedText(for: item)
            return cell
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
            return result
        }
    }
}
