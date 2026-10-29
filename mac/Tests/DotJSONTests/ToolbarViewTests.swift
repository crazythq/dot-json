import DotJSONCore
import Foundation
import Testing
@testable import DotJSON

/// 工具栏布局的结构性回归测试。
struct ToolbarViewTests {
    private func toolbarSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ToolbarView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    @Test func toolbarDoesNotContainManualDivider() throws {
        let source = try toolbarSource()
        #expect(!source.contains("Divider()"))
    }

    @Test func toolbarDoesNotIncludeIndentPopUpButton() throws {
        let source = try toolbarSource()
        let popupURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/IndentPopUpButton.swift")

        #expect(!source.contains("IndentPopUpButton"))
        #expect(!FileManager.default.fileExists(atPath: popupURL.path))
    }

    @Test func allIndentOptionsHaveVisibleEnglishTitles() {
        for option in JSONFormatter.Indent.allCases {
            #expect(!option.label.isEmpty)
        }
    }

    @Test func allEightActionsUseToolbarActionHelpersWithoutControlGroup() throws {
        let source = try toolbarSource()

        #expect(source.contains("toolbarActionButton(\"Format\", systemImage: \"text.alignleft\")"))
        #expect(source.contains("toolbarActionButton(\"Minify\", systemImage: \"text.aligncenter\")"))
        #expect(source.contains("toolbarVerticalMenuButton("))
        #expect(source.contains("title: \"Export\""))
        #expect(source.contains("toolbarActionButton(\"Clear\", systemImage: \"trash\")"))
        #expect(source.contains("toolbarActionButton(\"Paste\", systemImage: \"doc.on.clipboard\")"))
        #expect(source.contains("toolbarActionButton(\"Copy\", systemImage: \"doc.on.doc\")"))
        #expect(source.contains("toolbarActionButton(\"Import\", systemImage: \"square.and.arrow.down\")"))
        #expect(!source.contains("ControlGroup"))
        #expect(!source.contains("ToolbarItemGroup"))
        #expect(!source.contains(".labelStyle(.titleAndIcon)"))
    }

    @Test func toolbarUsesVerticalIconAboveCaptionLayout() throws {
        let source = try toolbarSource()

        #expect(source.contains("private struct ToolbarActionLabelStyle: LabelStyle"))
        #expect(source.contains("VStack(spacing: ToolbarMetrics.verticalIconTitleSpacing)"))
        #expect(source.contains("static let captionPointSize: CGFloat = 11"))
        #expect(source.contains("static let verticalButtonMinHeight: CGFloat = 38"))
        #expect(source.contains("func toolbarActionChrome()"))
    }

    @Test func convertAndExportUseAppKitVerticalMenuButtonsNotSwiftUIMenu() throws {
        let source = try toolbarSource()

        #expect(source.contains("struct ToolbarVerticalMenuButton: NSViewRepresentable"))
        #expect(source.contains("ToolbarVerticalMenuHostView"))
        #expect(source.contains("ToolbarActionFace("))
        #expect(source.contains("showsMenuChevron: true"))
        #expect(source.contains("SwiftUI `Menu` ignores custom label chrome in toolbars"))
        #expect(!source.contains("toolbarMenuActionLabel"))
        #expect(!source.contains("Menu {"))
        #expect(!source.contains(".menuStyle(.borderlessButton)"))
    }

    @Test func toolbarProvidesJSONImportAction() throws {
        let source = try toolbarSource()

        #expect(source.contains("private func importDocument()"))
        #expect(source.contains("ws.openDocuments(panel.urls)"))
    }

    @Test func toolbarNoLongerHostsSearch() throws {
        let source = try toolbarSource()
        #expect(!source.contains("ToolbarItem(placement: .principal)"))
    }

    @Test func toolbarMetricsStillPresent() throws {
        let source = try toolbarSource()

        #expect(source.contains("static let hideTextBelowWidth: CGFloat = 780"))
        #expect(source.contains("static let iconOnlyHitSize: CGFloat = 28"))
    }

    @Test func toolbarIconLabelsKeepNativeLabelSemanticsForOverflowMenuRows() throws {
        let source = try toolbarSource()

        #expect(source.contains("Label(title, systemImage: systemImage)"))
        #expect(source.contains("setAccessibilityHelp(help)"))
    }

    @Test func contentViewPassesWindowWidthToToolbar() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("ToolbarView(windowWidth: mainWindowContentWidth)"))
    }

    @Test func splitPanesAllowTenPointMinimumWidth() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains(".frame(minWidth: 10)"))
    }
}
