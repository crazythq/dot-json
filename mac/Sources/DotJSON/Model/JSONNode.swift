import Foundation

/// Platform-agnostic tree node model for JSON structure.
/// Used by all platform targets (macOS, Windows, uTools, Raycast).
indirect enum JSONNode: Sendable, Equatable {
    case object([(key: String, value: JSONNode)])
    case array([JSONNode])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    var typeLabel: String {
        switch self {
        case .object: return "object"
        case .array:  return "array"
        case .string: return "string"
        case .number: return "number"
        case .bool:   return "bool"
        case .null:   return "null"
        }
    }

    var childCount: Int {
        switch self {
        case .object(let pairs): return pairs.count
        case .array(let items):  return items.count
        default:                 return 0
        }
    }

    var isContainer: Bool {
        switch self {
        case .object, .array: return true
        default:              return false
        }
    }

    var summary: String {
        switch self {
        case .object(let pairs): return "{ \(pairs.count) items }"
        case .array(let items):  return "[ \(items.count) items ]"
        case .string(let s):     return "\"\(s)\""
        case .number(let n):     return n
        case .bool(let b):       return b ? "true" : "false"
        case .null:              return "null"
        }
    }

    // MARK: - Equatable (manual — labeled tuples don't auto-synthesize)

    static func == (lhs: JSONNode, rhs: JSONNode) -> Bool {
        switch (lhs, rhs) {
        case let (.object(lPairs), .object(rPairs)):
            guard lPairs.count == rPairs.count else { return false }
            for (l, r) in zip(lPairs, rPairs) {
                guard l.key == r.key, l.value == r.value else { return false }
            }
            return true
        case let (.array(lItems), .array(rItems)):
            return lItems == rItems
        case let (.string(lStr), .string(rStr)):
            return lStr == rStr
        case let (.number(lNum), .number(rNum)):
            return lNum == rNum
        case let (.bool(lBool), .bool(rBool)):
            return lBool == rBool
        case (.null, .null):
            return true
        default:
            return false
        }
    }
}
