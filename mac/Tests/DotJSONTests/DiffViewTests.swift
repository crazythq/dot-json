import Foundation
import Testing
@testable import DotJSON

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
    }
}
