import Foundation

/// 把 Python `dict/list` 文本的确定性子集转换为标准 JSON。
enum PythonLiteralRepairer {
    /// 扫描并转换单引号、Python 常量和尾逗号。
    ///
    /// - Parameter input: 已抽取且顶层应为对象或数组的候选文本。
    /// - Returns: 保留空白布局的标准 JSON 候选。
    /// - Throws: 遇到未知标识符、非法转义或截断字符串时抛出修复错误。
    static func repair(_ input: String) throws(JSONRepairer.RepairError) -> String {
        guard let first = input.first(where: { !$0.isWhitespace }), first == "{" || first == "[" else {
            throw error("Python repair requires a top-level dict or list.")
        }

        var output = ""
        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            if character == "'" {
                let decoded = try decodeSingleQuotedString(in: input, index: &index)
                output += try encodeJSONString(decoded)
                continue
            }
            if character == "\"" {
                output += try copyDoubleQuotedString(in: input, index: &index)
                continue
            }
            if character.isLetter || character == "_" {
                output += try convertIdentifier(in: input, index: &index)
                continue
            }
            if character == ",", nextNonWhitespace(in: input, after: index).map({ $0 == "}" || $0 == "]" }) == true {
                // 只在结构层删除闭合括号前的逗号；随后空白由普通分支原样保留。
                index = input.index(after: index)
                continue
            }
            output.append(character)
            index = input.index(after: index)
        }
        return output
    }

    /// 复制已有 JSON 双引号字符串，防止误改字符串内部 token。
    private static func copyDoubleQuotedString(
        in input: String,
        index: inout String.Index
    ) throws(JSONRepairer.RepairError) -> String {
        let start = index
        index = input.index(after: index)
        var escaped = false
        while index < input.endIndex {
            let character = input[index]
            index = input.index(after: index)
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return String(input[start..<index])
            }
        }
        throw error("Unterminated double-quoted string.", input: input, at: start)
    }

    /// 解码一个 Python 单引号字符串并推进扫描位置。
    private static func decodeSingleQuotedString(
        in input: String,
        index: inout String.Index
    ) throws(JSONRepairer.RepairError) -> String {
        let start = index
        index = input.index(after: index)
        var decoded = ""

        while index < input.endIndex {
            let character = input[index]
            index = input.index(after: index)
            if character == "'" { return decoded }
            if character == "\n" || character == "\r" {
                throw error("Python single-quoted strings cannot contain raw newlines.", input: input, at: start)
            }
            guard character == "\\" else {
                decoded.append(character)
                continue
            }
            guard index < input.endIndex else {
                throw error("Incomplete Python string escape.", input: input, at: start)
            }
            let escape = input[index]
            index = input.index(after: index)
            switch escape {
            case "\\": decoded.append("\\")
            case "'": decoded.append("'")
            case "\"": decoded.append("\"")
            case "n": decoded.append("\n")
            case "r": decoded.append("\r")
            case "t": decoded.append("\t")
            case "b": decoded.append("\u{08}")
            case "f": decoded.append("\u{0C}")
            case "x": decoded.unicodeScalars.append(try readScalar(in: input, index: &index, digits: 2))
            case "u": decoded.unicodeScalars.append(try readScalar(in: input, index: &index, digits: 4))
            case "U": decoded.unicodeScalars.append(try readScalar(in: input, index: &index, digits: 8))
            default:
                throw error("Unsupported Python string escape: \\(escape).", input: input, at: start)
            }
        }
        throw error("Unterminated single-quoted string.", input: input, at: start)
    }

    /// 读取固定长度十六进制 Unicode 标量。
    private static func readScalar(
        in input: String,
        index: inout String.Index,
        digits: Int
    ) throws(JSONRepairer.RepairError) -> Unicode.Scalar {
        var value: UInt32 = 0
        for _ in 0..<digits {
            guard index < input.endIndex, let digit = input[index].hexDigitValue else {
                throw error("Incomplete hexadecimal Python string escape.", input: input, at: index)
            }
            value = value * 16 + UInt32(digit)
            index = input.index(after: index)
        }
        guard !(0xD800...0xDFFF).contains(value), let scalar = Unicode.Scalar(value) else {
            throw error("Invalid Unicode scalar in Python string escape.", input: input, at: index)
        }
        return scalar
    }

    /// 转换结构层的完整 Python 标识符 token。
    private static func convertIdentifier(
        in input: String,
        index: inout String.Index
    ) throws(JSONRepairer.RepairError) -> String {
        let start = index
        while index < input.endIndex, input[index].isLetter || input[index].isNumber || input[index] == "_" {
            index = input.index(after: index)
        }
        let token = String(input[start..<index])
        switch token {
        case "True": return "true"
        case "False": return "false"
        case "None": return "null"
        default:
            throw error("Unsupported Python token: \(token).", input: input, at: start)
        }
    }

    /// 查找逗号之后的下一个非空白字符。
    private static func nextNonWhitespace(in input: String, after index: String.Index) -> Character? {
        var cursor = input.index(after: index)
        while cursor < input.endIndex {
            if !input[cursor].isWhitespace { return input[cursor] }
            cursor = input.index(after: cursor)
        }
        return nil
    }

    /// 通过 Foundation 安全生成一个 JSON 双引号字符串。
    private static func encodeJSONString(_ value: String) throws(JSONRepairer.RepairError) -> String {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: [value],
                options: [.withoutEscapingSlashes]
            )
            guard var encoded = String(data: data, encoding: .utf8) else {
                throw error("Unable to encode repaired Python string.")
            }
            encoded.removeFirst()
            encoded.removeLast()
            return encoded
        } catch let repairError as JSONRepairer.RepairError {
            throw repairError
        } catch {
            throw Self.error("Unable to encode repaired Python string.")
        }
    }

    /// 创建可选定位的“不支持语法”错误。
    private static func error(
        _ message: String,
        input: String? = nil,
        at index: String.Index? = nil
    ) -> JSONRepairer.RepairError {
        let offset: Int?
        if let input, let index {
            offset = input[..<index].utf8.count
        } else {
            offset = nil
        }
        return JSONRepairer.RepairError(
            kind: .unsupportedSyntax,
            message: message,
            byteOffset: offset
        )
    }
}
