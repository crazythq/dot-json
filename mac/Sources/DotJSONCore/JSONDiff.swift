import Foundation

/// 结构化 JSON 对比、路径级合并与文本行 LCS。
public enum JSONDiff {
    /// 合并输入超过该字节数时跳过行级 Diff。
    public static let softInputByteLimit = 2_000_000

    public enum Kind: String, Sendable, Equatable {
        case add
        case remove
        case change
    }

    public enum ApplyDirection: Sendable, Equatable {
        case toLeft
        case toRight
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public var id: String { path.description + kind.rawValue }
        public let kind: Kind
        public let path: JSONPath
        public let leftValue: JSONNode?
        public let rightValue: JSONNode?

        public init(kind: Kind, path: JSONPath, leftValue: JSONNode?, rightValue: JSONNode?) {
            self.kind = kind
            self.path = path
            self.leftValue = leftValue
            self.rightValue = rightValue
        }
    }

    public enum CompareError: Error, Sendable {
        case leftInvalid(JSONParser.ParseError)
        case rightInvalid(JSONParser.ParseError)
    }

    public enum LineKind: Sendable, Equatable {
        case same
        case removed
        case added
        case changed
    }

    public struct LineRow: Sendable, Equatable {
        public let kind: LineKind
        public let leftLine: String?
        public let rightLine: String?

        public init(kind: LineKind, leftLine: String?, rightLine: String?) {
            self.kind = kind
            self.leftLine = leftLine
            self.rightLine = rightLine
        }
    }

    public enum LineDiff: Sendable, Equatable {
        case available([LineRow])
        case skipped(message: String)
    }

    public struct Comparison: Sendable, Equatable {
        public let rows: [Row]
        public let lineDiff: LineDiff
        public let leftPretty: String
        public let rightPretty: String
        public let leftRoot: JSONNode
        public let rightRoot: JSONNode

        public init(
            rows: [Row],
            lineDiff: LineDiff,
            leftPretty: String,
            rightPretty: String,
            leftRoot: JSONNode,
            rightRoot: JSONNode
        ) {
            self.rows = rows
            self.lineDiff = lineDiff
            self.leftPretty = leftPretty
            self.rightPretty = rightPretty
            self.leftRoot = leftRoot
            self.rightRoot = rightRoot
        }
    }

    // MARK: - Compare

    /// 对比两侧 JSON 文本；非法 JSON 抛出错误，不返回空 Diff。
    public static func compare(
        leftText: String,
        rightText: String,
        indent: JSONFormatter.Indent = .fourSpaces
    ) throws -> Comparison {
        let leftRoot: JSONNode
        let rightRoot: JSONNode
        do {
            leftRoot = try JSONParser.parse(leftText)
        } catch {
            throw CompareError.leftInvalid(error)
        }
        do {
            rightRoot = try JSONParser.parse(rightText)
        } catch {
            throw CompareError.rightInvalid(error)
        }
        return compare(left: leftRoot, right: rightRoot, leftText: leftText, rightText: rightText, indent: indent)
    }

    /// 对比两棵已解析树。
    public static func compare(
        left: JSONNode,
        right: JSONNode,
        leftText: String,
        rightText: String,
        indent: JSONFormatter.Indent = .fourSpaces
    ) -> Comparison {
        let rows = structuredDiff(left: left, right: right, path: JSONPath())
        let leftPretty = (try? JSONFormatter.format(left, indent: indent)) ?? JSONParser.serialize(left)
        let rightPretty = (try? JSONFormatter.format(right, indent: indent)) ?? JSONParser.serialize(right)
        let combinedSize = leftText.utf8.count + rightText.utf8.count
        let lineDiff: LineDiff
        if combinedSize > softInputByteLimit {
            lineDiff = .skipped(message: "Combined input exceeds 2 MB; line diff omitted.")
        } else {
            lineDiff = .available(lineDiff(leftPretty: leftPretty, rightPretty: rightPretty))
        }
        return Comparison(
            rows: rows,
            lineDiff: lineDiff,
            leftPretty: leftPretty,
            rightPretty: rightPretty,
            leftRoot: left,
            rightRoot: right
        )
    }

    // MARK: - Apply

