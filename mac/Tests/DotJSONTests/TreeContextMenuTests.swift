import DotJSONCore
import Foundation
import Testing
@testable import DotJSON

/// 树右键菜单启用规则与安全确认约束。
struct TreeContextMenuTests {
    @Test func expandCollapseOnlyEnabledForContainers() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"{"obj":{"a":1},"leaf":"x"}"#))
        let root = tree.child(of: nil, at: 0)!
        let obj = tree.child(of: root, at: 1)! // sorted: leaf(0), obj(1)
        let leaf = tree.child(of: root, at: 0)!

        #expect(TreeContextMenuValidation.allowsExpandCollapse(for: obj))
        #expect(!TreeContextMenuValidation.allowsExpandCollapse(for: leaf))
        #expect(TreeContextMenuValidation.allowsExpandCollapse(for: root))
    }

    @Test func deleteDisabledOnlyForRoot() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"{"child":1}"#))
        let root = tree.child(of: nil, at: 0)!
        let child = tree.child(of: root, at: 0)!

        #expect(!TreeContextMenuValidation.allowsDelete(for: root))
        #expect(TreeContextMenuValidation.allowsDelete(for: child))
    }

    /// 删除确认必须以 Cancel 为默认按钮，避免回车直接删。
    @Test func deleteConfirmationUsesCancelAsDefaultButton() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/TreeView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("addButton(withTitle: \"Cancel\")"))
        #expect(source.contains("addButton(withTitle: \"Delete\")"))
        #expect(source.contains("hasDestructiveAction = true"))
        #expect(source.contains(".alertSecondButtonReturn"))
        #expect(source.contains("outlineView?.window"))
        #expect(source.contains("contextMenuItemSnapshot"))
        #expect(source.contains("expandItem(liveItem, expandChildren: true)"))
        #expect(source.contains("collapseItem(liveItem, collapseChildren: true)"))
        #expect(source.contains("presentDeleteFailure"))
        #expect(!source.contains("try? editorViewModel.deleteNode"))
    }
}
