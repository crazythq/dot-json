import Testing
@testable import DotJSONCore

struct JSONDiffTests {

    @Test func detectsAddRemoveAndChange() throws {
        let left = #"{"a":1,"b":2}"#
        let right = #"{"a":1,"b":3,"c":4}"#
        let comparison = try JSONDiff.compare(leftText: left, rightText: right)
        let kinds = Set(comparison.rows.map(\.kind))
        #expect(kinds.contains(.change))
        #expect(comparison.rows.contains { $0.path.description == "b" && $0.kind == .change })
        #expect(comparison.rows.contains { $0.path.description == "c" && $0.kind == .add })
    }

    @Test func arrayUsesIndexPaths() throws {
        let left = #"{"items":[1,2]}"#
        let right = #"{"items":[1,3]}"#
        let comparison = try JSONDiff.compare(leftText: left, rightText: right)
        #expect(comparison.rows.contains { $0.path.description == "items.1" && $0.kind == .change })
    }

    @Test func arrayShrinkIsRemoveAtIndex() throws {
        let left = #"{"items":[1,2,3]}"#
        let right = #"{"items":[9]}"#
        let comparison = try JSONDiff.compare(leftText: left, rightText: right)
        #expect(comparison.rows.contains { $0.path.description == "items.0" && $0.kind == .change })
        #expect(comparison.rows.contains { $0.path.description == "items.1" && $0.kind == .remove })
        #expect(comparison.rows.contains { $0.path.description == "items.2" && $0.kind == .remove })
    }

    @Test func arrayReorderByIndexNotContentMatch() throws {
        let left = #"{"order":["a","b","c"]}"#
        let right = #"{"order":["c","a"]}"#
        let comparison = try JSONDiff.compare(leftText: left, rightText: right)
        #expect(comparison.rows.contains { $0.path.description == "order.0" && $0.kind == .change })
        #expect(comparison.rows.contains { $0.path.description == "order.1" && $0.kind == .change })
        #expect(comparison.rows.contains { $0.path.description == "order.2" && $0.kind == .remove })
    }

    @Test func applySingleRowToLeftAndRight() throws {
        let leftNode = try JSONParser.parse(#"{"x":1}"#)
        let rightNode = try JSONParser.parse(#"{"x":2,"y":3}"#)
        let comparison = JSONDiff.compare(
            left: leftNode,
            right: rightNode,
            leftText: "{}",
            rightText: "{}"
        )
        guard let changeRow = comparison.rows.first(where: { $0.path.description == "x" }),
              let addRow = comparison.rows.first(where: { $0.path.description == "y" }) else {
            Issue.record("Missing expected rows")
            return
        }
        let appliedChange = try JSONDiff.apply(
            row: changeRow,
            direction: .toLeft,
            left: leftNode,
            right: rightNode
        ).left
        #expect(appliedChange.optionalNode(at: try JSONPath.parse("x")) == .number("2"))

        let appliedAdd = try JSONDiff.apply(
            row: addRow,
            direction: .toRight,
            left: leftNode,
            right: rightNode
        ).right
        #expect(appliedAdd.optionalNode(at: try JSONPath.parse("y")) == nil)
    }

    @Test func applyAllToLeft() throws {
        let leftNode = try JSONParser.parse(#"{"a":1,"b":2}"#)
        let rightNode = try JSONParser.parse(#"{"a":9,"c":3}"#)
        let comparison = JSONDiff.compare(
            left: leftNode,
            right: rightNode,
            leftText: "{}",
            rightText: "{}"
        )
        let merged = try JSONDiff.applyAll(
            rows: comparison.rows,
            direction: .toLeft,
            left: leftNode,
            right: rightNode
        ).left
        #expect(merged == rightNode)
    }

    @Test func rejectsIllegalJSON() {
        #expect(throws: JSONDiff.CompareError.self) {
            try JSONDiff.compare(leftText: "{", rightText: "{}")
        }
        #expect(throws: JSONDiff.CompareError.self) {
            try JSONDiff.compare(leftText: "{}", rightText: "not json")
        }
    }

    @Test func softLimitSkipsLineDiff() throws {
        let chunk = String(repeating: "x", count: JSONDiff.softInputByteLimit / 2 + 1)
        let left = #"{"k":"\#(chunk)","v":"a"}"#
        let right = #"{"k":"\#(chunk)","v":"b"}"#
        let comparison = try JSONDiff.compare(leftText: left, rightText: right)
        #expect(comparison.rows.count == 1)
        if case .skipped(let message) = comparison.lineDiff {
            #expect(!message.isEmpty)
        } else {
            Issue.record("Expected skipped line diff")
        }
    }

    @Test func lineLCSDetectsSameAndChangedLines() throws {
        let left = try JSONFormatter.format(#"{"a":1,"b":2}"#, indent: .twoSpaces)
        let right = try JSONFormatter.format(#"{"a":1,"b":3}"#, indent: .twoSpaces)
        let rows = JSONDiff.makeLineDiff(leftPretty: left, rightPretty: right)
        #expect(rows.contains { $0.kind == .same })
        #expect(rows.contains { $0.kind == .changed || $0.kind == .removed })
    }

    @Test func longestCommonSubsequenceBasic() {
        let lcs = JSONDiff.longestCommonSubsequence(["a", "b", "c"], ["a", "c", "d"])
        #expect(lcs == ["a", "c"])
    }
}
