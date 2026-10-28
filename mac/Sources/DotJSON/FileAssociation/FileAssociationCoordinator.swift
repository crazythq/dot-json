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
        /// User declined a macOS Finder confirmation sheet (not an app error).
        case userCancelled
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
        let alreadySelf = FileAssociationLogic.extensionsAlreadySelf(
            jsonDefault: jsonDefault,
            jsonlDefault: jsonlDefault,
            selfAppURL: selfAppURL
        )
        let extensionsToSet = FileAssociationLogic.enableOrder.filter { !alreadySelf.contains($0) }
        if extensionsToSet.isEmpty {
            return .success
        }

        // macOS shows one Finder confirmation per UTI (`setDefaultApplication`); .json and .jsonl are
        // separate types, so a full enable from non-DotJSON defaults is two system sheets — not suppressible.
        var changedToSelf: [ManagedJSONExtension] = []

        for ext in extensionsToSet {
            do {
                try await workspace.setDefaultApplication(at: selfAppURL, for: ext)
            } catch {
                return await finishEnableAfterSetError(
                    error: error,
                    failingExtension: ext,
                    changedToSelf: changedToSelf,
                    prior: prior
                )
            }

            let defaultNow = workspace.defaultApplicationURL(for: ext)
            if !FileAssociationLogic.isSelfDefault(defaultApp: defaultNow, selfAppURL: selfAppURL) {
                _ = await rollbackChangedToSelf(changedToSelf: changedToSelf, prior: prior)
                return .userCancelled
            }
            changedToSelf.append(ext)
        }
        return .success
    }

    private func rollbackChangedToSelf(
        changedToSelf: [ManagedJSONExtension],
        prior: PriorHandlerSnapshot
    ) async -> Bool {
        var rollbackFailed = false
        let rollbacks = FileAssociationLogic.rollbackTargetsAfterPartialEnable(
            changedToSelf: changedToSelf,
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
        return rollbackFailed
    }

    private func finishEnableAfterSetError(
        error: Error,
        failingExtension: ManagedJSONExtension,
        changedToSelf: [ManagedJSONExtension],
        prior: PriorHandlerSnapshot
    ) async -> EnableOutcome {
        let rollbackFailed = await rollbackChangedToSelf(changedToSelf: changedToSelf, prior: prior)
        let defaultNow = workspace.defaultApplicationURL(for: failingExtension)
        let classification = FileAssociationLogic.classifyEnableSetFailure(
            error: error,
            defaultAppAfterAttempt: defaultNow,
            selfAppURL: selfAppURL
        )
        if classification == .userDeclined {
            return .userCancelled
        }
        return .failure(partialRollbackFailed: rollbackFailed)
    }

    enum DisableOutcome: Equatable {
        case success
        case partialRestore(extensionsStillDotJSON: [ManagedJSONExtension])
        case restoreFailed
    }

    func disableDotJSONAsDefault() async -> DisableOutcome {
        let prior = priorStore.load()

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
                    break
                }
            case .resetToSystemFallback:
                break
            }
        }

        let jsonDefault = workspace.defaultApplicationURL(for: .json)
        let jsonlDefault = workspace.defaultApplicationURL(for: .jsonl)
        let stillDotJSON = FileAssociationLogic.extensionsStillUsingSelf(
            jsonDefault: jsonDefault,
            jsonlDefault: jsonlDefault,
            selfAppURL: selfAppURL
        )

        if stillDotJSON.isEmpty {
            return .success
        }
        if stillDotJSON.count == ManagedJSONExtension.allCases.count {
            return .restoreFailed
        }
        return .partialRestore(extensionsStillDotJSON: stillDotJSON)
    }

    enum ResetOutcome: Equatable {
        case success
        case failure
    }

    func resetToMacOSDefaults() async -> ResetOutcome {
        let jsonDefault = workspace.defaultApplicationURL(for: .json)
        let jsonlDefault = workspace.defaultApplicationURL(for: .jsonl)
        let targets = FileAssociationLogic.extensionsStillUsingSelf(
            jsonDefault: jsonDefault,
            jsonlDefault: jsonlDefault,
            selfAppURL: selfAppURL
        )
        guard !targets.isEmpty else {
            return .success
        }

        var anyFailure = false
        for ext in targets {
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
