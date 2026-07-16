import Foundation
import DotJSONCore

/// Tree wrapper around JSONNode for NSOutlineView data source.
///
/// The invisible root (nil) always has exactly 1 child — the root `Item`.
/// This Item wraps the actual JSON root and can be expanded to show children.
struct JSONTree {
    let root: JSONNode

    struct Item: Identifiable {
        let id: String
        let key: String
        let node: JSONNode
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
            return Item(id: "$", key: key, node: root)
        }

        let node = item!.node
        switch node {
        case .object(let pairs):
            guard pairs.indices.contains(index) else { return nil }
            let pair = pairs[index]
            return Item(id: "\(item!.id)/\(pair.key)", key: pair.key, node: pair.value)
        case .array(let items):
            guard items.indices.contains(index) else { return nil }
            return Item(id: "\(item!.id)/\(index)", key: "[\(index)]", node: items[index])
        default:
            return nil
        }
    }

    func isExpandable(_ item: Item?) -> Bool {
        guard let item else { return true }
        return item.node.isContainer
    }
}

extension JSONTree.Item {
    /// Full JSONPath for this item, derived from its ID.
    /// Example: id="$/users/0/name" → "$.users[0].name"
    var jsonPath: String {
        let parts = id.split(separator: "/")
        guard parts.count > 1 else { return "$" }
        var path = "$"
        for part in parts.dropFirst() {
            if part.allSatisfy(\.isNumber) {
                path += "[\(part)]"
            } else {
                path += ".\(part)"
            }
        }
        return path
    }
}
