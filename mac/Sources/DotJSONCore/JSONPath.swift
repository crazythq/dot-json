import Foundation

/// JSON 路径分量：对象键或数组下标（点分路径中的数字段表示下标）。
public enum JSONPathComponent: Sendable, Equatable {
    case key(String)
    case index(Int)
}

/// 点分路径，例如 `user.items.0.name`。
public struct JSONPath: Sendable, Equatable, Hashable, Comparable {
    public let components: [JSONPathComponent]

    public init(_ components: [JSONPathComponent] = []) {
        self.components = components
    }

    public var isEmpty: Bool { components.isEmpty }

    public var description: String {
        guard !components.isEmpty else { return "" }
        return components.map { component in
            switch component {
            case .key(let key): return key
            case .index(let index): return String(index)
            }
        }.joined(separator: ".")
    }

    public static func < (lhs: JSONPath, rhs: JSONPath) -> Bool {
        lhs.description < rhs.description
    }

    /// 解析点分路径；纯数字段视为数组下标，否则为对象键。
    public static func parse(_ string: String) throws -> JSONPath {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return JSONPath() }
        var components: [JSONPathComponent] = []
        for segment in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
            let part = String(segment)
            if part.isEmpty {
                throw JSONPathError.invalidSegment
            }
            if part.allSatisfy(\.isNumber), let index = Int(part) {
                components.append(.index(index))
            } else {
                components.append(.key(part))
            }
        }
        return JSONPath(components)
    }

    public func appending(_ component: JSONPathComponent) -> JSONPath {
        JSONPath(components + [component])
    }

    public enum JSONPathError: Error, Sendable {
        case invalidSegment
        case traversalFailed
        case indexOutOfRange
        case keyNotFound
    }
}

// MARK: - JSONNode navigation

extension JSONNode {
    /// 读取路径上的节点；路径为空时返回自身。
    public func node(at path: JSONPath) throws -> JSONNode {
        var current = self
        for component in path.components {
            switch (current, component) {
            case (.object(let pairs), .key(let key)):
                guard let value = pairs.first(where: { $0.key == key })?.value else {
                    throw JSONPath.JSONPathError.keyNotFound
                }
                current = value
            case (.array(let items), .index(let index)):
                guard items.indices.contains(index) else {
                    throw JSONPath.JSONPathError.indexOutOfRange
                }
                current = items[index]
            default:
                throw JSONPath.JSONPathError.traversalFailed
            }
        }
        return current
    }

    /// 在副本上设置路径处的值；中间缺失的对象/数组会被创建。
    public func setting(_ value: JSONNode, at path: JSONPath) throws -> JSONNode {
        guard let head = path.components.first else { return value }
        let tail = JSONPath(Array(path.components.dropFirst()))
        switch self {
        case .object(var pairs):
            switch head {
            case .key(let key):
                let child: JSONNode
                if let index = pairs.firstIndex(where: { $0.key == key }) {
                    child = try pairs[index].value.setting(value, at: tail)
                    pairs[index].value = child
                } else if tail.isEmpty {
                    pairs.append((key: key, value: value))
                    pairs.sort { $0.key < $1.key }
                } else {
                    let scaffold: JSONNode = switch tail.components.first {
                    case .index?: .array([])
                    default: .object([])
                    }
                    let created = try scaffold.setting(value, at: tail)
                    pairs.append((key: key, value: created))
                    pairs.sort { $0.key < $1.key }
                }
                return .object(pairs)
            case .index:
                throw JSONPath.JSONPathError.traversalFailed
            }
        case .array(var items):
            guard case .index(let index) = head else {
                throw JSONPath.JSONPathError.traversalFailed
            }
            if tail.isEmpty {
                if items.indices.contains(index) {
                    items[index] = value
                } else {
                    while items.count < index {
                        items.append(.null)
                    }
                    items.append(value)
                }
                return .array(items)
            }
            if !items.indices.contains(index) {
                while items.count <= index {
                    items.append(.null)
                }
            }
            items[index] = try items[index].setting(value, at: tail)
            return .array(items)
        default:
            if tail.isEmpty { return value }
            throw JSONPath.JSONPathError.traversalFailed
        }
    }

    /// 删除路径处的节点；路径为空时返回 `null`。
    public func removing(at path: JSONPath) throws -> JSONNode {
        guard let head = path.components.first else { return .null }
        let tail = JSONPath(Array(path.components.dropFirst()))
        switch self {
        case .object(var pairs):
            guard case .key(let key) = head else {
                throw JSONPath.JSONPathError.traversalFailed
            }
            guard let index = pairs.firstIndex(where: { $0.key == key }) else {
                throw JSONPath.JSONPathError.keyNotFound
            }
            if tail.isEmpty {
                pairs.remove(at: index)
                return .object(pairs)
            }
            pairs[index].value = try pairs[index].value.removing(at: tail)
            return .object(pairs)
        case .array(var items):
            guard case .index(let index) = head else {
                throw JSONPath.JSONPathError.traversalFailed
            }
            guard items.indices.contains(index) else {
                throw JSONPath.JSONPathError.indexOutOfRange
            }
            if tail.isEmpty {
                items.remove(at: index)
                return .array(items)
            }
            items[index] = try items[index].removing(at: tail)
            return .array(items)
        default:
            throw JSONPath.JSONPathError.traversalFailed
        }
    }

    /// 若路径存在则返回值，否则 `nil`。
    public func optionalNode(at path: JSONPath) -> JSONNode? {
        try? node(at: path)
    }
}
