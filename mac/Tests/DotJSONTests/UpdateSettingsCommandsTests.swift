import Testing
import Foundation

struct UpdateSettingsCommandsTests {
    private func macPackageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) -> URL {
        macPackageRoot().appendingPathComponent("Sources/DotJSON/\(relative)")
    }

    @Test func settingsExposesAutoCheckToggleAndButton() throws {
        let text = try String(contentsOf: source("Views/SettingsView.swift"), encoding: .utf8)
        #expect(text.contains("Check for Updates Automatically"))
        #expect(text.contains("Check for Updates…"))
        #expect(text.contains("dotjson.autoCheckUpdates") || text.contains("AppPreferences.StorageKey.autoCheckUpdates"))
    }

    @Test func commandsExposesCheckForUpdatesMenuItem() throws {
        let text = try String(contentsOf: source("App/DotJSONCommands.swift"), encoding: .utf8)
        #expect(text.contains("Check for Updates…"))
        #expect(text.contains("CommandGroup(after: .appInfo)"))
        #expect(text.contains("runManualCheck"))
    }

    @Test func appTriggersAutomaticCheckOnAppear() throws {
        let text = try String(contentsOf: source("App/DotJSONApp.swift"), encoding: .utf8)
        #expect(text.contains("runAutomaticCheckIfNeeded"))
    }

    @Test func checkFailedAlertMentionsUnreachableAndRateLimit() throws {
        let text = try String(contentsOf: source("Update/UpdatePromptCoordinator.swift"), encoding: .utf8)
        #expect(text.contains("Couldn't Check for Updates"))
        #expect(text.contains("couldn't finish checking for updates"))
        #expect(text.contains("API rate limit"))
        #expect(!text.contains("could not reach GitHub to check for updates"))
    }
}
