import Foundation
import Testing
@testable import DotJSON

@MainActor
private final class MockDefaultApplicationWorkspace: DefaultApplicationWorkspace {
    var defaults: [ManagedJSONExtension: URL] = [:]
    private(set) var setCalls: [(URL, ManagedJSONExtension)] = []
    var failSetFor: Set<ManagedJSONExtension> = []
    var hardFailSetFor: Set<ManagedJSONExtension> = []
    /// Hard-fail budget per extension (default 1 when in `hardFailSetFor`). Rollback uses the same API.
    var hardFailBudget: [ManagedJSONExtension: Int] = [:]
    /// How many upcoming hard-fails may mutate `defaults` before throwing (default 1).
    var hardFailMutatingBudget: [ManagedJSONExtension: Int] = [:]
    var userCancelSetFor: Set<ManagedJSONExtension> = []
    var workspaceCandidateURL: URL?

    func defaultApplicationURL(for ext: ManagedJSONExtension) -> URL? {
        defaults[ext]
    }

    func workspaceCandidate(for ext: ManagedJSONExtension) -> URL? {
        workspaceCandidateURL
    }

    func setDefaultApplication(at appURL: URL, for ext: ManagedJSONExtension) async throws {
        if userCancelSetFor.contains(ext) {
            throw DefaultApplicationWorkspaceError.userCancelled
        }
        if hardFailSetFor.contains(ext) {
            let remaining = hardFailBudget[ext] ?? 1
            if remaining > 0 {
                hardFailBudget[ext] = remaining - 1
                setCalls.append((appURL, ext))
                let mutatingLeft = hardFailMutatingBudget[ext] ?? 1
                if mutatingLeft > 0 {
                    defaults[ext] = appURL
                    hardFailMutatingBudget[ext] = mutatingLeft - 1
                }
                throw DefaultApplicationWorkspaceError.setFailed(underlyingDescription: "mock hard failure")
            }
        }
        if failSetFor.contains(ext) {
            setCalls.append((appURL, ext))
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

    @Test func enableJsonDoesNotChangeJsonl() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = vscode
        workspace.defaults[.jsonl] = vscode
        let suite = "FileAssociationCoordinatorTests.enableJsonOnly"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = makeCoordinator(workspace: workspace, priorStore: PriorHandlerStore(defaults: defaults))

        let outcome = await coordinator.enableDotJSONAsDefault(for: .json)
        #expect(outcome == .success)
        #expect(workspace.defaults[.json] == selfApp)
        #expect(workspace.defaults[.jsonl] == vscode)
        #expect(workspace.setCalls.allSatisfy { $0.1 == .json })
    }

    @Test func enableJsonlDoesNotChangeJson() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = vscode
        workspace.defaults[.jsonl] = vscode
        let suite = "FileAssociationCoordinatorTests.enableJsonlOnly"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = makeCoordinator(workspace: workspace, priorStore: PriorHandlerStore(defaults: defaults))

        let outcome = await coordinator.enableDotJSONAsDefault(for: .jsonl)
        #expect(outcome == .success)
        #expect(workspace.defaults[.jsonl] == selfApp)
        #expect(workspace.defaults[.json] == vscode)
        #expect(workspace.setCalls.allSatisfy { $0.1 == .jsonl })
    }

    @Test func enableNoOpsWhenExtensionAlreadySelf() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = selfApp
        workspace.defaults[.jsonl] = vscode
        let coordinator = makeCoordinator(
            workspace: workspace,
            priorStore: PriorHandlerStore(defaults: UserDefaults(suiteName: "FileAssociationCoordinatorTests.noop")!)
        )

