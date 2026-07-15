import Testing
import Foundation
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
}
