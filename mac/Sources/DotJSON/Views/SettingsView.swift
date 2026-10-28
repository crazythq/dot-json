import SwiftUI

struct SettingsView: View {
    @State private var coordinator = FileAssociationCoordinator()
    @State private var openJSONWithDotJSON = false
    @State private var isBusy = false

    var body: some View {
        Form {
            Section("Files") {
                Toggle(isOn: binding) {
                    Text("Open JSON files with DotJSON")
                }
                .disabled(isBusy)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 120)
        .onAppear {
            syncToggleFromSystem()
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { openJSONWithDotJSON },
            set: { newValue in
                if newValue {
                    turnOn()
                } else {
                    turnOff()
                }
            }
        )
    }

    private func syncToggleFromSystem() {
        openJSONWithDotJSON = coordinator.refreshToggleState().isFullyOn
    }

    private func turnOn() {
        isBusy = true
        Task {
            let outcome = await coordinator.enableDotJSONAsDefault()
            syncToggleFromSystem()
            isBusy = false
            if case .failure(let rollbackFailed) = outcome {
                FileAssociationAlerts.showEnableFailure(partialRollbackFailed: rollbackFailed)
            }
        }
    }

    private func turnOff() {
        FileAssociationAlerts.confirmDisable {
            isBusy = true
            Task {
                let outcome = await coordinator.disableDotJSONAsDefault()
                syncToggleFromSystem()
                isBusy = false
                switch outcome {
                case .success:
                    FileAssociationAlerts.showDisableSuccess()
                case .restoreFailed:
                    FileAssociationAlerts.showDisableFailure(offerReset: true) {
                        runReset()
                    }
                }
            }
        }
        // Re-sync immediately in case user cancels confirmation (toggle may have flipped).
        DispatchQueue.main.async {
            syncToggleFromSystem()
        }
    }

    private func runReset() {
        isBusy = true
        Task {
            let outcome = await coordinator.resetToMacOSDefaults()
            syncToggleFromSystem()
            isBusy = false
            switch outcome {
            case .success:
                FileAssociationAlerts.showResetSuccess()
            case .failure:
                FileAssociationAlerts.showResetFailure()
            }
        }
    }
}
