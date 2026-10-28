import SwiftUI
import DotJSONCore

struct SettingsView: View {
    @State private var coordinator = FileAssociationCoordinator()
    @State private var openJSON = false
    @State private var openJSONL = false
    @State private var busyExtensions: Set<ManagedJSONExtension> = []

    @AppStorage(AppPreferences.StorageKey.restoreSession)
    private var restoreSession: Bool = true

    @AppStorage(AppPreferences.StorageKey.formatOnOpen)
    private var formatOnOpen: Bool = true

    @AppStorage(AppPreferences.StorageKey.formatOnPaste)
    private var formatOnPaste: Bool = true

    @AppStorage(AppPreferences.StorageKey.defaultIndent)
    private var defaultIndentRaw: String = AppPreferences.DefaultIndentEncoding.fourSpaces.rawValue

    var body: some View {
        Form {
            Section("General") {
                Toggle(isOn: $restoreSession) {
                    SettingsToggleLabels(
                        title: "Restore Session",
                        subtitle: "Reopen tabs from your last session when DotJSON launches. Recent files are always kept, even when this is off."
                    )
                }

                Button("Clear Recent Files") {
                    WorkspaceViewModel.shared?.clearRecentFiles()
                }
            }

            Section("Editor") {
                Picker("Default Indent", selection: $defaultIndentRaw) {
                    Text("2 Spaces").tag(AppPreferences.DefaultIndentEncoding.twoSpaces.rawValue)
                    Text("4 Spaces").tag(AppPreferences.DefaultIndentEncoding.fourSpaces.rawValue)
                    Text("Tab").tag(AppPreferences.DefaultIndentEncoding.tab.rawValue)
                }

                Toggle(isOn: $formatOnOpen) {
                    SettingsToggleLabels(
                        title: "Format on Open",
                        subtitle: "Format JSON when you open a file. Restoring a saved session never formats tabs."
                    )
                }
                .onChange(of: formatOnOpen) { _, enabled in
                    WorkspaceViewModel.shared?.syncFormatOnOpenToOpenTabs(enabled: enabled)
                }

                Toggle(isOn: $formatOnPaste) {
                    SettingsToggleLabels(
                        title: "Format on Paste",
                        subtitle: "Automatically format pasted JSON in the editor."
                    )
                }
                .onChange(of: formatOnPaste) { _, enabled in
                    WorkspaceViewModel.shared?.syncFormatOnPasteToOpenTabs(enabled)
                }
            }

            Section("Files") {
                Toggle(isOn: binding(for: .json)) {
                    FileAssociationToggleLabels(
                        title: "Associate with .json files",
                        subtitle: "Use DotJSON as the default app"
                    )
                }
                .disabled(busyExtensions.contains(.json))

                Toggle(isOn: binding(for: .jsonl)) {
                    FileAssociationToggleLabels(
                        title: "Associate with .jsonl files",
                        subtitle: "Use DotJSON as the default app"
                    )
                }
                .disabled(busyExtensions.contains(.jsonl))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 360)
        .onAppear {
            syncTogglesFromSystem()
        }
    }

    private func binding(for ext: ManagedJSONExtension) -> Binding<Bool> {
        Binding(
            get: { ext == .json ? openJSON : openJSONL },
            set: { newValue in
                if newValue {
                    turnOn(ext)
                } else {
                    turnOff(ext)
                }
            }
        )
    }

    private func syncTogglesFromSystem() {
        openJSON = coordinator.isDotJSONDefault(for: .json)
        openJSONL = coordinator.isDotJSONDefault(for: .jsonl)
    }

    private func syncToggle(for ext: ManagedJSONExtension) {
        switch ext {
        case .json:
            openJSON = coordinator.isDotJSONDefault(for: .json)
        case .jsonl:
            openJSONL = coordinator.isDotJSONDefault(for: .jsonl)
        }
    }

    private func turnOn(_ ext: ManagedJSONExtension) {
        if coordinator.isDotJSONDefault(for: ext) {
            syncToggle(for: ext)
            return
        }
        guard !busyExtensions.contains(ext) else { return }
        busyExtensions.insert(ext)
        Task {
            let outcome = await coordinator.enableDotJSONAsDefault(for: ext)
            syncToggle(for: ext)
            busyExtensions.remove(ext)
            if case .failure(let rollbackFailed) = outcome {
                FileAssociationAlerts.showEnableFailure(for: ext, partialRollbackFailed: rollbackFailed)
            }
        }
    }

    private func turnOff(_ ext: ManagedJSONExtension) {
        guard !busyExtensions.contains(ext) else { return }
        busyExtensions.insert(ext)
        Task {
            let outcome = await coordinator.disableDotJSONAsDefault(for: ext)
            syncToggle(for: ext)
            busyExtensions.remove(ext)
            if case .restoreFailed = outcome {
                FileAssociationAlerts.showDisableFailure(for: ext, offerReset: true) {
                    runReset(for: ext)
                }
            }
        }
    }

    private func runReset(for ext: ManagedJSONExtension) {
        busyExtensions.insert(ext)
        Task {
            let outcome = await coordinator.resetToMacOSDefault(for: ext)
            syncToggle(for: ext)
            busyExtensions.remove(ext)
            switch outcome {
            case .success:
                FileAssociationAlerts.showResetSuccess(for: ext)
            case .failure:
                FileAssociationAlerts.showResetFailure(for: ext)
            }
        }
    }
}

private struct SettingsToggleLabels: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FileAssociationToggleLabels: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
