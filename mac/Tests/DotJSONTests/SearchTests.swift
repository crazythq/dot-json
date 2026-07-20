import Testing
import Foundation
@testable import DotJSON

@MainActor
struct SearchTests {

    @Test func searchFindsKeyMatch() {
        let vm = EditorViewModel()
        vm.rawText = #"{"userName":"Alice","userAge":30}"#
        vm.search("userName")
        #expect(vm.searchMatchCount == 1)
        #expect(vm.searchResults.first?.isKey == true)
    }

    @Test func searchFindsValueMatch() {
        let vm = EditorViewModel()
        vm.rawText = #"{"name":"Alice","city":"Beijing"}"#
        vm.search("Alice")
        #expect(vm.searchMatchCount == 1)
        #expect(vm.searchResults.first?.isKey == false)
    }

    @Test func searchFindsMultipleMatches() {
        let vm = EditorViewModel()
        vm.rawText = #"{"user":{"name":"Alice"},"admin":{"name":"Alice"}}"#
        vm.search("Alice")
        #expect(vm.searchMatchCount == 2)
    }

    @Test func searchEmptyQueryClearsResults() {
        let vm = EditorViewModel()
        vm.rawText = #"{"name":"Alice"}"#
        vm.search("name")
        #expect(vm.searchMatchCount == 1)
        vm.search("")
        #expect(vm.searchMatchCount == 0)
    }

    @Test func searchNoMatchReturnsEmpty() {
        let vm = EditorViewModel()
        vm.rawText = #"{"x":1,"y":2}"#
        vm.search("nonexistent")
        #expect(vm.searchMatchCount == 0)
    }

    @Test func searchIsCaseSensitive() {
        let vm = EditorViewModel()
        vm.rawText = #"{"name":"alice","Name":"bob"}"#
        vm.search("Name")
        #expect(vm.searchMatchCount == 1)
    }

    @Test func searchNavigateCycles() {
        let vm = EditorViewModel()
        vm.rawText = #"{"a":"x","b":"x","c":"x"}"#
        vm.search("x")
        #expect(vm.activeSearchIndex == 0)
        vm.nextSearchResult()
        #expect(vm.activeSearchIndex == 1)
        vm.nextSearchResult()
        #expect(vm.activeSearchIndex == 2)
        vm.nextSearchResult()
        #expect(vm.activeSearchIndex == 0) // wraps around
    }

    @Test func searchPrevWrapsAround() {
        let vm = EditorViewModel()
        vm.rawText = #"{"a":"x","b":"x"}"#
        vm.search("x")
        #expect(vm.activeSearchIndex == 0)
        vm.prevSearchResult()
        #expect(vm.activeSearchIndex == 1) // wraps to last
    }

    @Test func activeSearchResultTracksNavigationAndSourceRange() throws {
        let vm = EditorViewModel()
        vm.rawText = "{\n  \"name\": \"Task\",\n  \"description\": \"Task runner\"\n}"

        vm.search("Task")

        let firstResult = try #require(vm.activeSearchResult)
        #expect(firstResult.lineNumber == 2)
        #expect(firstResult.column == 12)
        #expect(firstResult.range.location == 13)
        #expect(firstResult.range.length == 4)

        vm.nextSearchResult()

        let secondResult = try #require(vm.activeSearchResult)
        #expect(secondResult.lineNumber == 3)
        #expect(secondResult.column == 19)
        #expect(secondResult.range.location == 38)
    }

    @Test func editingTextRefreshesExistingSearchQuery() {
        let vm = EditorViewModel()
        vm.rawText = #"{"name":"Task"}"#
        vm.search("Task")
        #expect(vm.searchMatchCount == 1)

        vm.rawText = #"{"name":"Other"}"#

        #expect(vm.searchMatchCount == 0)
        #expect(vm.activeSearchResult == nil)
    }

    /// 右侧搜索必须直接返回具有稳定节点身份的树结果。
    @Test func treeSearchFindsRepeatedCompactJSONKeysAsDistinctNodes() async {
        let vm = EditorViewModel()
        vm.rawText = #"{"rows":[{"rowIndex":1},{"rowIndex":2}]}"#

        await vm.searchTree("rowIndex")?.value

        #expect(vm.treeSearchMatchCount == 2)
        #expect(Set(vm.treeSearchMatches.map(\.nodeID)).count == 2)
        #expect(vm.activeTreeSearchMatch?.field == .key)
    }

    /// 右侧搜索结果切换应循环，并保持每一条重复结果的独立身份。
    @Test func treeSearchNavigationCyclesDistinctMatches() async throws {
        let vm = EditorViewModel()
        vm.rawText = #"{"first":"same","second":"same"}"#
        await vm.searchTree("same")?.value
        let firstID = try #require(vm.activeTreeSearchMatch?.nodeID)

        vm.nextTreeSearchResult()
        let secondID = try #require(vm.activeTreeSearchMatch?.nodeID)
        vm.nextTreeSearchResult()

        #expect(firstID != secondID)
        #expect(vm.activeTreeSearchMatch?.nodeID == firstID)
    }

    /// 清空右侧查询必须同步清空命中和活动索引。
    @Test func emptyTreeSearchClearsResults() async {
        let vm = EditorViewModel()
        vm.rawText = #"{"name":"Task"}"#
        await vm.searchTree("Task")?.value
        #expect(vm.treeSearchMatchCount == 1)

        vm.searchTree("")

        #expect(vm.treeSearchMatches.isEmpty)
        #expect(vm.activeTreeSearchMatch == nil)
        #expect(vm.treeSearchQuery.isEmpty)
    }

    /// 较早启动的异步查询不得覆盖用户后来输入的查询。
    @Test func staleTreeSearchCannotOverwriteNewerQuery() async {
        let vm = EditorViewModel()
        let rows = (0..<20_000).map { #"{"rowIndex":\#($0),"label":"other"}"# }
        vm.rawText = #"{"rows":[\#(rows.joined(separator: ","))],"needle":"found"}"#

        let staleSearch = vm.searchTree("rowIndex")
        let latestSearch = vm.searchTree("found")
        await latestSearch?.value
        await staleSearch?.value

        #expect(vm.treeSearchQuery == "found")
        #expect(vm.treeSearchMatchCount == 1)
        #expect(vm.activeTreeSearchMatch?.matchedText == "found")
    }
}
