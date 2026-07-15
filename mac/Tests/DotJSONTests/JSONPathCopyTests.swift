import Testing
import Foundation
@testable import DotJSON

struct JSONPathCopyTests {

    @Test func rootItemPath() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"{"name":"Alice"}"#))
        let rootItem = tree.child(of: nil, at: 0)
        #expect(rootItem?.jsonPath == "$")
    }

    @Test func nestedPropertyPath() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"{"user":{"name":"Alice"}}"#))
        let rootItem = tree.child(of: nil, at: 0)!
        let userItem = tree.child(of: rootItem, at: 0)! // "user"
        let nameItem = tree.child(of: userItem, at: 0)! // "name"
        #expect(nameItem.jsonPath == "$.user.name")
    }

    @Test func arrayElementPath() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"{"items":[10,20]}"#))
        let rootItem = tree.child(of: nil, at: 0)!
        let itemsItem = tree.child(of: rootItem, at: 0)! // "items"
        let elemItem = tree.child(of: itemsItem, at: 0)!  // [0]
        #expect(elemItem.jsonPath == "$.items[0]")
    }

    @Test func rootArrayPath() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"[1,2,3]"#))
        let rootItem = tree.child(of: nil, at: 0)!
        let elemItem = tree.child(of: rootItem, at: 0)!
        #expect(elemItem.jsonPath == "$[0]")
    }

    @Test func deepNestedPath() throws {
        let tree = JSONTree(root: try JSONParser.parse(
            #"{"data":{"users":[{"id":1,"name":"Alice"}]}}"#
        ))
        let rootItem = tree.child(of: nil, at: 0)!
        let dataItem = tree.child(of: rootItem, at: 0)!     // "data"
        let usersItem = tree.child(of: dataItem, at: 0)!     // "users"
        let user0Item = tree.child(of: usersItem, at: 0)!    // [0]
        let nameItem = tree.child(of: user0Item, at: 1)!    // "name" (sorted: id=0, name=1)
        #expect(nameItem.jsonPath == "$.data.users[0].name")
    }
}
