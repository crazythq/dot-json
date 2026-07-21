import Foundation

/// 补足 Foundation JSON 解析器在不同系统版本上的严格语法差异。
///
/// 当前只检测标准 JSON 明确禁止、但部分 Foundation 版本会宽松接受的尾逗号。
enum StrictJSONSyntax {
    /// 查找字符串之外、闭合对象或数组之前的尾逗号。
    ///
    /// - Parameter text: 待检查的完整 JSON 文本。
    /// - Returns: 首个尾逗号在 UTF-8 文本中的字节偏移；不存在时返回 `nil`。
    static func trailingCommaByteOffset(in text: String) -> Int? {
        var index = text.startIndex
        var isInsideString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]

            if isInsideString {
                if isEscaped {
                    // 被转义字符不参与字符串边界判断，下一字符恢复普通字符串扫描。
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == ",",
                      let next = nextNonWhitespace(in: text, after: index),
                      next == "}" || next == "]" {
                return text[..<index].utf8.count
            }

            index = text.index(after: index)
        }

        return nil
    }

    /// 查找指定位置之后的下一个非空白字符。
    ///
    /// - Parameters:
    ///   - text: 正在扫描的 JSON 文本。
    ///   - index: 当前字符位置。
    /// - Returns: 下一个非空白字符；到达文本末尾时返回 `nil`。
    private static func nextNonWhitespace(in text: String, after index: String.Index) -> Character? {
        var cursor = text.index(after: index)
        while cursor < text.endIndex {
            if !text[cursor].isWhitespace {
                return text[cursor]
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }
}
