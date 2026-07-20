import Foundation

/// JSON 树节点的稳定身份。
///
/// 字符串 key 和数组下标使用不同的路径组件，避免对象 key `"0"` 与数组下标 `0`
/// 发生碰撞；也不依赖节点显示文本，因此重复 key/value 仍能独立导航。
struct TreeNodeID: Hashable, Sendable {
    /// 构成节点路径的单个组件。
    enum Component: Hashable, Sendable {
        case key(String)
        case index(Int)
    }

    /// 从 JSON 根节点到当前节点的路径；空数组表示根节点。
    let components: [Component]

    /// JSON 根节点身份。
    static let root = TreeNodeID(components: [])

    /// 返回追加一个路径组件后的子节点身份。
    ///
    /// - Parameter component: 对象 key 或数组下标。
    /// - Returns: 新的子节点身份。
    func appending(_ component: Component) -> TreeNodeID {
        TreeNodeID(components: components + [component])
    }
}

/// 树搜索命中所在的显示字段。
enum TreeSearchField: Sendable, Equatable {
    case key
    case value
}

/// 一条可唯一定位到树节点和字段内文本范围的搜索结果。
struct TreeSearchMatch: Sendable, Equatable {
    /// 命中节点的稳定身份。
    let nodeID: TreeNodeID

    /// 从根节点到命中节点父节点的有序身份链。
    let ancestorIDs: [TreeNodeID]

    /// 命中发生在节点 key 还是显示 value。
    let field: TreeSearchField

    /// 命中在对应显示字符串中的 UTF-16 范围。
    let matchRange: NSRange

    /// 当前查询文本，用于视图层绘制背景高亮。
    let matchedText: String
}

/// JSON 树的只读扁平搜索索引。
///
/// 索引在树结构变化时建立一次。查询只线性扫描预先保存的 key/value 字符串，结果直接携带
/// 节点身份与祖先链，因此切换结果时不需要再次 DFS 整棵树。
struct TreeSearchIndex: Sendable {
    /// 一条节点搜索记录。
    private struct Record: Sendable {
        let nodeID: TreeNodeID
        let ancestorIDs: [TreeNodeID]
        let key: String
        let value: String
    }

    private let records: [Record]

    /// 为指定 JSON 根节点建立扁平搜索索引。
    ///
    /// - Parameter root: 已成功解析的 JSON 树根节点。
    init(root: JSONNode) {
        var records: [Record] = []
        let rootKey: String
        switch root {
        case .object:
            rootKey = "{root}"
        case .array:
            rootKey = "[root]"
        default:
            rootKey = "root"
        }
        Self.appendRecords(
            node: root,
            key: rootKey,
            nodeID: .root,
            ancestorIDs: [],
            to: &records
        )
        self.records = records
    }

    /// 查找所有 key/value 命中。
    ///
    /// - Parameter query: 区分大小写的非空查询文本。
    /// - Returns: 按树的显示顺序排列的精确命中；空查询返回空数组。
    func matches(query: String) -> [TreeSearchMatch] {
        guard !query.isEmpty else { return [] }

        var matches: [TreeSearchMatch] = []
        for record in records {
            Self.appendMatches(
                query: query,
                in: record.key,
                field: .key,
                record: record,
                to: &matches
            )
            Self.appendMatches(
                query: query,
                in: record.value,
                field: .value,
                record: record,
                to: &matches
            )
        }
        return matches
    }

    /// 深度优先生成节点记录，同时保存祖先链。
    private static func appendRecords(
        node: JSONNode,
        key: String,
        nodeID: TreeNodeID,
        ancestorIDs: [TreeNodeID],
        to records: inout [Record]
    ) {
        records.append(Record(
            nodeID: nodeID,
            ancestorIDs: ancestorIDs,
            key: key,
            value: node.summary
        ))

        let childAncestors = ancestorIDs + [nodeID]
        switch node {
        case .object(let pairs):
            for pair in pairs {
                appendRecords(
                    node: pair.value,
                    key: pair.key,
                    nodeID: nodeID.appending(.key(pair.key)),
                    ancestorIDs: childAncestors,
                    to: &records
                )
            }
        case .array(let items):
            for (index, child) in items.enumerated() {
                appendRecords(
                    node: child,
                    key: "[\(index)]",
                    nodeID: nodeID.appending(.index(index)),
                    ancestorIDs: childAncestors,
                    to: &records
                )
            }
        default:
            break
        }
    }

    /// 把一个显示字符串中的全部 UTF-16 命中追加到结果。
    private static func appendMatches(
        query: String,
        in text: String,
        field: TreeSearchField,
        record: Record,
        to matches: inout [TreeSearchMatch]
    ) {
        let source = text as NSString
        var remaining = NSRange(location: 0, length: source.length)

        while remaining.length > 0 {
            let range = source.range(of: query, options: [], range: remaining)
            guard range.location != NSNotFound else { break }

            matches.append(TreeSearchMatch(
                nodeID: record.nodeID,
                ancestorIDs: record.ancestorIDs,
                field: field,
                matchRange: range,
                matchedText: query
            ))

            let nextLocation = NSMaxRange(range)
            remaining = NSRange(
                location: nextLocation,
                length: source.length - nextLocation
            )
        }
    }
}
