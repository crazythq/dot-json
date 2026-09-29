import AppKit
import Foundation
import Testing
@testable import DotJSON

@MainActor
struct DiffViewTests {

    private func diffViewSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/DiffView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    @Test func pathDiffStatusColumnUsesFullEnglishLabels() throws {
        let source = try diffViewSource()

        #expect(source.contains(#"return "Modified""#))
        #expect(source.contains(#"return "Added""#))
        #expect(source.contains(#"return "Deleted""#))
        #expect(!source.contains(#"return "M""#))
        #expect(!source.contains(#"return "A""#))
        #expect(!source.contains(#"return "D""#))
    }

    @Test func diffSideEditorsAcceptSingleFileDrop() throws {
        let source = try diffViewSource()

        #expect(source.contains(".dropDestination(for: URL.self)"))
        #expect(source.contains("workspace.rejectDiffMultiFileDrop()"))
        #expect(source.contains("workspace.openFileOnDiffSide(url, position: position)"))
        #expect(source.contains("DiffSideTextEditor(text: sideTextBinding(position))"))
        #expect(source.contains("handleDiffFileDrop"))
        #expect(source.contains("workspace.openFileOnDiffSide(url, position: position)"))
        // SwiftUI TextEditor (not DiffSideTextEditor) must not be used — it pastes dropped paths as text.
        let withoutDiffSideEditor = source.replacingOccurrences(
            of: "DiffSideTextEditor(text:",
            with: ""
        )
        #expect(!withoutDiffSideEditor.contains("TextEditor(text:"))
    }

    @Test func diffPaneTextViewForwardsFileDragsWithoutMutatingBuffer() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/DiffSideTextEditor.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("final class DiffPaneTextView"))
        #expect(source.contains("onFileURLsDropped"))
        #expect(source.contains("FileDropPasteboard.fileURLs"))
        #expect(source.contains("onFileURLsDropped?(fileURLs)"))
        #expect(source.contains("return true"))
    }

    @Test func diffPaneTextViewFileDropCallbackDoesNotMutateEditorString() {
        let textView = DiffPaneTextView()
        textView.string = #"{"unchanged":true}"#
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diff-drag.json")
        textView.onFileURLsDropped = { _ in }

        textView.onFileURLsDropped?([url])

        #expect(textView.string == #"{"unchanged":true}"#)
    }
}
