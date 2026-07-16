import Foundation
import DotJSONCore

// Platform-specific extensions for JSONNode (macOS App).
// All core types are now in the same module — no cross-module imports needed.
extension JSONNode {
    // Reserved for NSOutlineView data source helpers.
    // Example: childCount / isContainer / typeLabel already defined in JSONNode.swift.
}

extension JSONNode {
    /// Returns the JSONPath component for a child at the given index.
    /// - For objects: returns ".keyName"
    /// - For arrays: returns "[index]"
    /// - For leaf nodes or out-of-bounds: returns ""
    /// The UI (NSOutlineView data source) concatenates these along the tree path.
    func childPathComponent(at index: Int) -> String {
        switch self {
        case .object(let pairs):
            guard pairs.indices.contains(index) else { return "" }
            return ".\(pairs[index].key)"
        case .array(let items):
            guard items.indices.contains(index) else { return "" }
            return "[\(index)]"
        default:
            return ""
        }
    }
}
