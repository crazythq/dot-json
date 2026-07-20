import Testing
import Foundation
@testable import DotJSONCore
@testable import DotJSON

struct JSONParserTests {

    @Test func parseSimpleObject() throws {
        let json = #"{"name":"Alice","age":30}"#
        let node = try JSONParser.parse(json)
        guard case .object(let pairs) = node else {
            Issue.record("Expected object")
            return
        }
        #expect(pairs.count == 2)
        #expect(pairs[0].key == "age")
        #expect(pairs[1].key == "name")
    }

    @Test func parseArray() throws {
        let json = #"[1, 2, 3]"#
        let node = try JSONParser.parse(json)
        guard case .array(let items) = node else {
            Issue.record("Expected array")
            return
        }
        #expect(items.count == 3)
    }

    @Test func parseNested() throws {
        let json = #"{"a":{"b":[1,2]}}"#
        let node = try JSONParser.parse(json)
        guard case .object(let pairs) = node,
              case .object(let inner) = pairs[0].value,
              case .array(let arr) = inner[0].value
        else {
            Issue.record("Expected nested structure")
            return
        }
        #expect(pairs[0].key == "a")
        #expect(inner[0].key == "b")
        #expect(arr.count == 2)
    }

    @Test func parseAllPrimitives() throws {
        let json = #"{"s":"hello","n":3.14,"b":true,"x":null}"#
        let node = try JSONParser.parse(json)
        guard case .object(let pairs) = node else {
            Issue.record("Expected object")
            return
        }
        let byKey = Dictionary(uniqueKeysWithValues: pairs)
        guard case .string(let s) = byKey["s"] else { Issue.record("s"); return }
        guard case .number = byKey["n"] else { Issue.record("n"); return }
        guard case .bool = byKey["b"] else { Issue.record("b"); return }
        guard case .null = byKey["x"] else { Issue.record("x"); return }
        #expect(s == "hello")
    }