        let outcome = await coordinator.enableDotJSONAsDefault(for: .json)
        #expect(outcome == .success)
        #expect(workspace.setCalls.isEmpty)
    }

    @Test func enablePersistsPriorForExtensionOnly() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = vscode
        workspace.defaults[.jsonl] = selfApp
        let suite = "FileAssociationCoordinatorTests.priorJsonOnly"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        store.save(PriorHandlerSnapshot(jsonAppURL: URL(fileURLWithPath: "/Kept.json.app"), jsonlAppURL: nil))
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        _ = await coordinator.enableDotJSONAsDefault(for: .json)
        #expect(store.load().jsonAppURL == vscode)
        #expect(store.load().jsonlAppURL == nil)
    }

    @Test func enableDeclineReturnsCancelledWithoutChangingDefault() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = vscode
        workspace.failSetFor = [.json]
        let coordinator = makeCoordinator(
            workspace: workspace,
            priorStore: PriorHandlerStore(defaults: UserDefaults(suiteName: "FileAssociationCoordinatorTests.decline")!)
        )

        let outcome = await coordinator.enableDotJSONAsDefault(for: .json)
        #expect(outcome == .userCancelled)
        #expect(workspace.defaults[.json] == vscode)
        #expect(workspace.setCalls.count == 1)
    }

    @Test func enableHardFailureWhenDefaultIsSelf() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = vscode
        workspace.hardFailSetFor = [.json]
        workspace.hardFailBudget[.json] = 1
        let coordinator = makeCoordinator(
            workspace: workspace,
            priorStore: PriorHandlerStore(defaults: UserDefaults(suiteName: "FileAssociationCoordinatorTests.hard")!)
        )

        let outcome = await coordinator.enableDotJSONAsDefault(for: .json)
        #expect(outcome == .failure(partialRollbackFailed: false))
        #expect(workspace.defaults[.json] == vscode)
    }

    @Test func enableHardFailureWhenRollbackAlsoFails() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = vscode
        workspace.hardFailSetFor = [.json]
        workspace.hardFailBudget[.json] = 2
        workspace.hardFailMutatingBudget[.json] = 1
        let suite = "FileAssociationCoordinatorTests.hardRollback"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        store.save(PriorHandlerSnapshot(jsonAppURL: vscode, jsonlAppURL: nil))
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        let outcome = await coordinator.enableDotJSONAsDefault(for: .json)
        #expect(outcome == .failure(partialRollbackFailed: true))
        #expect(workspace.defaults[.json] == selfApp)
    }

    @Test func disableJsonDoesNotChangeJsonl() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = selfApp
        workspace.defaults[.jsonl] = selfApp
        let suite = "FileAssociationCoordinatorTests.disableJsonOnly"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        store.save(PriorHandlerSnapshot(jsonAppURL: textEdit, jsonlAppURL: vscode))
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        let outcome = await coordinator.disableDotJSONAsDefault(for: .json)
        #expect(outcome == .success)
        #expect(workspace.defaults[.json] == textEdit)
        #expect(workspace.defaults[.jsonl] == selfApp)
    }

    @Test func disableWhenPriorAppMissingUsesSystemFallback() async {
        let missingPrior = URL(fileURLWithPath: "/Applications/DotJSONCIMissingPriorApp.app")
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = selfApp
        workspace.workspaceCandidateURL = textEdit
        let suite = "FileAssociationCoordinatorTests.disableMissingPriorApp"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PriorHandlerStore(defaults: defaults)
        store.save(PriorHandlerSnapshot(jsonAppURL: missingPrior, jsonlAppURL: nil))
        let coordinator = makeCoordinator(workspace: workspace, priorStore: store)

        let outcome = await coordinator.disableDotJSONAsDefault(for: .json)
        #expect(outcome == .success)
        #expect(workspace.defaults[.json] == textEdit)
    }

    @Test func disableMissingPriorReturnsRestoreFailedForExtension() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = selfApp
        workspace.defaults[.jsonl] = vscode
        workspace.failSetFor = [.json]
        let coordinator = makeCoordinator(
            workspace: workspace,
            priorStore: PriorHandlerStore(defaults: UserDefaults(suiteName: "FileAssociationCoordinatorTests.noPrior")!)
        )

        let outcome = await coordinator.disableDotJSONAsDefault(for: .json)
        #expect(outcome == .restoreFailed)
        #expect(workspace.defaults[.json] == selfApp)
        #expect(workspace.defaults[.jsonl] == vscode)
    }

    @Test func resetOnlyTouchesRequestedExtension() async {
        let workspace = MockDefaultApplicationWorkspace()
        workspace.defaults[.json] = vscode
        workspace.defaults[.jsonl] = selfApp
        workspace.workspaceCandidateURL = textEdit
        let coordinator = makeCoordinator(
            workspace: workspace,
            priorStore: PriorHandlerStore(defaults: UserDefaults(suiteName: "FileAssociationCoordinatorTests.resetOne")!)
        )

        let outcome = await coordinator.resetToMacOSDefault(for: .jsonl)
        #expect(outcome == .success)
        #expect(workspace.defaults[.json] == vscode)
        #expect(workspace.defaults[.jsonl] == textEdit)
        #expect(workspace.setCalls.allSatisfy { $0.1 == .jsonl })
    }
}
