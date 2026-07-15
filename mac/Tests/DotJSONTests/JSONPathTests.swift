import Testing
import Foundation
@testable import DotJSON

struct JSONPathTests {

    @Test func objectChildKey() throws {
        let node = try JSONParser.parse(#"{"name":"Alice","age":30}"#)
        // Sorted keys: "age"(0), "name"(1)
        #expect(node.childPathComponent(at: 0) == ".age")
        #expect(node.childPathComponent(at: 1) == ".name")
    }

    @Test func arrayChildIndex() throws {
        let node = try JSONParser.parse(#"[10,20,30]"#)
        #expect(node.childPathComponent(at: 0) == "[0]")
        #expect(node.childPathComponent(at: 2) == "[2]")
    }

    @Test func nestedObjectChildKey() throws {
        let node = try JSONParser.parse(#"{"user":{"profile":{"age":30}}}"#)
        guard case .object(let root) = node,
              case .object(let user) = root[0].value
        else {
            Issue.record("Expected nested structure")
            return
        }
        // "user" is first key, its value's first key is "profile"
        #expect(user[0].key == "profile")
        #expect(user[0].value.childPathComponent(at: 0) == ".age")
    }

    @Test func leafNodeHasEmptyPathComponent() throws {
        let node = try JSONParser.parse(#""hello""#)
        #expect(node.childPathComponent(at: 0) == "")
    }

    @Test func outOfBoundsReturnsEmpty() throws {
        let node = try JSONParser.parse(#"{"a":1}"#)
        #expect(node.childPathComponent(at: 99) == "")
    }
}
