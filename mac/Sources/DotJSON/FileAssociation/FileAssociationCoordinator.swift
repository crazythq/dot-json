import Foundation

/// Orchestrates per-extension default-handler changes.
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

    func isDotJSONDefault(for ext: ManagedJSONExtension) -> Bool {
        FileAssociationLogic.isSelfDefault(
            defaultApp: workspace.defaultApplicationURL(for: ext),
            selfAppURL: selfAppURL
        )
    }

    enum EnableOutcome: Equatable {
        case success
        case userCancelled
        case failure(partialRollbackFailed: Bool)
    }

    func enableDotJSONAsDefault(for ext: ManagedJSONExtension) async -> EnableOutcome {
        let currentDefault = workspace.defaultApplicationURL(for: ext)
        if FileAssociationLogic.isSelfDefault(defaultApp: currentDefault, selfAppURL: selfAppURL) {
            return .success
        }

        var snapshot = PriorHandlerSnapshot()
        snapshot.set(currentDefault, for: ext)
        priorStore.merge(snapshot)

        let prior = priorStore.load()
        do {
            try await workspace.setDefaultApplication(at: selfAppURL, for: ext)
        } catch {
            var changedToSelf: [ManagedJSONExtension] = []
            if FileAssociationLogic.isSelfDefault(
                defaultApp: workspace.defaultApplicationURL(for: ext),
                selfAppURL: selfAppURL
            ) {
                changedToSelf = [ext]
            }
            return await finishEnableAfterSetError(
                error: error,
                failingExtension: ext,
                changedToSelf: changedToSelf,
                prior: prior
            )
        }

        let defaultNow = workspace.defaultApplicationURL(for: ext)
        if !FileAssociationLogic.isSelfDefault(defaultApp: defaultNow, selfAppURL: selfAppURL) {
            return .userCancelled
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
                selfAppURL: selfAppURL,
                fileManager: fileManager
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
        let defaultAfterAttempt = workspace.defaultApplicationURL(for: failingExtension)
        let classification = FileAssociationLogic.classifyEnableSetFailure(
            error: error,
            defaultAppAfterAttempt: defaultAfterAttempt,
            selfAppURL: selfAppURL
        )
        let rollbackFailed = await rollbackChangedToSelf(changedToSelf: changedToSelf, prior: prior)
        if classification == .userDeclined {
            return .userCancelled
        }
        return .failure(partialRollbackFailed: rollbackFailed)
    }

    enum DisableOutcome: Equatable {
        case success
        case restoreFailed
    }

    private func applySystemFallback(for ext: ManagedJSONExtension) async {
        let candidate = workspace.workspaceCandidate(for: ext)
        guard let fallback = FileAssociationLogic.systemFallbackApp(
            for: ext,
            workspaceCandidate: candidate,
            selfAppURL: selfAppURL,
            fileManager: fileManager
        ) else {
            return
        }
        do {
            try await workspace.setDefaultApplication(at: fallback, for: ext)
        } catch {
            return
        }
    }

    func disableDotJSONAsDefault(for ext: ManagedJSONExtension) async -> DisableOutcome {
        let prior = priorStore.load()
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
                await applySystemFallback(for: ext)
            }
        case .resetToSystemFallback:
            await applySystemFallback(for: ext)
        }

        if isDotJSONDefault(for: ext) {
            return .restoreFailed
        }
        priorStore.clear(for: ext)
        return .success
    }

    enum ResetOutcome: Equatable {
        case success
        case failure
    }

    func resetToMacOSDefault(for ext: ManagedJSONExtension) async -> ResetOutcome {
        guard isDotJSONDefault(for: ext) else {
            return .success
        }

        let candidate = workspace.workspaceCandidate(for: ext)
        guard let fallback = FileAssociationLogic.systemFallbackApp(
            for: ext,
            workspaceCandidate: candidate,
            selfAppURL: selfAppURL,
            fileManager: fileManager
        ) else {
            return .failure
        }
        do {
            try await workspace.setDefaultApplication(at: fallback, for: ext)
        } catch {
            return .failure
        }
        if isDotJSONDefault(for: ext) {
            return .failure
        }
        priorStore.clear(for: ext)
        return .success
    }
}
