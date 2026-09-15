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
}
