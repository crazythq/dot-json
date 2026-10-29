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
        #expect(source.contains("toolbarMenuActionLabel(\n                    String(localized: \"toolbar.convert\""))
        #expect(source.contains("toolbarMenuActionLabel(\"Export\", systemImage: \"square.and.arrow.up\")"))
        #expect(source.contains("toolbarActionButton(\"Clear\", systemImage: \"trash\")"))
        #expect(source.contains("toolbarActionButton(\"Paste\", systemImage: \"doc.on.clipboard\")"))
        #expect(source.contains("toolbarActionButton(\"Copy\", systemImage: \"doc.on.doc\")"))
        #expect(source.contains("toolbarActionButton(\"Import\", systemImage: \"square.and.arrow.down\")"))
        #expect(!source.contains("ControlGroup"))
        #expect(!source.contains("ToolbarItemGroup"))
        #expect(!source.contains(".labelStyle(.titleAndIcon)"))
        #expect(!source.contains("ToolbarAdaptiveLabelStyle"))
    }

    @Test func toolbarUsesVerticalIconAboveCaptionLayout() throws {
        let source = try toolbarSource()

        #expect(source.contains("private struct ToolbarActionLabelStyle: LabelStyle"))
        #expect(source.contains("VStack(spacing: ToolbarMetrics.verticalIconTitleSpacing)"))
        #expect(source.contains("configuration.icon"))
        #expect(source.contains("configuration.title"))
        #expect(source.contains("static let captionPointSize: CGFloat = 11"))
        #expect(source.contains("static let verticalButtonMinHeight: CGFloat = 38"))
        #expect(source.contains("private struct ToolbarActionButtonStyle: ButtonStyle"))
        #expect(!source.contains("HStack(spacing: ToolbarMetrics.titleAndIconSpacing)"))
    }

    @Test func convertAndExportMenusUseVerticalMenuLabels() throws {
        let source = try toolbarSource()

        #expect(source.contains("private func toolbarMenuActionLabel"))
        #expect(source.contains("ToolbarActionFace("))
        #expect(source.contains("showsMenuChevron: true"))
        #expect(source.contains(".menuStyle(.borderlessButton)"))
        #expect(source.contains(".menuIndicator(.hidden)"))
        #expect(source.contains("horizontal titleAndIcon"))
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
        #expect(source.contains("static let iconOnlyPadding: CGFloat = 6"))
    }

    @Test func toolbarIconLabelsKeepNativeLabelSemanticsForOverflowMenuRows() throws {
        let source = try toolbarSource()

        #expect(source.contains("Label(title, systemImage: systemImage)"))
        #expect(source.contains(".foregroundStyle(.primary)"))
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
