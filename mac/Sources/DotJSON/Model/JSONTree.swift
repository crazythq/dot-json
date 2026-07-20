import Foundation
import DotJSONCore

/// Tree wrapper around JSONNode for NSOutlineView data source.
///
/// The invisible root (nil) always has exactly 1 child — the root `Item`.
/// This Item wraps the actual JSON root and can be expanded to show children.
struct JSONTree {
    let root: JSONNode

    struct Item: Identifiable, Hashable {
        let id: TreeNodeID
        let key: String
        let node: JSONNode

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    init(root: JSONNode) {
        self.root = root
    }

    // MARK: - Data Source

    /// The invisible root always has 1 child: the root wrapper item.
    func numberOfChildren(of item: Item?) -> Int {
        if item == nil {
            return 1 // always one root item
        }
        return item!.node.childCount
    }

    func child(of item: Item?, at index: Int) -> Item? {
        if item == nil {
            guard index == 0 else { return nil }
            let key: String
            switch root {
            case .object: key = "{root}"
            case .array:  key = "[root]"
            default:      key = "root"
            }
            return Item(id: .root, key: key, node: root)
        }

        let node = item!.node
        switch node {
        case .object(let pairs):
            guard pairs.indices.contains(index) else { return nil }
            let pair = pairs[index]
            return Item(
                id: item!.id.appending(.key(pair.key)),
                key: pair.key,
                node: pair.value
            )
        case .array(let items):
            guard items.indices.contains(index) else { return nil }
            return Item(
                id: item!.id.appending(.index(index)),
                key: "[\(index)]",
                node: items[index]
            )
        default:
            return nil
        }
    }

    func isExpandable(_ item: Item?) -> Bool {
        guard let item else { return true }
        return item.node.isContainer
    }

    /// 按稳定节点身份直接取得树项。
    ///
    /// - Parameter nodeID: 从根到目标节点的 key/index 路径。
    /// - Returns: 路径与当前树结构匹配时返回目标项，否则返回 `nil`。
    ///
    /// 搜索结果已经携带完整身份，因此这里只按路径深度导航，不再 DFS 扫描其他分支。
    func item(for nodeID: TreeNodeID) -> Item? {
        var currentNode = root
        var currentID = TreeNodeID.root
        var currentKey: String
        switch root {
        case .object:
            currentKey = "{root}"
        case .array:
            currentKey = "[root]"
        default:
            currentKey = "root"
        }

        for component in nodeID.components {
            switch (currentNode, component) {
            case let (.object(pairs), .key(requestedKey)):
                guard let pair = pairs.first(where: { $0.key == requestedKey }) else {
                    return nil
                }
                currentNode = pair.value
                currentID = currentID.appending(.key(requestedKey))
                currentKey = requestedKey
            case let (.array(items), .index(index)):
                guard items.indices.contains(index) else { return nil }
                currentNode = items[index]
                currentID = currentID.appending(.index(index))
                currentKey = "[\(index)]"
            default:
                return nil
            }
        }

        return Item(id: currentID, key: currentKey, node: currentNode)
    }
}

extension JSONTree.Item {
    /// 当前节点的完整 JSONPath。
    var jsonPath: String {
        var path = "$"
        for component in id.components {
            switch component {
            case .key(let key):
                path += ".\(key)"
            case .index(let index):
                path += "[\(index)]"
            }
        }
        return path
    }
}
