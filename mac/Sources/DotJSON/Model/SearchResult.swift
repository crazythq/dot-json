import Foundation

struct SearchResult: Identifiable, Equatable {
    let id = UUID()
    let lineNumber: Int
    let column: Int
    let matchedText: String
    let isKey: Bool
    let range: NSRange

    /// 保存一次搜索命中在原文中的显示位置和 `NSTextView` 可用的 UTF-16 范围。
    ///
    /// - Parameters:
    ///   - lineNumber: 从 1 开始的行号。
    ///   - column: 从 1 开始的列号。
    ///   - matchedText: 命中的原始查询文本。
    ///   - isKey: 命中是否位于 JSON key 区域。
    ///   - range: 命中在完整原文 UTF-16 坐标系中的范围。
    init(
        lineNumber: Int,
        column: Int,
        matchedText: String,
        isKey: Bool,
        range: NSRange = NSRange(location: 0, length: 0)
    ) {
        self.lineNumber = lineNumber
        self.column = column
        self.matchedText = matchedText
        self.isKey = isKey
        self.range = range
    }

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.lineNumber == rhs.lineNumber
            && lhs.column == rhs.column
            && lhs.matchedText == rhs.matchedText
            && lhs.isKey == rhs.isKey
            && NSEqualRanges(lhs.range, rhs.range)
    }
}
