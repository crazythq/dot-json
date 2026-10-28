import SwiftUI

struct SettingsView: View {
    @State private var coordinator = FileAssociationCoordinator()
    @State private var openJSON = false
    @State private var openJSONL = false
    @State private var busyExtensions: Set<ManagedJSONExtension> = []

    var body: some View {
        Form {
            Section("Files") {
                Toggle(isOn: binding(for: .json)) {
                    Text("Open .json files with DotJSON")
                }
                .disabled(busyExtensions.contains(.json))

                Toggle(isOn: binding(for: .jsonl)) {
                    Text("Open .jsonl files with DotJSON")
                }
                .disabled(busyExtensions.contains(.jsonl))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 150)
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
        FileAssociationAlerts.confirmDisable(
            for: ext,
            onConfirm: {
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
            },
            onCancel: {
                syncToggle(for: ext)
            }
        )
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
