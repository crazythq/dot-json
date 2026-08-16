import Foundation

/// 将 `JSONNode` 序列化为 Python repr 风格文本。
///
/// 输出面向 Python 的 `print`/`pprint` 结果：`null` 变为 `None`、`true`/`false`
/// 变为 `True`/`False`，字符串与 key 使用单引号包裹，便于复制回 Python 代码中。
public enum PythonLiteralSerializer {

    /// 将 JSON 树序列化为 Python repr 风格文本。
    ///
    /// - Parameters:
    ///   - node: 已解析的 JSON 树。
    ///   - indent: 每一级的缩进字符串（沿用编辑器缩进设置）。
    /// - Returns: 带缩进的多行 Python 字面量文本。
    public static func serialize(_ node: JSONNode, indent: String) -> String {
        pythonString(node, indent: indent, level: 0)
    }

    /// 递归序列化单个节点。
    ///
    /// - Parameters:
    ///   - node: 当前节点。
    ///   - indent: 每一级的缩进字符串。
    ///   - level: 当前层级，用于生成前缀缩进。
    /// - Returns: 当前节点的 Python 字面量文本。
    private static func pythonString(_ node: JSONNode, indent: String, level: Int) -> String {
        let prefix = String(repeating: indent, count: level)
        let childPrefix = String(repeating: indent, count: level + 1)

        switch node {
        case .object(let pairs):
            guard !pairs.isEmpty else { return "{}" }
            let items = pairs.map { pair in
                "\(childPrefix)\(quote(pair.key)): "
                    + pythonString(pair.value, indent: indent, level: level + 1)
            }
            return "{\n\(items.joined(separator: ",\n"))\n\(prefix)}"
        case .array(let items):
            guard !items.isEmpty else { return "[]" }
            let lines = items.map {
                "\(childPrefix)\(pythonString($0, indent: indent, level: level + 1))"
            }
            return "[\n\(lines.joined(separator: ",\n"))\n\(prefix)]"
        case .string(let value):
            return quote(value)
        case .number(let value):
            return value
        case .bool(let value):
            return value ? "True" : "False"
        case .null:
            return "None"
        }
    }

    /// 使用单引号包裹字符串，并按 Python 字面量规则转义。
    ///
    /// - Parameter value: 原始字符串。
    /// - Returns: 可直接用于 Python 源码的单引号字符串。
    private static func quote(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.unicodeScalars.count + 2)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x5C: // 反斜杠
                escaped += "\\\\"
            case 0x27: // 单引号
                escaped += "\\'"
            case 0x0A: // 换行
                escaped += "\\n"
            case 0x0D: // 回车
                escaped += "\\r"
            case 0x09: // 制表符
                escaped += "\\t"
            case 0x00...0x1F: // 其余控制字符
                escaped += String(format: "\\x%02x", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return "'\(escaped)'"
    }
}
