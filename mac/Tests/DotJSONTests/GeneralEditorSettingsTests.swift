import Testing
import Foundation
@testable import DotJSON
import DotJSONCore

@MainActor
struct GeneralEditorSettingsTests {

    private func isolatedDefaults() -> UserDefaults {
        let suite = "GeneralEditorSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func macPackageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func dotJSONSource(_ relativePath: String) -> URL {
        macPackageRoot().appendingPathComponent("Sources/DotJSON/\(relativePath)")
    }

    @Test func settingsViewIncludesGeneralAndEditorSections() throws {
        let settingsURL = dotJSONSource("Views/SettingsView.swift")
        let commandsURL = dotJSONSource("App/DotJSONCommands.swift")
        let settingsSource = try String(contentsOf: settingsURL, encoding: .utf8)
        let commandsSource = try String(contentsOf: commandsURL, encoding: .utf8)

        #expect(settingsSource.contains("Section(\"General\")"))
        #expect(settingsSource.contains("Restore Session"))
        #expect(settingsSource.contains("Recent files are always kept"))
        #expect(settingsSource.contains("Clear Recent Files"))
        #expect(settingsSource.contains("Section(\"Editor\")"))
        #expect(settingsSource.contains("Default Indent"))
        #expect(settingsSource.contains("Format on Open"))
        #expect(settingsSource.contains("Restoring a saved session never formats"))
        #expect(settingsSource.contains("Format on Paste"))
        #expect(settingsSource.contains("Section(\"Files\")"))
        #expect(!commandsSource.contains("Clear Menu"))
    }

    @Test func appPreferencesDefaultValues() {
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)

        #expect(prefs.restoreSession == true)
        #expect(prefs.formatOnOpen == true)
        #expect(prefs.formatOnPaste == true)
        #expect(prefs.defaultIndent == .fourSpaces)
    }

    @Test func sessionRestoreNeverFormatsEvenWhenFormatOnOpenEnabled() throws {
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.formatOnOpen = true

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore_no_format_\(UUID().uuidString).json")
        let rawOnDisk = #"{"z":1,"a":2}"#
        try rawOnDisk.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        struct SessionSnapshot: Codable {
            let fileURLs: [String]
            let activeIndex: Int
            let recentFiles: [String]
        }
        let snapshot = SessionSnapshot(
            fileURLs: [url.path],
            activeIndex: 0,
            recentFiles: [url.path]
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "dotjson.workspaceState")

        let ws = WorkspaceViewModel(userDefaults: defaults)

        #expect(ws.tabs.count == 1)
        #expect(ws.tabs[0].rawText == rawOnDisk)
        #expect(ws.recentFiles.count == 1)
    }

    @Test func restoreSessionOffStillRestoresRecentFiles() throws {
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.restoreSession = false

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore_off_recent_\(UUID().uuidString).json")
        try #"{"k":1}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        struct SessionSnapshot: Codable {
            let fileURLs: [String]
            let activeIndex: Int
            let recentFiles: [String]
        }
        let snapshot = SessionSnapshot(
            fileURLs: [url.path],
            activeIndex: 0,
            recentFiles: [url.path]
        )
        defaults.set(try JSONEncoder().encode(snapshot), forKey: "dotjson.workspaceState")

        let ws = WorkspaceViewModel(userDefaults: defaults)

        #expect(ws.recentFiles.map(\.path) == [url.path])
        #expect(ws.tabs.count == 1)
        #expect(ws.tabs[0].fileURL == nil)
    }

    @Test func clearRecentFilesDoesNotCloseTabs() throws {
        let defaults = isolatedDefaults()
        AppPreferences(defaults: defaults).clearPreferenceKeys()
        defaults.removeObject(forKey: "dotjson.workspaceState")

        let ws = WorkspaceViewModel(userDefaults: defaults)
        ws.closeAllTabs()
        ws.newTab()
        ws.newTab()
        let tabCount = ws.tabs.count

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clear_recent_\(UUID().uuidString).json")
        ws.addRecent(url)

        ws.clearRecentFiles()

        #expect(ws.recentFiles.isEmpty)
        #expect(ws.tabs.count == tabCount)
    }

    /// Q4: new open applies default indent before load. Changing default indent later must not reformat open tabs.
    @Test func defaultIndentPreferenceDoesNotChangeOpenTabs() throws {
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.defaultIndent = .twoSpaces
        defaults.removeObject(forKey: "dotjson.workspaceState")

        let ws = WorkspaceViewModel(userDefaults: defaults)
        ws.closeAllTabs()
        ws.newTab()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("indent_stays_\(UUID().uuidString).json")
        let fourSpace = try JSONFormatter.format(#"{"a":1}"#, indent: .fourSpaces)
        try fourSpace.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        ws.openDocument(from: url)
        guard let tab = ws.tabs.first(where: { $0.fileURL == url }) else {
            Issue.record("Expected opened tab")
            return
        }
        #expect(tab.indent == .twoSpaces)

        prefs.defaultIndent = .tab
        #expect(tab.indent == .twoSpaces)
    }

    @Test func newTabUsesDefaultIndentFromPreferences() {
        let defaults = isolatedDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.defaultIndent = .twoSpaces
        defaults.removeObject(forKey: "dotjson.workspaceState")

        let ws = WorkspaceViewModel(userDefaults: defaults)
        ws.closeAllTabs()
        ws.newTab()

        #expect(ws.tabs.last?.indent == .twoSpaces)
    }

    @Test func syncFormatOnPasteUpdatesOpenTabs() {
        let defaults = isolatedDefaults()
        defaults.removeObject(forKey: "dotjson.workspaceState")
        let ws = WorkspaceViewModel(userDefaults: defaults)
        ws.closeAllTabs()
        ws.newTab()
        ws.newTab()
        ws.tabs[0].autoFormatOnPaste = true
        ws.tabs[1].autoFormatOnPaste = true

        ws.syncFormatOnPasteToOpenTabs(false)

        #expect(ws.tabs[0].autoFormatOnPaste == false)
        #expect(ws.tabs[1].autoFormatOnPaste == false)
    }
}
