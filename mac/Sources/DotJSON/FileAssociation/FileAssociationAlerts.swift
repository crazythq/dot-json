import AppKit
import Foundation

@MainActor
enum FileAssociationAlerts {
    private static let getInfoSteps = """
    Manual steps:
    1. In Finder, select any .json or .jsonl file.
    2. Press ⌘I (Get Info).
    3. Under “Open with”, choose the app you want.
    4. Click “Change All…” to apply to all files of that type.
    """

    static func showEnableFailure(for ext: ManagedJSONExtension, partialRollbackFailed: Bool) {
        var message =
            "DotJSON could not be set as the default app for .\(ext.rawValue) files."
        if partialRollbackFailed {
            message += " A partial change may remain; please fix .\(ext.rawValue) in Finder."
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

    static func showDisableFailure(
        for ext: ManagedJSONExtension,
        offerReset: Bool,
        onReset: @escaping () -> Void
    ) {
        var buttons = ["OK", "Open System Settings…"]
        if offerReset {
            buttons.insert("Reset to macOS Default", at: 0)
        }
        var message =
            "DotJSON could not restore the previous default app for .\(ext.rawValue) files."
        message += "\n\n\(getInfoSteps)"
        presentAlert(
            title: "Restore Failed",
            message: message,
            informativeText: offerReset
                ? "Reset to macOS Default will only change .\(ext.rawValue) files still set to DotJSON."
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

    static func showResetSuccess(for ext: ManagedJSONExtension) {
        presentAlert(
            title: "Defaults Reset",
            message: "macOS default apps were applied for .\(ext.rawValue) files.",
            informativeText: nil,
            buttons: ["OK"],
            defaultButtonIndex: 0,
            handler: nil
        )
    }

    static func showResetFailure(for ext: ManagedJSONExtension) {
        var message = "Could not reset the default app for .\(ext.rawValue) files automatically."
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

    static func confirmDisable(
        for ext: ManagedJSONExtension,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        presentAlert(
            title: "Stop opening .\(ext.rawValue) with DotJSON?",
            message:
                "This will restore the app that opened .\(ext.rawValue) files before you turned this on.",
            informativeText: nil,
            buttons: ["Cancel", "Restore Previous App"],
            defaultButtonIndex: 1
        ) { response in
            if response == .alertSecondButtonReturn {
                onConfirm()
            } else {
                onCancel?()
            }
        }
    }

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
        if defaultButtonIndex >= 0, defaultButtonIndex < alert.buttons.count {
            alert.buttons[defaultButtonIndex].keyEquivalent = "\r"
        }
        let response = alert.runModal()
        handler?(response)
    }
}
