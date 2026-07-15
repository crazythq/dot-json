import Foundation

/// Single source of truth for JSON ↔ model conversion.
/// Uses Foundation's JSONSerialization, zero third-party dependencies.
enum JSONParser {

    enum ParseError: Error, LocalizedError, Sendable {
        /// 输入不是合法 JSON。
        ///
        /// - Parameters:
        ///   - detail: 可直接展示给用户的解析错误说明。
        ///   - byteOffset: Foundation 返回的 UTF-8 字节偏移；没有定位信息时为 `nil`。
        case invalidJSON(detail: String, byteOffset: Int?)
        case notJSONObjectOrArray

        var errorDescription: String? {
            switch self {
            case .invalidJSON(let detail, _): return detail
            case .notJSONObjectOrArray:    return "Top-level value must be an object or array."
            }
        }

        /// Foundation 提供的 UTF-8 错误位置。
        var byteOffset: Int? {
            guard case .invalidJSON(_, let byteOffset) = self else { return nil }
            return byteOffset
        }
    }

    /// Convert a JSON string into a `JSONNode` tree.
    static func parse(_ text: String) throws(ParseError) -> JSONNode {
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

    private static func convert(_ value: Any) throws(ParseError) -> JSONNode {
        switch value {
        case let dict as [String: Any]:
            let pairs = dict.sorted { $0.key < $1.key }.map { (key: $0.key, value: try! convert($0.value)) }
            return .object(pairs)

        case let arr as [Any]:
            return .array(arr.map { try! convert($0) })

        case let str as String:
            return .string(str)

        case let num as NSNumber:
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .bool(num.boolValue)
            }
            return .number(num.stringValue)

        case is NSNull:
            return .null

        default:
            throw .notJSONObjectOrArray
        }
    }

    /// Serialize a `JSONNode` tree back to a JSON string.
    static func serialize(_ node: JSONNode) -> String {
        serializeAny(convertToAny(node))
    }

    private static func convertToAny(_ node: JSONNode) -> Any {
        switch node {
        case .object(let pairs):
            var dict = [String: Any]()
            for (k, v) in pairs { dict[k] = convertToAny(v) }
            return dict
        case .array(let items):
            return items.map { convertToAny($0) }
        case .string(let s):   return s
        case .number(let n):   return Double(n) ?? n
        case .bool(let b):     return b
        case .null:            return NSNull()
        }
    }

    private static func serializeAny(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return "null" }
        return String(data: data, encoding: .utf8) ?? "null"
    }
}
