import Foundation

/// 将常见 Python 字面量输出修复为标准 JSON。
///
/// 该修复器只处理没有歧义的语法差异：单引号字符串、Python 常量、无引号对象 key 和容器尾逗号。
/// 它不会猜测裸 value、tuple、set、bytes、注释或截断结构，避免把无法确定语义的文本改坏。
enum JSONRepairer {

    /// Python 字面量修复失败时抛出的业务错误。
    enum RepairError: Error, LocalizedError, Equatable {
        /// 输入包含当前修复器不应猜测的语法。
        case unsupportedSyntax(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedSyntax(let message):
                return message
            }
        }
    }

    /// 把一个 Python `dict` / `list` 风格文本转换为标准 JSON。
    ///
    /// - Parameter input: 用户粘贴或输入的原始文本。
    /// - Returns: 只做必要字符替换后的标准 JSON 文本；合法 JSON 会原样返回。
    /// - Throws: `RepairError.unsupportedSyntax` 表示输入不在保守修复范围内。
    static func repair(_ input: String) throws -> String {
        if (try? JSONFormatter.validate(input)) != nil {
            return input
        }

        guard startsWithSupportedContainer(input) else {
            throw RepairError.unsupportedSyntax("Python repair requires a top-level dict or list.")
        }

        let repaired = try PythonLiteralScanner(input).repair()
        guard (try? JSONFormatter.validate(repaired)) != nil else {
            throw RepairError.unsupportedSyntax("Input cannot be repaired without guessing.")
        }
        return repaired
    }

    /// 判断输入是否以可安全修复的顶层容器开始。
    ///
    /// - Parameter input: 原始文本。
    /// - Returns: 输入去掉空白和 BOM 后以 `{` 或 `[` 开始时返回 `true`。
    private static func startsWithSupportedContainer(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutBOM = trimmed.first == "\u{FEFF}" ? String(trimmed.dropFirst()) : trimmed
        return withoutBOM.first == "{" || withoutBOM.first == "["
    }
}

/// 对 Python 字面量文本做字符串感知扫描和转换。
///
/// 扫描器逐字符前进，只有在字符串之外才转换 Python token、无引号 key 或移除尾逗号。
/// 这样可以保证字符串内容里的 `True`、`None`、逗号和括号不会被误改。
private struct PythonLiteralScanner {
    private let input: String

    /// 创建一个 Python 字面量扫描器。
    ///
    /// - Parameter input: 待修复的原始文本。
    init(_ input: String) {
        self.input = input
    }

    /// 执行完整扫描并返回候选 JSON。
    ///
    /// - Returns: 已替换单引号字符串、Python 常量、无引号 key 和尾逗号的文本。
    /// - Throws: 遇到裸 value、未闭合字符串或不支持的转义时抛出 `RepairError`。
    func repair() throws -> String {
        var output = ""
        var index = input.startIndex

        while index < input.endIndex {
            let character = input[index]

            if character == "'" {
                output += try parseSingleQuotedString(from: &index)
                continue
            }

            if character == "\"" {
                output += try copyDoubleQuotedString(from: &index)
                continue
            }

            if character == "," && isTrailingComma(at: index) {
                input.formIndex(after: &index)
                continue
            }

            if let token = pythonToken(at: index) {
                output += token.json
                index = token.endIndex
                continue
            }

            if isIdentifierStart(character) {
                output += try parseIdentifierToken(from: &index)
                continue
            }

            output.append(character)
            input.formIndex(after: &index)
        }

        return output
    }

    /// 解析 Python 单引号字符串并重新编码成 JSON 字符串。
    ///
    /// - Parameter index: 当前扫描位置，必须指向单引号；返回时移动到字符串后一个字符。
    /// - Returns: Foundation JSON 编码后的双引号字符串。
    /// - Throws: 字符串未闭合或包含不支持的 Python 转义时抛出 `RepairError`。
    private func parseSingleQuotedString(from index: inout String.Index) throws -> String {
        input.formIndex(after: &index)
        var decoded = ""

        while index < input.endIndex {
            let character = input[index]

            if character == "'" {
                input.formIndex(after: &index)
                return jsonEncodedString(decoded)
            }

            if character == "\\" {
                input.formIndex(after: &index)
                decoded.append(try parseEscape(from: &index))
                continue
            }

            decoded.append(character)
            input.formIndex(after: &index)
        }

        throw JSONRepairer.RepairError.unsupportedSyntax("Single-quoted string is not closed.")
    }

