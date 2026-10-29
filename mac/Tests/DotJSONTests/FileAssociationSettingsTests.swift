import Foundation
import Testing

/// Structural checks for Settings (General, Editor, Files).
struct FileAssociationSettingsTests {
    /// `mac/` package root from this test file (`Tests/DotJSONTests/...`).
    private func macPackageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func dotJSONSource(_ relativePath: String) -> URL {
        macPackageRoot().appendingPathComponent("Sources/DotJSON/\(relativePath)")
    }

    @Test func appExposesSettingsSceneWithFilesToggle() throws {
        let appURL = dotJSONSource("App/DotJSONApp.swift")
        let settingsURL = dotJSONSource("Views/SettingsView.swift")

        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        let settingsSource = try String(contentsOf: settingsURL, encoding: .utf8)

        #expect(appSource.contains("Settings {"))
        #expect(appSource.contains("SettingsView()"))
        #expect(settingsSource.contains("Section(\"Files\")"))
        #expect(settingsSource.contains("Associate with .json files"))
        #expect(settingsSource.contains("Associate with .jsonl files"))
        #expect(settingsSource.contains("Use DotJSON as the default app"))
        #expect(!settingsSource.contains("Open .json files"))
        #expect(!settingsSource.contains("Associate DotJSON with .json files"))
        #expect(!settingsSource.contains("Handler"))
        #expect(!settingsSource.contains("confirmDisable"))
        #expect(!settingsSource.contains("Restore Previous App"))
        #expect(settingsSource.contains("Section(\"General\")"))
        #expect(settingsSource.contains("Section(\"Editor\")"))
    }


    @Test func settingsSupportsEscapeAndCommandWClose() throws {
        let settings = try String(contentsOf: dotJSONSource("Views/SettingsView.swift"), encoding: .utf8)
        let commands = try String(contentsOf: dotJSONSource("App/DotJSONCommands.swift"), encoding: .utf8)
        #expect(settings.contains("SettingsEscapeKeyMonitor"))
        #expect(settings.contains("keyCode == 53"))
        #expect(settings.contains("performClose(nil)"))
        #expect(commands.contains("performCloseCommand()"))
        #expect(commands.contains("isSettingsWindow"))
        #expect(commands.contains("keyboardShortcut(\"w\", modifiers: .command)"))
    }


    @Test func infoPlistDeclaresJsonlWithoutOwningPublicJsonl() throws {
        let plistURL = macPackageRoot().appendingPathComponent("Info.plist")
        let plist = try String(contentsOf: plistURL, encoding: .utf8)

        #expect(plist.contains("sh.crazy.dotjson.jsonl"))
        #expect(plist.contains("org.jsonlines.jsonl"))
        #expect(plist.contains("UTExportedTypeDeclarations"))
        #expect(plist.contains("UTImportedTypeDeclarations"))
        let exportedRange = try #require(plist.range(of: "UTExportedTypeDeclarations"))
        let importedRange = try #require(plist.range(of: "UTImportedTypeDeclarations"))
        let exportedSection = String(plist[exportedRange.lowerBound..<importedRange.lowerBound])
        #expect(!exportedSection.contains("public.jsonl"))
    }
}
