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
}