    /// 原样复制 JSON 双引号字符串。
    ///
    /// - Parameter index: 当前扫描位置，必须指向双引号；返回时移动到字符串后一个字符。
    /// - Returns: 输入中的双引号字符串原文。
    /// - Throws: 字符串未闭合时抛出 `RepairError`。
    private func copyDoubleQuotedString(from index: inout String.Index) throws -> String {
        var copied = "\""
        input.formIndex(after: &index)
        var isEscaped = false

        while index < input.endIndex {
            let character = input[index]
            copied.append(character)
            input.formIndex(after: &index)

            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return copied
            }
        }

        throw JSONRepairer.RepairError.unsupportedSyntax("Double-quoted string is not closed.")
    }

    /// 解析 Python 字符串转义序列。
    ///
    /// - Parameter index: 当前扫描位置，必须指向反斜杠后的第一个字符。
    /// - Returns: 解码后的单个或多个 Swift `Character`。
    /// - Throws: 转义不完整、十六进制位数不足或 Unicode 标量非法时抛出 `RepairError`。
    private func parseEscape(from index: inout String.Index) throws -> String {
        guard index < input.endIndex else {
            throw JSONRepairer.RepairError.unsupportedSyntax("Escape sequence is incomplete.")
        }

        let escaped = input[index]
        input.formIndex(after: &index)

        switch escaped {
        case "\\": return "\\"
        case "'": return "'"
        case "\"": return "\""
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        case "b": return "\u{08}"
        case "f": return "\u{0C}"
        case "x": return try parseHexEscape(length: 2, from: &index)
        case "u": return try parseHexEscape(length: 4, from: &index)
        case "U": return try parseHexEscape(length: 8, from: &index)
        default:
            throw JSONRepairer.RepairError.unsupportedSyntax("Unsupported Python string escape.")
        }
    }

    /// 解析固定长度的十六进制 Unicode 转义。
    ///
    /// - Parameters:
    ///   - length: Python 转义要求的十六进制位数。
    ///   - index: 当前扫描位置，返回时移动到转义数字后一个字符。
    /// - Returns: 解码后的 Unicode 标量字符串。
    /// - Throws: 位数不足、非十六进制字符、代理区或无效标量时抛出 `RepairError`。
    private func parseHexEscape(length: Int, from index: inout String.Index) throws -> String {
        var hex = ""
        for _ in 0..<length {
            guard index < input.endIndex, input[index].isHexDigit else {
                throw JSONRepairer.RepairError.unsupportedSyntax("Unicode escape is incomplete.")
            }
            hex.append(input[index])
            input.formIndex(after: &index)
        }

        guard let value = UInt32(hex, radix: 16),
              !(0xD800...0xDFFF).contains(value),
              let scalar = UnicodeScalar(value) else {
            throw JSONRepairer.RepairError.unsupportedSyntax("Unicode escape is invalid.")
        }
        return String(Character(scalar))
    }

    /// 检查当前位置的逗号是否为容器尾逗号。
    ///
    /// - Parameter index: 当前扫描位置，必须指向逗号。
    /// - Returns: 后续第一个非空白字符是 `}` 或 `]` 时返回 `true`。
    private func isTrailingComma(at index: String.Index) -> Bool {
        var next = input.index(after: index)
        while next < input.endIndex, input[next].isWhitespace {
            input.formIndex(after: &next)
        }
        return next < input.endIndex && (input[next] == "}" || input[next] == "]")
    }

    /// 识别当前位置是否为可安全转换的 Python 常量。
    ///
    /// - Parameter index: 当前扫描位置。
    /// - Returns: 匹配到 `True`、`False` 或 `None` 时返回 JSON 文本和 token 结束位置。
    private func pythonToken(at index: String.Index) -> (json: String, endIndex: String.Index)? {
        let tokenPairs = [
            ("False", "false"),
            ("True", "true"),
            ("None", "null"),
            ("false", "false"),
            ("true", "true"),
            ("null", "null"),
        ]
        for (python, json) in tokenPairs {
            guard input[index...].hasPrefix(python) else { continue }
            let end = input.index(index, offsetBy: python.count)
            if isTokenBoundary(before: index) && isTokenBoundary(after: end) {
                // `true:` 这类位置是对象 key，不是布尔值；交给 key 修复分支加引号。
                guard nextNonWhitespace(after: end) != ":" else { return nil }
                return (json, end)
            }
        }
        return nil
    }

    /// 解析字符串外的标识符 token。
    ///
    /// - Parameter index: 当前扫描位置，必须指向标识符首字符；返回时移动到标识符后一个字符。
    /// - Returns: 如果标识符后面是冒号，返回带双引号的 JSON key。
    /// - Throws: 标识符不是对象 key 时抛出 `RepairError`，避免把裸 value 猜成字符串。
    private func parseIdentifierToken(from index: inout String.Index) throws -> String {
        let start = index
        input.formIndex(after: &index)
        while index < input.endIndex, isIdentifierPart(input[index]) {
            input.formIndex(after: &index)
        }

        var lookahead = index
        while lookahead < input.endIndex, input[lookahead].isWhitespace {
            input.formIndex(after: &lookahead)
        }

        guard lookahead < input.endIndex, input[lookahead] == ":" else {
            throw JSONRepairer.RepairError.unsupportedSyntax(
                "Bare values are not safe to repair."
            )
        }

        return jsonEncodedString(String(input[start..<index]))
    }

    /// 查找指定位置之后第一个非空白字符。
    ///
    /// - Parameter index: 查找起点。
    /// - Returns: 后续第一个非空白字符；没有找到时返回 `nil`。
    private func nextNonWhitespace(after index: String.Index) -> Character? {
        var next = index
        while next < input.endIndex, input[next].isWhitespace {
            input.formIndex(after: &next)
        }
        return next < input.endIndex ? input[next] : nil
    }

    /// 判断 token 前一个字符是否为边界。
    ///
    /// - Parameter index: token 起始位置。
    /// - Returns: 起始位置在文本开头，或前一个字符不是标识符字符时返回 `true`。
    private func isTokenBoundary(before index: String.Index) -> Bool {
        guard index > input.startIndex else { return true }
        let previous = input[input.index(before: index)]
        return !isIdentifierPart(previous)
    }

    /// 判断 token 后一个字符是否为边界。
    ///
    /// - Parameter index: token 结束位置。
    /// - Returns: 结束位置在文本末尾，或当前字符不是标识符字符时返回 `true`。
    private func isTokenBoundary(after index: String.Index) -> Bool {
        guard index < input.endIndex else { return true }
        return !isIdentifierPart(input[index])
    }

    /// 判断字符是否可能开始 Python 标识符。
    ///
    /// - Parameter character: 当前字符。
    /// - Returns: ASCII 字母或下划线返回 `true`。
    private func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isASCII && character.isLetter
    }

    /// 判断字符是否可能属于 Python 标识符。
    ///
    /// - Parameter character: 当前字符。
    /// - Returns: ASCII 字母、数字或下划线返回 `true`。
    private func isIdentifierPart(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    /// 把 Swift 字符串编码为 JSON 字符串字面量。
    ///
    /// - Parameter string: 已解码的字符串内容。
    /// - Returns: 带双引号的 JSON 字符串；编码异常时返回空字符串字面量。
    private func jsonEncodedString(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: [string],
            options: [.withoutEscapingSlashes]
        ), var encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        encoded.removeFirst()
        encoded.removeLast()
        return encoded
    }
}
