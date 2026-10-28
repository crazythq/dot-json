import Foundation
import Testing
@testable import DotJSON

@MainActor
private final class MockDefaultApplicationWorkspace: DefaultApplicationWorkspace {
    var defaults: [ManagedJSONExtension: URL] = [:]
    private(set) var setCalls: [(URL, ManagedJSONExtension)] = []
    var failSetFor: Set<ManagedJSONExtension> = []
    var workspaceCandidateURL: URL?

    func defaultApplicationURL(for ext: ManagedJSONExtension) -> URL? {
        defaults[ext]
    }

    func workspaceCandidate(for ext: ManagedJSONExtension) -> URL? {
        workspaceCandidateURL
    }

    func setDefaultApplication(at appURL: URL, for ext: ManagedJSONExtension) async throws {
        if failSetFor.contains(ext) {
            throw DefaultApplicationWorkspaceError.setFailed(underlyingDescription: "mock failure")
        }
        setCalls.append((appURL, ext))
        defaults[ext] = appURL
    }
}

@MainActor
struct FileAssociationCoordinatorTests {
    private let selfApp = URL(fileURLWithPath: "/Applications/DotJSON.app")
    private let vscode = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
    private let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    private func makeCoordinator(
        workspace: MockDefaultApplicationWorkspace,
        priorStore: PriorHandlerStore
    ) -> FileAssociationCoordinator {
        FileAssociationCoordinator(
            workspace: workspace,
            priorStore: priorStore,
            selfAppURL: selfApp,
            fileManager: .default
        )
    }

    @Test func enableSkipsPriorOverwriteWhenAlreadyDefault() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = selfApp
        workspace.defaults[.jsonl] = selfApp
        let suite = "FileAssociationCoordinatorTests.alreadyOn"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        let kept = URL(fileURLWithPath: "/Applications/Kept.app")
        store.save(PriorHandlerSnapshot(jsonAppURL: kept, jsonlAppURL: kept))
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        _ = await coordinator.enableDotJSONAsDefault()
        #expect(store.load().jsonAppURL == kept)
    }

    @Test func enablePersistsPriorAndSetsBoth() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = vscode
        workspace.defaults[.jsonl] = vscode
        let suite = "FileAssociationCoordinatorTests.enable"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        let outcome = await coordinator.enableDotJSONAsDefault()
        #expect(outcome == .success)
        #expect(workspace.defaults[.json] == selfApp)
        #expect(workspace.defaults[.jsonl] == selfApp)
        #expect(store.load().jsonAppURL == vscode)
        #expect(store.load().jsonlAppURL == vscode)
    }

    @Test func enableJsonlFailureKeepsJsonWhenJsonAlreadySelf() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = selfApp
        workspace.defaults[.jsonl] = vscode
        workspace.failSetFor = [.jsonl]
        let suite = "FileAssociationCoordinatorTests.halfOpenAlreadySelf"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        store.save(PriorHandlerSnapshot(jsonAppURL: vscode, jsonlAppURL: vscode))
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        let outcome = await coordinator.enableDotJSONAsDefault()
        #expect(outcome == .failure(partialRollbackFailed: false))
        #expect(workspace.defaults[.json] == selfApp)
        #expect(workspace.defaults[.jsonl] == vscode)
        #expect(!workspace.setCalls.contains { $0.1 == .json })
    }

    @Test func enableJsonlFailureRollsBackJson() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = vscode
        workspace.defaults[.jsonl] = vscode
        workspace.failSetFor = [.jsonl]
        let suite = "FileAssociationCoordinatorTests.rollback"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        store.save(PriorHandlerSnapshot(jsonAppURL: vscode, jsonlAppURL: vscode))
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        let outcome = await coordinator.enableDotJSONAsDefault()
        #expect(outcome == .failure(partialRollbackFailed: false))
        #expect(workspace.defaults[.json] == vscode)
        #expect(workspace.setCalls.contains { $0.0 == vscode && $0.1 == .json })
    }

    @Test func disableRestoreSuccess() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = selfApp
        workspace.defaults[.jsonl] = selfApp
        let suite = "FileAssociationCoordinatorTests.disable"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        store.save(PriorHandlerSnapshot(jsonAppURL: vscode, jsonlAppURL: vscode))
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        let outcome = await coordinator.disableDotJSONAsDefault()
        #expect(outcome == .success)
        #expect(workspace.defaults[.json] == vscode)
        #expect(workspace.defaults[.jsonl] == vscode)
    }

    @Test func disablePartialRestoreWhenOneSideRestored() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = selfApp
        workspace.defaults[.jsonl] = selfApp
        let suite = "FileAssociationCoordinatorTests.partialDisable"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        store.save(PriorHandlerSnapshot(jsonAppURL: vscode, jsonlAppURL: nil))
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        let outcome = await coordinator.disableDotJSONAsDefault()
        #expect(outcome == .partialRestore(extensionsStillDotJSON: [.jsonl]))
        #expect(workspace.defaults[.json] == vscode)
        #expect(workspace.defaults[.jsonl] == selfApp)
    }

    @Test func resetOnlyTouchesExtensionsStillOnDotJSON() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = vscode
        workspace.defaults[.jsonl] = selfApp
        workspace.workspaceCandidateURL = textEdit
        let suite = "FileAssociationCoordinatorTests.resetPartial"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        let outcome = await coordinator.resetToMacOSDefaults()
        #expect(outcome == .success)
        #expect(workspace.defaults[.json] == vscode)
        #expect(workspace.defaults[.jsonl] == textEdit)
    }

    @Test func disableMissingPriorReturnsRestoreFailed() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = selfApp
        workspace.defaults[.jsonl] = selfApp
        let suite = "FileAssociationCoordinatorTests.missingPrior"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        let outcome = await coordinator.disableDotJSONAsDefault()
        #expect(outcome == .restoreFailed)
    }

    @Test func resetUsesNonSelfCandidate() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = selfApp
        workspace.defaults[.jsonl] = selfApp
        workspace.workspaceCandidateURL = textEdit
        let suite = "FileAssociationCoordinatorTests.reset"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        let outcome = await coordinator.resetToMacOSDefaults()
        #expect(outcome == .success)
        #expect(workspace.defaults[.json] == textEdit)
        #expect(store.load().jsonAppURL == nil)
    }
}
