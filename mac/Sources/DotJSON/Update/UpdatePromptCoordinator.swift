import AppKit
import Foundation

@MainActor
protocol UpdateAlerter: AnyObject {
    func presentAvailable(
        version: String,
        onDownload: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onRemindLater: @escaping () -> Void
    )
    func presentUpToDate()
    func presentCheckFailed(onOpenReleases: @escaping () -> Void)
}

@MainActor
final class NSAlertUpdateAlerter: UpdateAlerter {
    func presentAvailable(
        version: String,
        onDownload: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onRemindLater: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Version \(version) is available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Skip This Version")
        alert.addButton(withTitle: "Remind Later")
        alert.buttons[0].keyEquivalent = "\r"
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            onDownload()
        case .alertSecondButtonReturn:
            onSkip()
        default:
            onRemindLater()
        }
    }

    func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "DotJSON is up to date."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.buttons[0].keyEquivalent = "\r"
        _ = alert.runModal()
    }

    func presentCheckFailed(onOpenReleases: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Couldn't Check for Updates"
        alert.informativeText =
            "DotJSON couldn't finish checking for updates. GitHub may be unreachable, or the API rate limit for your network may be exceeded."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Releases Page")
        alert.buttons[0].keyEquivalent = "\r"
        if alert.runModal() == .alertSecondButtonReturn {
            onOpenReleases()
        }
    }
}

@MainActor
final class UpdatePromptCoordinator {
    enum Mode {
        case automatic
        case manual
    }

    static let shared = UpdatePromptCoordinator(alerter: NSAlertUpdateAlerter())

    private let checkerFactory: @Sendable () -> UpdateChecker
    private let preferences: AppPreferences
    private let alerter: UpdateAlerter
    private let urlOpener: (URL) -> Void

    private var inFlight: Task<Void, Never>?
    private var checkID = 0
    private var didRunAutomaticCheckThisSession = false

    init(
        checkerFactory: @escaping @Sendable () -> UpdateChecker = { UpdateChecker() },
        preferences: AppPreferences = AppPreferences(),
        alerter: UpdateAlerter,
        urlOpener: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.checkerFactory = checkerFactory
        self.preferences = preferences
        self.alerter = alerter
        self.urlOpener = urlOpener
    }

    static func shouldPresentAvailable(version: String, mode: Mode, skipped: String?) -> Bool {
        switch mode {
        case .manual:
            return true
        case .automatic:
            return skipped != version
        }
    }

    func runAutomaticCheckIfNeeded() {
        guard preferences.autoCheckUpdates else { return }
        guard !didRunAutomaticCheckThisSession else { return }
        check(mode: .automatic)
    }

    func runManualCheck() {
        check(mode: .manual)
    }

    private func check(mode: Mode) {
        if mode == .automatic, inFlight != nil {
            return
        }

        if mode == .automatic {
            didRunAutomaticCheckThisSession = true
        }

        inFlight?.cancel()
        checkID += 1
        let id = checkID

        inFlight = Task { @MainActor in
            defer {
                if self.checkID == id {
                    self.inFlight = nil
                }
            }

            let checker = self.checkerFactory()
            let result = await checker.check()
            guard !Task.isCancelled else { return }

            switch result {
            case .available(let version, let releaseURL):
                guard Self.shouldPresentAvailable(
                    version: version,
                    mode: mode,
                    skipped: self.preferences.skippedUpdateVersion
                ) else {
                    return
                }
                self.alerter.presentAvailable(
                    version: version,
                    onDownload: { self.urlOpener(releaseURL) },
                    onSkip: { self.preferences.skippedUpdateVersion = version },
                    onRemindLater: {}
                )
            case .upToDate:
                if mode == .manual {
                    self.alerter.presentUpToDate()
                }
            case .unreachable, .invalidResponse:
                if mode == .manual {
                    self.alerter.presentCheckFailed {
                        self.urlOpener(UpdateURLs.releasesList)
                    }
                }
            case .cancelled:
                return
            }
        }
    }
}
