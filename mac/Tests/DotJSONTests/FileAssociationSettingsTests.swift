import Foundation
import Testing

/// Structural checks for minimal Settings scope (Files toggle only).
struct FileAssociationSettingsTests {
    @Test func appExposesSettingsSceneWithFilesToggle() throws {
        let appURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/App/DotJSONApp.swift")
        let settingsURL = appURL
            .deletingLastPathComponent()
            .appendingPathComponent("Views/SettingsView.swift")

        let appSource = try String(contentsOf: appURL, encoding: .utf8)
        let settingsSource = try String(contentsOf: settingsURL, encoding: .utf8)

        #expect(appSource.contains("Settings {"))
        #expect(appSource.contains("SettingsView()"))
        #expect(settingsSource.contains("Section(\"Files\")"))
        #expect(settingsSource.contains("Open JSON files with DotJSON"))
        #expect(!settingsSource.contains("Section(\"General\")"))
        #expect(!settingsSource.contains("Section(\"Editor\")"))
    }

    @Test func infoPlistDeclaresJsonlWithoutOwningPublicJsonl() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
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
