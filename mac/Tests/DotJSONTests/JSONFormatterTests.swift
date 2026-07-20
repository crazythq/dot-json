import Testing
import Foundation
@testable import DotJSONCore
@testable import DotJSON

struct JSONFormatterTests {

    @Test func formatSimpleObject() throws {
        let input = #"{"a":1,"b":2}"#
        let result = try JSONFormatter.format(input)
        #expect(result.contains("\n"))
        #expect(result.contains("    "))
        #expect(!result.contains("\t"))
    }

    @Test func formatWithTabIndent() throws {
        let input = #"{"a":1}"#
        let result = try JSONFormatter.format(input, indent: .tab)
        #expect(result.contains("\t"))
    }

    @Test func minifyCompact() throws {
        let input = """
        {
            "a": 1,
            "b": 2
        }
        """
        let result = try JSONFormatter.minify(input)
        #expect(!result.contains("\n"))
        #expect(!result.contains("  "))
    }

    @Test func validateGoodJSON() throws {
        let data = try JSONFormatter.validate(#"{"ok":true}"#)
        #expect(data.count > 0)
    }

    @Test func validateBadJSON() {
        #expect(throws: (any Error).self) {
            try _ = JSONFormatter.validate(#"{bad"#)
        }
    }

    @Test func indentEnumLabels() {
        #expect(JSONFormatter.Indent.twoSpaces.label == "2 spaces")
        #expect(JSONFormatter.Indent.fourSpaces.label == "4 spaces")
        #expect(JSONFormatter.Indent.tab.label == "Tab")
    }

    @Test func formatRoundtrip() throws {
        let input = #"{"name":"test","value":42}"#
        let formatted = try JSONFormatter.format(input)
        let reparsed = try JSONFormatter.validate(formatted)
        #expect(reparsed.count > 0)
    }

    // MARK: - 边界情况

    @Test func formatEmptyObject() throws {
        let result = try JSONFormatter.format("{}")
        #expect(result == "{}")
    }

    @Test func formatEmptyArray() throws {
        let result = try JSONFormatter.format("[]")
        #expect(result == "[]")
    }

    @Test func formatStringValue() throws {
        let result = try JSONFormatter.format(#""hello""#)
        #expect(result.contains("hello"))
    }

    @Test func formatNumberValue() throws {
        let result = try JSONFormatter.format("42")
        #expect(result == "42")
    }

    @Test func formatBooleanValue() throws {
        let result = try JSONFormatter.format("true")
        #expect(result == "true")
    }

    @Test func formatNullValue() throws {
        let result = try JSONFormatter.format("null")
        #expect(result == "null")
    }

    @Test func formatArrayValue() throws {
        let result = try JSONFormatter.format("[1,2,3]")
        #expect(result.contains("\n"))
    }

    @Test func validateEmptyStringThrows() {
        #expect(throws: (any Error).self) {
            try _ = JSONFormatter.validate("")
        }
    }

    @Test func formatNestedObject() throws {
        let input = #"{"a":{"b":{"c":1}}}"#
        let result = try JSONFormatter.format(input)
        let lines = result.components(separatedBy: .newlines)
        #expect(lines.count >= 3)
        #expect(result.contains("\"c\": 1"))
    }

    @Test func formatWithUnicodeCharacters() throws {
        let input = #"{"name":"中文测试","emoji":"😀"}"#
        let result = try JSONFormatter.format(input)
        #expect(result.contains("中文测试"))
        #expect(result.contains("😀"))
    }

    @Test func minifyNestedObject() throws {
        let input = #"{"a":{"b":2}}"#
        let result = try JSONFormatter.minify(input)
        #expect(!result.contains("\n"))
        #expect(!result.contains("  "))
    }

    @Test func minifyArray() throws {
        let result = try JSONFormatter.minify("[1, 2, 3]")
        #expect(result == "[1,2,3]")
    }

    @Test func indentRawValues() {
        #expect(JSONFormatter.Indent.twoSpaces.rawValue == "  ")
        #expect(JSONFormatter.Indent.fourSpaces.rawValue == "    ")
        #expect(JSONFormatter.Indent.tab.rawValue == "\t")
    }

    @Test func validateVeryLongJSON() throws {
        let value = String(repeating: "x", count: 10_000)
        let json = "{\"key\":\"\(value)\"}"
        let data = try JSONFormatter.validate(json)
        #expect(data.count > 10_000)
    }

    @Test func formatVeryLongJSON() throws {
        let value = String(repeating: "x", count: 1_000)
        let json = "{\"key\":\"\(value)\"}"
        let result = try JSONFormatter.format(json)
        #expect(result.contains("\"key\""))
    }

    @Test func formatMixedArray() throws {
        let input = #"["hello",42,true,null]"#
        let result = try JSONFormatter.format(input)
        #expect(result.contains("hello"))
        #expect(result.contains("42"))
        #expect(result.contains("true"))
        #expect(result.contains("null"))
    }

    @Test func formatPreservesSpecialCharacters() throws {
        let input = #"{"url":"https://example.com?a=1&b=2"}"#
        let result = try JSONFormatter.format(input)
        #expect(result.contains("https://example.com?a=1&b=2"))
    }

    @Test func validateValidArray() throws {
        let data = try JSONFormatter.validate("[1,2,3]")
        #expect(data.count > 0)
    }
}