    /// 将单条结构化 Diff 应用到指定侧。
    ///
    /// `add` 表示仅右侧存在的路径：`toLeft` 把 `rightValue` 写入左侧；`toRight` 从右侧删除该路径（拒绝新增）。
    /// `remove` 表示仅左侧存在：`toLeft` 从左侧删除；`toRight` 把 `leftValue` 写入右侧。
    /// `change`：`toLeft` 用 `rightValue` 覆盖左侧；`toRight` 用 `leftValue` 覆盖右侧。
    public static func apply(
        row: Row,
        direction: ApplyDirection,
        left: JSONNode,
        right: JSONNode
    ) throws -> (left: JSONNode, right: JSONNode) {
        switch direction {
        case .toLeft:
            return (try applyRowToTarget(row: row, targetIsLeft: true, left: left, right: right), right)
        case .toRight:
            return (left, try applyRowToTarget(row: row, targetIsLeft: false, left: left, right: right))
        }
    }

    /// 批量按方向应用多条 Diff；路径按深度从深到浅排序，数组下标从大到小。
    public static func applyAll(
        rows: [Row],
        direction: ApplyDirection,
        left: JSONNode,
        right: JSONNode
    ) throws -> (left: JSONNode, right: JSONNode) {
        let ordered = sortRowsForApply(rows)
        var currentLeft = left
        var currentRight = right
        for row in ordered {
            let result = try apply(row: row, direction: direction, left: currentLeft, right: currentRight)
            currentLeft = result.left
            currentRight = result.right
        }
        return (currentLeft, currentRight)
    }

    // MARK: - Structured diff

    private static func structuredDiff(left: JSONNode, right: JSONNode, path: JSONPath) -> [Row] {
        if left == right { return [] }

        switch (left, right) {
        case (.object(let leftPairs), .object(let rightPairs)):
            var rows: [Row] = []
            let leftKeys = Dictionary(uniqueKeysWithValues: leftPairs.map { ($0.key, $0.value) })
            let rightKeys = Dictionary(uniqueKeysWithValues: rightPairs.map { ($0.key, $0.value) })
            let allKeys = Set(leftKeys.keys).union(rightKeys.keys).sorted()
            for key in allKeys {
                let childPath = path.appending(.key(key))
                switch (leftKeys[key], rightKeys[key]) {
                case (nil, let rightValue?):
                    rows.append(Row(kind: .add, path: childPath, leftValue: nil, rightValue: rightValue))
                case (let leftValue?, nil):
                    rows.append(Row(kind: .remove, path: childPath, leftValue: leftValue, rightValue: nil))
                case (let leftValue?, let rightValue?):
                    rows.append(contentsOf: structuredDiff(left: leftValue, right: rightValue, path: childPath))
                case (nil, nil):
                    break
                }
            }
            return rows
        case (.array(let leftItems), .array(let rightItems)):
            var rows: [Row] = []
            let maxCount = max(leftItems.count, rightItems.count)
            for index in 0..<maxCount {
                let childPath = path.appending(.index(index))
                let leftItem = leftItems.indices.contains(index) ? leftItems[index] : nil
                let rightItem = rightItems.indices.contains(index) ? rightItems[index] : nil
                switch (leftItem, rightItem) {
                case (nil, let rightValue?):
                    rows.append(Row(kind: .add, path: childPath, leftValue: nil, rightValue: rightValue))
                case (let leftValue?, nil):
                    rows.append(Row(kind: .remove, path: childPath, leftValue: leftValue, rightValue: nil))
                case (let leftValue?, let rightValue?):
                    rows.append(contentsOf: structuredDiff(left: leftValue, right: rightValue, path: childPath))
                case (nil, nil):
                    break
                }
            }
            return rows
        default:
            return [Row(kind: .change, path: path, leftValue: left, rightValue: right)]
        }
    }

    private static func applyRowToTarget(
        row: Row,
        targetIsLeft: Bool,
        left: JSONNode,
        right: JSONNode
    ) throws -> JSONNode {
        let targetRoot = targetIsLeft ? left : right
        switch row.kind {
        case .add:
            if targetIsLeft {
                guard let value = row.rightValue else { return targetRoot }
                return try targetRoot.setting(value, at: row.path)
            }
            return try targetRoot.removing(at: row.path)
        case .remove:
            if targetIsLeft {
                return try targetRoot.removing(at: row.path)
            }
            guard let value = row.leftValue else { return targetRoot }
            return try targetRoot.setting(value, at: row.path)
        case .change:
            if targetIsLeft {
                guard let value = row.rightValue else { return targetRoot }
                return try targetRoot.setting(value, at: row.path)
            }
            guard let value = row.leftValue else { return targetRoot }
            return try targetRoot.setting(value, at: row.path)
        }
    }

