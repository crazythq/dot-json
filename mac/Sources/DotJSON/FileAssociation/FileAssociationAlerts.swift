import AppKit
import Foundation

enum FileAssociationAlerts {
    private static let getInfoSteps = """
    Manual steps:
    1. In Finder, select any .json or .jsonl file.
    2. Press ⌘I (Get Info).
    3. Under “Open with”, choose the app you want.
    4. Click “Change All…” to apply to all files of that type.
    """

    static func showEnableFailure(partialRollbackFailed: Bool) {
        var message = "DotJSON could not be set as the default app for JSON files."
        if partialRollbackFailed {
            message += " A partial change may remain; please fix both .json and .jsonl in Finder."
        }
        message += "\n\n\(getInfoSteps)"
        presentAlert(
            title: "Could Not Set Default App",
            message: message,
            informativeText: nil,
            buttons: ["OK", "Open System Settings…"],
            defaultButtonIndex: 0
        ) { response in
            if response == .alertSecondButtonReturn {
                openSystemSettingsIfPossible()
            }
        }
    }

    static func showDisableSuccess() {
        presentAlert(
            title: "Default App Restored",
            message: "Your previous default apps for .json and .jsonl were restored.",
            informativeText: nil,
            buttons: ["OK"],
            defaultButtonIndex: 0,
            handler: nil
        )
    }

    static func showDisableFailure(offerReset: Bool, onReset: @escaping () -> Void) {
        var buttons = ["OK", "Open System Settings…"]
        if offerReset {
            buttons.insert("Reset to macOS Default", at: 0)
        }
        var message = "DotJSON could not restore your previous default apps."
        message += "\n\n\(getInfoSteps)"
        presentAlert(
            title: "Restore Failed",
            message: message,
            informativeText: offerReset
                ? "You can reset to a typical macOS default (such as TextEdit) or change defaults manually."
                : nil,
            buttons: buttons,
            defaultButtonIndex: 0
        ) { response in
            guard offerReset else {
                if response == .alertSecondButtonReturn { openSystemSettingsIfPossible() }
                return
            }
            switch response {
            case .alertFirstButtonReturn:
                onReset()
            case .alertThirdButtonReturn:
                openSystemSettingsIfPossible()
            default:
                break
            }
        }
    }

    static func showResetSuccess() {
        presentAlert(
            title: "Defaults Reset",
            message: "macOS default apps were applied for .json and .jsonl.",
            informativeText: nil,
            buttons: ["OK"],
            defaultButtonIndex: 0,
            handler: nil
        )
    }

    static func showResetFailure() {
        var message = "Could not reset default apps automatically."
        message += "\n\n\(getInfoSteps)"
        presentAlert(
            title: "Reset Failed",
            message: message,
            informativeText: nil,
            buttons: ["OK", "Open System Settings…"],
            defaultButtonIndex: 0
        ) { response in
            if response == .alertSecondButtonReturn {
                openSystemSettingsIfPossible()
            }
        }
    }

    static func confirmDisable(onConfirm: @escaping () -> Void) {
        presentAlert(
            title: "Stop Opening JSON with DotJSON?",
            message: "This will restore the apps that opened .json and .jsonl before you turned this on.",
            informativeText: nil,
            buttons: ["Cancel", "Restore Previous Apps"],
            defaultButtonIndex: 1
        ) { response in
            if response == .alertSecondButtonReturn {
                onConfirm()
            }
        }
    }

    /// Attempts Desktop & Dock → Default web browser area; no reliable per-extension pane on macOS 14.
    static func openSystemSettingsIfPossible() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Default-Apps-Settings.extension",
            "x-apple.systempreferences:com.apple.settings.Default-apps",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
        _ = NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
    }

    private static func presentAlert(
        title: String,
        message: String,
        informativeText: String?,
        buttons: [String],
        defaultButtonIndex: Int,
        handler: ((NSApplication.ModalResponse) -> Void)?
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = [message, informativeText].compactMap { $0 }.joined(separator: "\n\n")
        for button in buttons {
            alert.addButton(withTitle: button)
        }
        alert.alertStyle = .warning
        let response = alert.runModal()
        handler?(response)
    }
}
