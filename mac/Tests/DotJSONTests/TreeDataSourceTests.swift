import Testing
import Foundation
@testable import DotJSONCore
@testable import DotJSON

struct TreeDataSourceTests {

    @Test func itemCountForRootObject() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"{"a":1,"b":2,"c":3}"#))
        #expect(tree.numberOfChildren(of: nil) == 1)
        let rootItem = tree.child(of: nil, at: 0)!
        #expect(tree.numberOfChildren(of: rootItem) == 3)
    }

    @Test func itemCountForRootArray() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"[1,2,3,4]"#))
        #expect(tree.numberOfChildren(of: nil) == 1)
        let rootItem = tree.child(of: nil, at: 0)!
        #expect(tree.numberOfChildren(of: rootItem) == 4)
    }

    @Test func childAtIndexForObject() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"{"x":100,"y":200}"#))
        let rootItem = tree.child(of: nil, at: 0)!
        guard let child0 = tree.child(of: rootItem, at: 0),
              let child1 = tree.child(of: rootItem, at: 1) else {
            Issue.record("Expected children")
            return
        }
        #expect(child0.key == "x")
        #expect(child1.key == "y")
        #expect(child0.node.summary == "100")
        #expect(child1.node.summary == "200")
    }

    @Test func leafNodesHaveNoChildren() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"{"name":"Alice"}"#))
        let rootItem = tree.child(of: nil, at: 0)!
        let child = tree.child(of: rootItem, at: 0)
        #expect(child != nil)
        #expect(tree.numberOfChildren(of: child) == 0)
    }

    @Test func isExpandableForContainers() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"{"obj":{"inner":1},"arr":[1,2],"str":"x"}"#))
        let rootItem = tree.child(of: nil, at: 0)!
        // Sorted: "arr"(0), "obj"(1), "str"(2)
        guard let arrItem = tree.child(of: rootItem, at: 0),
              let objItem = tree.child(of: rootItem, at: 1),
              let strItem = tree.child(of: rootItem, at: 2) else {
            Issue.record("Expected children")
            return
        }
        #expect(tree.isExpandable(arrItem) == true)
        #expect(tree.isExpandable(objItem) == true)
        #expect(tree.isExpandable(strItem) == false)
    }

    @Test func emptyContainerIsExpandable() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"{"emptyObj":{},"emptyArr":[]}"#))
        let rootItem = tree.child(of: nil, at: 0)!
        let emptyArr = tree.child(of: rootItem, at: 0)! // "emptyArr"(0)
        let emptyObj = tree.child(of: rootItem, at: 1)! // "emptyObj"(1)
        #expect(tree.isExpandable(emptyArr) == true)
        #expect(tree.isExpandable(emptyObj) == true)
    }

    @Test func nestedStructure() throws {
        let tree = JSONTree(root: try JSONParser.parse(
            #"{"users":[{"id":1},{"id":2}]}"#
        ))
        let rootItem = tree.child(of: nil, at: 0)!
        guard let usersItem = tree.child(of: rootItem, at: 0) else {
            Issue.record("Expected users item")
            return
        }
        #expect(usersItem.key == "users")
        #expect(tree.numberOfChildren(of: usersItem) == 2)
        guard let firstUser = tree.child(of: usersItem, at: 0) else {
            Issue.record("Expected first user")
            return
        }
        #expect(firstUser.key == "[0]")
        #expect(tree.numberOfChildren(of: firstUser) == 1)
    }

    @Test func outOfBoundsReturnsNil() throws {
        let tree = JSONTree(root: try JSONParser.parse(#"{"a":1}"#))
        #expect(tree.child(of: nil, at: 99) == nil)
    }
}