    private static func sortRowsForApply(_ rows: [Row]) -> [Row] {
        rows.sorted { lhs, rhs in
            let leftDepth = lhs.path.components.count
            let rightDepth = rhs.path.components.count
            if leftDepth != rightDepth { return leftDepth > rightDepth }
            return lhs.path.description > rhs.path.description
        }
    }

    // MARK: - Line LCS

    /// 对两段已格式化的文本做行级 LCS Diff。
    public static func lineDiff(leftPretty: String, rightPretty: String) -> [LineRow] {
        let leftLines = leftPretty.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let rightLines = rightPretty.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let leftCount = leftLines.count
        let rightCount = rightLines.count
        var lengths = Array(repeating: Array(repeating: 0, count: rightCount + 1), count: leftCount + 1)
        for i in 1...leftCount {
            for j in 1...rightCount {
                if leftLines[i - 1] == rightLines[j - 1] {
                    lengths[i][j] = lengths[i - 1][j - 1] + 1
                } else {
                    lengths[i][j] = max(lengths[i - 1][j], lengths[i][j - 1])
                }
            }
        }
        enum Step {
            case same(String)
            case removed(String)
            case added(String)
        }
        var steps: [Step] = []
        var i = leftCount
        var j = rightCount
        while i > 0 || j > 0 {
            if i > 0, j > 0, leftLines[i - 1] == rightLines[j - 1] {
                steps.append(.same(leftLines[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0, i == 0 || lengths[i][j - 1] >= lengths[i - 1][j] {
                steps.append(.added(rightLines[j - 1]))
                j -= 1
            } else if i > 0 {
                steps.append(.removed(leftLines[i - 1]))
                i -= 1
            }
        }
        steps.reverse()
        var rows: [LineRow] = []
        var stepIndex = steps.startIndex
        while stepIndex < steps.endIndex {
            switch steps[stepIndex] {
            case .same(let line):
                rows.append(LineRow(kind: .same, leftLine: line, rightLine: line))
                stepIndex = steps.index(after: stepIndex)
            case .removed(let leftLine):
                let next = steps.index(after: stepIndex)
                if next < steps.endIndex, case .added(let rightLine) = steps[next] {
                    rows.append(LineRow(kind: .changed, leftLine: leftLine, rightLine: rightLine))
                    stepIndex = steps.index(after: next)
                } else {
                    rows.append(LineRow(kind: .removed, leftLine: leftLine, rightLine: nil))
                    stepIndex = next
                }
            case .added(let rightLine):
                rows.append(LineRow(kind: .added, leftLine: nil, rightLine: rightLine))
                stepIndex = steps.index(after: stepIndex)
            }
        }
        return rows
    }

    /// 最长公共子序列（行数组元素为 `Equatable`）。
    public static func longestCommonSubsequence<T: Equatable>(_ left: [T], _ right: [T]) -> [T] {
        let leftCount = left.count
        let rightCount = right.count
        if leftCount == 0 || rightCount == 0 { return [] }
        var lengths = Array(repeating: Array(repeating: 0, count: rightCount + 1), count: leftCount + 1)
        for i in 1...leftCount {
            for j in 1...rightCount {
                if left[i - 1] == right[j - 1] {
                    lengths[i][j] = lengths[i - 1][j - 1] + 1
                } else {
                    lengths[i][j] = max(lengths[i - 1][j], lengths[i][j - 1])
                }
            }
        }
        var result: [T] = []
        var i = leftCount
        var j = rightCount
        while i > 0, j > 0 {
            if left[i - 1] == right[j - 1] {
                result.append(left[i - 1])
                i -= 1
                j -= 1
            } else if lengths[i - 1][j] >= lengths[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }

    /// 输入字节数是否超过软限制。
    public static func exceedsSoftLimit(leftText: String, rightText: String) -> Bool {
        leftText.utf8.count + rightText.utf8.count > softInputByteLimit
    }
}
