import Foundation
import Testing
@testable import DotJSON

struct FileAssociationLogicTests {
    private let selfApp = URL(fileURLWithPath: "/Applications/DotJSON.app")
    private let otherApp = URL(fileURLWithPath: "/Applications/Other.app")
    private let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    @Test func toggleOnRequiresBothExtensions() {
        let both = FileAssociationLogic.toggleState(
            jsonDefault: selfApp,
            jsonlDefault: selfApp,
            selfAppURL: selfApp
        )
        #expect(both.isFullyOn)

        let jsonOnly = FileAssociationLogic.toggleState(
            jsonDefault: selfApp,
            jsonlDefault: otherApp,
            selfAppURL: selfApp
        )
        #expect(!jsonOnly.isFullyOn)
    }

    @Test func shouldNotPersistPriorWhenAlreadyFullyOn() {
        let state = FileAssociationToggleState(
            isDotJSONDefaultForJSON: true,
            isDotJSONDefaultForJSONL: true
        )
        #expect(!FileAssociationLogic.shouldPersistPriorWhenEnabling(state: state))
    }

    @Test func priorSnapshotSkipsExtensionsAlreadySelf() {
        let prior = FileAssociationLogic.priorToPersistWhenEnabling(
            jsonDefault: selfApp,
            jsonlDefault: otherApp,
            selfAppURL: selfApp
        )
        #expect(prior.jsonAppURL == nil)
        #expect(prior.jsonlAppURL == otherApp)
    }

    @Test func rollbackOrderIsJsonlThenJson() {
        let prior = PriorHandlerSnapshot(jsonAppURL: otherApp, jsonlAppURL: textEdit)
        let targets = FileAssociationLogic.rollbackTargetsAfterPartialEnable(
            succeeded: [.json, .jsonl],
            prior: prior
        )
        #expect(targets.map(\.0) == [.jsonl, .json])
    }

    @Test func rollbackIncludesNilPriorForSucceededExtension() {
        let prior = PriorHandlerSnapshot(jsonAppURL: otherApp, jsonlAppURL: nil)
        let targets = FileAssociationLogic.rollbackTargetsAfterPartialEnable(
            changedToSelf: [.jsonl],
            prior: prior
        )
        #expect(targets.count == 1)
        #expect(targets[0].0 == .jsonl)
        #expect(targets[0].1 == nil)
    }

    @Test func rollbackSkipsExtensionsAlreadySelfBeforeEnable() {
        let prior = PriorHandlerSnapshot(jsonAppURL: otherApp, jsonlAppURL: otherApp)
        let targets = FileAssociationLogic.rollbackTargetsAfterPartialEnable(
            changedToSelf: [.jsonl],
            prior: prior
        )
        #expect(targets.map(\.0) == [.jsonl])
    }

    @Test func restoreMissingPriorOffersReset() {
        let action = FileAssociationLogic.restoreAction(
            for: .json,
            prior: PriorHandlerSnapshot(),
            priorAppExists: { _ in true }
        )
        #expect(action == .resetToSystemFallback)
    }

    @Test func restoreUninstalledPriorOffersReset() {
        let action = FileAssociationLogic.restoreAction(
            for: .json,
            prior: PriorHandlerSnapshot(jsonAppURL: otherApp, jsonlAppURL: nil),
            priorAppExists: { _ in false }
        )
        #expect(action == .resetToSystemFallback)
    }

    @Test func systemFallbackPrefersNonSelfWorkspaceCandidate() {
        let fallback = FileAssociationLogic.systemFallbackApp(
            for: .json,
            workspaceCandidate: otherApp,
            selfAppURL: selfApp
        )
        #expect(fallback == otherApp)
    }

    @Test func systemFallbackUsesTextEditWhenCandidateIsSelf() {
        let fallback = FileAssociationLogic.systemFallbackApp(
            for: .json,
            workspaceCandidate: selfApp,
            selfAppURL: selfApp
        )
        #expect(fallback == textEdit)
    }
}
