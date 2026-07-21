import Foundation

/// 不依赖界面的 JSON 校验、格式化与压缩能力。
public enum JSONFormatter {
    /// 可用的格式化缩进方式。
    public enum Indent: Sendable, Equatable, CaseIterable {
        case twoSpaces
        case fourSpaces
        case tab

        /// 面向用户的缩进名称。
        public var label: String {
            switch self {
            case .twoSpaces: return "2 spaces"
            case .fourSpaces: return "4 spaces"
            case .tab: return "Tab"
            }
        }

        /// 实际写入每一级的缩进字符串。
        public var rawValue: String {
            switch self {
            case .twoSpaces: return "  "
            case .fourSpaces: return "    "
            case .tab: return "\t"
            }
        }
    }

    /// 生成 key 排序后的可读 JSON。
    ///
    /// - Parameters:
    ///   - json: 输入 JSON 文本。
    ///   - indent: 每级缩进方式。
    /// - Returns: 格式化后的 JSON。
    /// - Throws: 输入不是合法 JSON 时抛出 Foundation 解析错误。
    public static func format(_ json: String, indent: Indent = .fourSpaces) throws -> String {
        let data = try validate(json)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try prettyPrint(object, indent: indent.rawValue)
    }

    /// 生成 key 排序后的单行 JSON。
    ///
    /// - Parameter json: 输入 JSON 文本。
    /// - Returns: 压缩后的 JSON。
    /// - Throws: 输入不是合法 JSON 时抛出 Foundation 解析错误。
    public static func minify(_ json: String) throws -> String {
        let data = try validate(json)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let compact = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
        return String(data: compact, encoding: .utf8) ?? json
    }

    /// 校验 JSON 并返回原始 UTF-8 数据。
    ///
    /// - Parameter json: 待校验文本。
    /// - Returns: 输入对应的 UTF-8 数据。
    /// - Throws: 编码或 JSON 语法无效时抛出错误。
    public static func validate(_ json: String) throws -> Data {
        if let byteOffset = StrictJSONSyntax.trailingCommaByteOffset(in: json) {
            throw NSError(
                domain: "DotJSONCore",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Trailing commas are not valid JSON.",
                    "NSJSONSerializationErrorIndex": byteOffset,
                ]
            )
        }

        guard let data = json.data(using: .utf8) else {
            throw NSError(
                domain: "DotJSONCore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 encoding."]
            )
        }
        _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return data
    }

    /// 递归输出对象，并应用调用方指定的缩进。
    private static func prettyPrint(_ value: Any, indent: String, level: Int = 0) throws -> String {
        let prefix = String(repeating: indent, count: level)
        let childPrefix = String(repeating: indent, count: level + 1)

        switch value {
        case let dictionary as [String: Any]:
            guard !dictionary.isEmpty else { return "{}" }
            let items = try dictionary.sorted { $0.key < $1.key }.map { key, value in
                let encoded = try prettyPrint(value, indent: indent, level: level + 1)
                return "\(childPrefix)\(jsonEncodeLeaf(key)): \(encoded)"
            }
            return "{\n\(items.joined(separator: ",\n"))\n\(prefix)}"
        case let array as [Any]:
            guard !array.isEmpty else { return "[]" }
            let items = try array.map {
                "\(childPrefix)\(try prettyPrint($0, indent: indent, level: level + 1))"
            }
            return "[\n\(items.joined(separator: ",\n"))\n\(prefix)]"
        default:
            return jsonEncodeLeaf(value)
        }
    }

    /// 通过数组包装安全序列化单个 JSON 标量。
    private static func jsonEncodeLeaf(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: [value],
            options: [.sortedKeys, .withoutEscapingSlashes]
        ), var result = String(data: data, encoding: .utf8) else {
            return "null"
        }
        result.removeFirst()
        result.removeLast()
        return result
    }
}
