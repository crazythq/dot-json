import Foundation

/// JSON 文本与 `JSONNode` 之间转换的唯一入口。
public enum JSONParser {
    /// JSON 解析过程中可能出现的确定性错误。
    public enum ParseError: Error, LocalizedError, Sendable {
        case invalidJSON(detail: String, byteOffset: Int?)
        case notJSONObjectOrArray

        /// 面向用户的错误说明。
        public var errorDescription: String? {
            switch self {
            case .invalidJSON(let detail, _): return detail
            case .notJSONObjectOrArray: return "Top-level value must be an object or array."
            }
        }

        /// Foundation 提供的 UTF-8 错误字节偏移。
        public var byteOffset: Int? {
            guard case .invalidJSON(_, let byteOffset) = self else { return nil }
            return byteOffset
        }
    }

    /// 将 JSON 字符串解析为树节点。
    ///
    /// - Parameter text: UTF-8 JSON 文本。
    /// - Returns: 解析后的 JSON 树。
    /// - Throws: 文本编码或 JSON 语法无效时抛出 `ParseError`。
    public static func parse(_ text: String) throws(ParseError) -> JSONNode {
        guard let data = text.data(using: .utf8) else {
            throw .invalidJSON(detail: "Invalid UTF-8 encoding.", byteOffset: nil)
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let cocoaError = error as NSError
            let detail = cocoaError.userInfo[NSDebugDescriptionErrorKey] as? String
                ?? cocoaError.localizedDescription
            let byteOffset = cocoaError.userInfo["NSJSONSerializationErrorIndex"] as? Int
            throw .invalidJSON(detail: detail, byteOffset: byteOffset)
        }
        return try convert(object)
    }

    /// 将 JSON 树序列化为确定性紧凑 JSON。
    ///
    /// - Parameter node: 待序列化的节点。
    /// - Returns: key 已排序的紧凑 JSON 字符串。
    public static func serialize(_ node: JSONNode) -> String {
        serializeAny(convertToAny(node))
    }

    /// 将 Foundation JSON 对象递归转换为树节点。
    private static func convert(_ value: Any) throws(ParseError) -> JSONNode {
        switch value {
        case let dictionary as [String: Any]:
            var pairs: [(key: String, value: JSONNode)] = []
            for entry in dictionary.sorted(by: { $0.key < $1.key }) {
                pairs.append((key: entry.key, value: try convert(entry.value)))
            }
            return .object(pairs)
        case let array as [Any]:
            var items: [JSONNode] = []
            for value in array {
                items.append(try convert(value))
            }
            return .array(items)
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.stringValue)
        case is NSNull:
            return .null
        default:
            throw .notJSONObjectOrArray
        }
    }

    /// 将树节点转换为 Foundation 可序列化对象。
    private static func convertToAny(_ node: JSONNode) -> Any {
        switch node {
        case .object(let pairs):
            return Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, convertToAny($0.value)) })
        case .array(let items):
            return items.map(convertToAny)
        case .string(let string): return string
        case .number(let number): return Double(number) ?? number
        case .bool(let value): return value
        case .null: return NSNull()
        }
    }

    /// 将 Foundation JSON 对象序列化为紧凑文本。
    private static func serializeAny(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else {
            return "null"
        }
        return String(data: data, encoding: .utf8) ?? "null"
    }
}
