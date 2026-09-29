import Foundation
import Testing
@testable import DotJSON

@MainActor
struct DiffViewModelTests {

    @Test func refreshKeepsComparisonWhenOneSideInvalid() {
        let model = DiffViewModel(
            left: DiffSideBinding(
                source: .inline,
                label: "L",
                inlineText: #"{"a":1}"#,
                applyTarget: .inlineOnly
            ),
            right: DiffSideBinding(
                source: .inline,
                label: "R",
                inlineText: "{",
                applyTarget: .inlineOnly
            )
        )

        model.refresh()

        #expect(model.leftParseError == nil)
        #expect(model.rightParseError != nil)
        #expect(model.comparison == nil)
    }

    @Test func refreshBuildsComparisonWhenBothSidesValid() {
        let model = DiffViewModel(
            left: DiffSideBinding(
                source: .inline,
                label: "L",
                inlineText: #"{"a":1}"#,
                applyTarget: .inlineOnly
            ),
            right: DiffSideBinding(
                source: .inline,
                label: "R",
                inlineText: #"{"a":2}"#,
                applyTarget: .inlineOnly
            )
        )

        model.refresh()

        #expect(model.leftParseError == nil)
        #expect(model.rightParseError == nil)
        #expect(model.comparison?.rows.isEmpty == false)
    }

    @Test func loadFileSetsSideTextToDiskContentsNotFilesystemPath() throws {
        let workspace = WorkspaceViewModel()
        let model = DiffViewModel(
            left: DiffSideBinding(
                source: .inline,
                label: "L",
                inlineText: "{}",
                applyTarget: .inlineOnly
            ),
            right: DiffSideBinding(
                source: .inline,
                label: "R",
                inlineText: "{}",
                applyTarget: .inlineOnly
            )
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("diff-load-subdir")
            .appendingPathComponent("payload.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let diskContents = #"{"loaded":true,"n":2}"#
        try diskContents.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try model.loadFile(url: url, for: .right, workspace: workspace)

        #expect(model.right.inlineText == diskContents)
        #expect(!model.right.inlineText.contains(url.path))
        #expect(!model.right.inlineText.hasPrefix("/"))
    }
}
