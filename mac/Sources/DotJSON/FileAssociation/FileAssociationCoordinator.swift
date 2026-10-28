import Foundation

/// Orchestrates enable / disable / reset using pure decisions + workspace I/O.
@MainActor
final class FileAssociationCoordinator {
    private let workspace: any DefaultApplicationWorkspace
    private let priorStore: PriorHandlerStore
    private let selfAppURL: URL
    private let fileManager: FileManager

    init(
        workspace: any DefaultApplicationWorkspace = LiveDefaultApplicationWorkspace(),
        priorStore: PriorHandlerStore = PriorHandlerStore(),
        selfAppURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.priorStore = priorStore
        self.selfAppURL = selfAppURL
        self.fileManager = fileManager
    }

    func refreshToggleState() -> FileAssociationToggleState {
        let json = workspace.defaultApplicationURL(for: .json)
        let jsonl = workspace.defaultApplicationURL(for: .jsonl)
        return FileAssociationLogic.toggleState(
            jsonDefault: json,
            jsonlDefault: jsonl,
            selfAppURL: selfAppURL
        )
    }

    enum EnableOutcome: Equatable {
        case success
        case failure(partialRollbackFailed: Bool)
    }

    func enableDotJSONAsDefault() async -> EnableOutcome {
        let state = refreshToggleState()
        let jsonDefault = workspace.defaultApplicationURL(for: .json)
        let jsonlDefault = workspace.defaultApplicationURL(for: .jsonl)

        if FileAssociationLogic.shouldPersistPriorWhenEnabling(state: state) {
            let prior = FileAssociationLogic.priorToPersistWhenEnabling(
                jsonDefault: jsonDefault,
                jsonlDefault: jsonlDefault,
                selfAppURL: selfAppURL
            )
            priorStore.merge(prior)
        }

        let prior = priorStore.load()
        var succeeded: [ManagedJSONExtension] = []

        for ext in FileAssociationLogic.enableOrder {
            do {
                try await workspace.setDefaultApplication(at: selfAppURL, for: ext)
                succeeded.append(ext)
            } catch {
                var rollbackFailed = false
                let rollbacks = FileAssociationLogic.rollbackTargetsAfterPartialEnable(
                    succeeded: succeeded,
                    prior: prior
                )
                for (rollbackExt, priorURL) in rollbacks {
                    let candidate = workspace.workspaceCandidate(for: rollbackExt)
                    guard let target = priorURL ?? FileAssociationLogic.systemFallbackApp(
                        for: rollbackExt,
                        workspaceCandidate: candidate,
                        selfAppURL: selfAppURL
                    ) else {
                        rollbackFailed = true
                        continue
                    }
                    do {
                        try await workspace.setDefaultApplication(at: target, for: rollbackExt)
                    } catch {
                        rollbackFailed = true
                    }
                }
                return .failure(partialRollbackFailed: rollbackFailed)
            }
        }
        return .success
    }

    enum DisableOutcome: Equatable {
        case success
        case restoreFailed
    }

    func disableDotJSONAsDefault() async -> DisableOutcome {
        let prior = priorStore.load()
        var failed: [ManagedJSONExtension] = []

        for ext in ManagedJSONExtension.allCases {
            let action = FileAssociationLogic.restoreAction(
                for: ext,
                prior: prior,
                priorAppExists: { url in
                    fileManager.fileExists(atPath: url.path)
                }
            )
            switch action {
            case .restorePrior(let url):
                do {
                    try await workspace.setDefaultApplication(at: url, for: ext)
                } catch {
                    failed.append(ext)
                }
            case .resetToSystemFallback:
                failed.append(ext)
            }
        }

        if failed.isEmpty {
            return .success
        }
        return .restoreFailed
    }

    enum ResetOutcome: Equatable {
        case success
        case failure
    }

    func resetToMacOSDefaults() async -> ResetOutcome {
        var anyFailure = false
        for ext in ManagedJSONExtension.allCases {
            let candidate = workspace.workspaceCandidate(for: ext)
            guard let fallback = FileAssociationLogic.systemFallbackApp(
                for: ext,
                workspaceCandidate: candidate,
                selfAppURL: selfAppURL
            ) else {
                anyFailure = true
                continue
            }
            do {
                try await workspace.setDefaultApplication(at: fallback, for: ext)
            } catch {
                anyFailure = true
            }
        }
        if !anyFailure {
            priorStore.clear()
        }
        return anyFailure ? .failure : .success
    }
}