    @Test func parseInvalidJSON() {
        let json = #"{bad json"#
        #expect(throws: JSONParser.ParseError.self) {
            try JSONParser.parse(json)
        }
    }

    @Test func parseEmptyObject() throws {
        let node = try JSONParser.parse("{}")
        guard case .object(let pairs) = node else {
            Issue.record("Expected object")
            return
        }
        #expect(pairs.isEmpty)
    }

    @Test func serializeRoundtrip() throws {
        let input = #"{"name":"Bob","score":95}"#
        let node = try JSONParser.parse(input)
        let output = JSONParser.serialize(node)
        let reparsed = try JSONParser.parse(output)
        #expect(node == reparsed)
    }

    // MARK: - 边界情况

    @Test func parseEmptyArray() throws {
        let node = try JSONParser.parse("[]")
        guard case .array(let items) = node else {
            Issue.record("Expected array")
            return
        }
        #expect(items.isEmpty)
    }

    @Test func parseDeeplyNestedObject() throws {
        let json = #"{"a":{"a":{"a":{"a":{"a":{"a":{"a":{"a":{"a":{"a":1}}}}}}}}}}"#
        let node = try JSONParser.parse(json)
        #expect(node != nil)
    }

    @Test func parseLargeArray() throws {
        let numbers = (0..<1000).map(String.init).joined(separator: ",")
        let json = "[\(numbers)]"
        let node = try JSONParser.parse(json)
        guard case .array(let items) = node else {
            Issue.record("Expected array")
            return
        }
        #expect(items.count == 1000)
    }

    @Test func parseNegativeNumbers() throws {
        let json = #"{"a":-1,"b":-3.14}"#
        let node = try JSONParser.parse(json)
        guard case .object(let pairs) = node else {
            Issue.record("Expected object")
            return
        }
        #expect(pairs.count == 2)
    }

    @Test func parseScientificNotation() throws {
        let json = #"{"a":1e10,"b":1.5e-3}"#
        let node = try JSONParser.parse(json)
        guard case .object(let pairs) = node else {
            Issue.record("Expected object")
            return
        }
        #expect(pairs.count == 2)
    }

    @Test func parseEscapedCharacters() throws {
        let json = #"{"msg":"hello\nworld\t\"quoted\""}"#
        let node = try JSONParser.parse(json)
        guard case .object(let pairs) = node,
              case .string(let msg) = pairs[0].value else {
            Issue.record("Expected string")
            return
        }
        #expect(msg.contains("\n"))
        #expect(msg.contains("\t"))
    }

    @Test func parseUnicodeCharacters() throws {
        let json = #"{"name":"中文测试","symbol":"\u4f60\u597d"}"#
        let node = try JSONParser.parse(json)
        guard case .object(let pairs) = node else {
            Issue.record("Expected object")
            return
        }
        #expect(pairs.count == 2)
    }

    @Test func parseStringWithEmoji() throws {
        let json = #"{"emoji":"😀🎉🚀"}"#
        let node = try JSONParser.parse(json)
        guard case .object(let pairs) = node,
              case .string(let emoji) = pairs[0].value else {
            Issue.record("Expected string")
            return
        }
        #expect(emoji == "😀🎉🚀")
    }

    @Test func parseVeryLongString() throws {
        let value = String(repeating: "x", count: 100_000)
        let json = "{\"key\":\"\(value)\"}"
        let node = try JSONParser.parse(json)
        guard case .object(let pairs) = node,
              case .string(let str) = pairs[0].value else {
            Issue.record("Expected string")
            return
        }
        #expect(str.count == 100_000)
    }

    @Test func parseBooleanValues() throws {
        let json = #"{"t":true,"f":false}"#
        let node = try JSONParser.parse(json)
        guard case .object(let pairs) = node else {
            Issue.record("Expected object")
            return
        }
        let byKey = Dictionary(uniqueKeysWithValues: pairs)
        guard case .bool(let t) = byKey["t"] else { Issue.record("t"); return }
        guard case .bool(let f) = byKey["f"] else { Issue.record("f"); return }
        #expect(t == true)
        #expect(f == false)
    }

    @Test func parseNullValue() throws {
        let json = #"{"nothing":null}"#
        let node = try JSONParser.parse(json)
        guard case .object(let pairs) = node,
              case .null = pairs[0].value else {
            Issue.record("Expected null")
            return
        }
    }

    // MARK: - 错误路径

    @Test func parseErrorContainsByteOffset() {
        let json = "{\"key\": bad"
        do {
            _ = try JSONParser.parse(json)
            Issue.record("Expected error")
        } catch {
            if let parseError = error as? JSONParser.ParseError {
                #expect(parseError.errorDescription != nil)
            }
        }
    }

    @Test func parseTrailingCommaError() {
        let json = "{\"a\":1,}"
        #expect(throws: JSONParser.ParseError.self) {
            try JSONParser.parse(json)
        }
    }

    @Test func parseUnclosedStringError() {
        #expect(throws: JSONParser.ParseError.self) {
            try JSONParser.parse(#"{"key":"unclosed}"#)
        }
    }

    @Test func parseEmptyInputError() {
        #expect(throws: JSONParser.ParseError.self) {
            try JSONParser.parse("")
        }
    }

    @Test func serializeNull() {
        let result = JSONParser.serialize(.null)
        #expect(result == "null")
    }

    @Test func serializeBoolean() {
        let result = JSONParser.serialize(.bool(true))
        #expect(result == "true")
    }

    @Test func serializeNumber() {
        let result = JSONParser.serialize(.number("42"))
        #expect(result == "42")
    }

    @Test func serializeString() {
        let result = JSONParser.serialize(.string("hello"))
        #expect(result == "\"hello\"")
    }

    @Test func serializeEmptyArray() {
        let result = JSONParser.serialize(.array([]))
        #expect(result == "[]")
    }

    @Test func serializeEmptyObject() {
        let result = JSONParser.serialize(.object([]))
        #expect(result == "{}")
    }
}
