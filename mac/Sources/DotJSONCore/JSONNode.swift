import Foundation

/// 与平台无关的 JSON 树节点。
///
/// GUI 与 CLI 共用该模型，确保两种入口对 JSON 类型的理解一致。
public indirect enum JSONNode: Sendable, Equatable {
    case object([(key: String, value: JSONNode)])
    case array([JSONNode])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    /// 返回适合界面展示的节点类型名称。
    public var typeLabel: String {
        switch self {
        case .object: return "object"
        case .array:  return "array"
        case .string: return "string"
        case .number: return "number"
        case .bool:   return "bool"
        case .null:   return "null"
        }
    }

    /// 返回容器的直接子节点数量；标量返回零。
    public var childCount: Int {
        switch self {
        case .object(let pairs): return pairs.count
        case .array(let items):  return items.count
        default:                 return 0
        }
    }

    /// 表示当前节点是否可包含子节点。
    public var isContainer: Bool {
        switch self {
        case .object, .array: return true
        default:              return false
        }
    }

    /// 返回适合树视图紧凑展示的内容摘要。
    public var summary: String {
        switch self {
        case .object(let pairs): return "{ \(pairs.count) items }"
        case .array(let items):  return "[ \(items.count) items ]"
        case .string(let string): return "\"\(string)\""
        case .number(let number): return number
        case .bool(let value):    return value ? "true" : "false"
        case .null:               return "null"
        }
    }

    /// 比较两个 JSON 节点及其全部子节点。
    ///
    /// - Parameters:
    ///   - lhs: 左侧节点。
    ///   - rhs: 右侧节点。
    /// - Returns: 结构和值完全一致时返回 `true`。
    public static func == (lhs: JSONNode, rhs: JSONNode) -> Bool {
        switch (lhs, rhs) {
        case let (.object(leftPairs), .object(rightPairs)):
            guard leftPairs.count == rightPairs.count else { return false }
            return zip(leftPairs, rightPairs).allSatisfy {
                $0.key == $1.key && $0.value == $1.value
            }
        case let (.array(leftItems), .array(rightItems)):
            return leftItems == rightItems
        case let (.string(left), .string(right)):
            return left == right
        case let (.number(left), .number(right)):
            return left == right
        case let (.bool(left), .bool(right)):
            return left == right
        case (.null, .null):
            return true
        default:
            return false
        }
    }
}
