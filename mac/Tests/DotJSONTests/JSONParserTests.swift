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
}
