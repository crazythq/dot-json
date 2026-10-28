import DotJSONCore
import Foundation
import Testing
@testable import DotJSON

/// 工具栏布局的结构性回归测试。
///
/// 该测试确保文件操作组前没有手工分隔符，避免编辑操作被隐藏后留下孤立的横线与留白。
/// 搜索功能已下沉到左侧编辑器 ⌘F 和右侧树面板，工具栏不再承载搜索控件。
struct ToolbarViewTests {
    /// 读取真实工具栏源码，供结构性断言复用。
    ///
    /// - Returns: `ToolbarView.swift` 的完整源码文本。
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    private func toolbarSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ToolbarView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    /// 验证编辑工具栏组与文件操作组之间不使用会孤立显示的手工分隔符。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func toolbarDoesNotContainManualDivider() throws {
        let source = try toolbarSource()

        #expect(!source.contains("Divider()"))
    }

    /// 工具栏不再提供缩进下拉控件；各标签页的缩进状态仍由文档模型保留。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func toolbarDoesNotIncludeIndentPopUpButton() throws {
        let source = try toolbarSource()
        let popupURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/IndentPopUpButton.swift")

        #expect(!source.contains("IndentPopUpButton"))
        #expect(!source.contains("IndentPopUpButton.swift"))
        #expect(!FileManager.default.fileExists(atPath: popupURL.path))
        #expect(!source.contains("Picker(\"Indent\""))
        #expect(!source.contains("indentMenu(for:"))
    }

    @Test func allIndentOptionsHaveVisibleEnglishTitles() {
        for option in JSONFormatter.Indent.allCases {
            #expect(!option.label.isEmpty)
        }
        #expect(JSONFormatter.Indent.twoSpaces.label == "2 spaces")
        #expect(JSONFormatter.Indent.fourSpaces.label == "4 spaces")
        #expect(JSONFormatter.Indent.tab.label == "Tab")
    }

    @Test func formatAndMinifyUseStandaloneToolbarItemsWithSystemImages() throws {
        let source = try toolbarSource()

        #expect(source.contains("toolbarIconButton(\"Format\", systemImage: \"text.alignleft\")"))
        #expect(source.contains("toolbarIconButton(\"Minify\", systemImage: \"text.aligncenter\")"))
        #expect(source.contains("workspace.activeDocument?.format()"))
        #expect(source.contains("workspace.activeDocument?.minify()"))
        #expect(!source.contains("ToolbarItemGroup"))
        #expect(!source.contains("ControlGroup"))
        #expect(!source.contains("JSONTransformIconShape"))
        #expect(!source.contains("toolbarJSONTransformButton"))
    }

    /// 验证工具栏提供单文件 JSON 导入入口，并复用工作区的统一文档打开入口。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func toolbarProvidesJSONImportAction() throws {
        let source = try toolbarSource()

        #expect(source.contains("toolbarIconButton(\"Import\", systemImage: \"square.and.arrow.down\")"))
        #expect(source.contains("private func importDocument()"))
        #expect(source.contains("panel.allowsMultipleSelection = true"))
        #expect(source.contains("let ws = WorkspaceViewModel.shared"))
        #expect(source.contains("ws.openDocuments(panel.urls)"))
    }

    /// 验证导入和导出入口各自为独立 ToolbarItem（无 ControlGroup 半框）。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func importAndExportAreSeparateToolbarItems() throws {
        let source = try toolbarSource()

        #expect(source.contains("// ── 导入/导出 ──"))
        #expect(source.contains("toolbarIconButton(\"Import\", systemImage: \"square.and.arrow.down\")"))
        #expect(source.contains("toolbarIconLabel(\"Export\", systemImage: \"square.and.arrow.up\")"))
        #expect(!source.contains("ControlGroup {"))
    }

    /// 验证搜索已从工具栏移除，不再使用 toolbar principal 占位和原生搜索控件。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func toolbarNoLongerHostsSearch() throws {
        let source = try toolbarSource()

        #expect(!source.contains("ToolbarItem(placement: .principal)"))
        #expect(!source.contains("NativeToolbarSearchField"))
        #expect(!source.contains("fixedToolbarSearchField"))
    }

    /// 验证工具栏紧凑度量仍被保留，供其他控件使用。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func toolbarMetricsStillPresent() throws {
        let source = try toolbarSource()

        #expect(source.contains("private enum ToolbarMetrics"))
        #expect(source.contains("static let searchFieldWidth: CGFloat = 140"))
        #expect(source.contains("static let controlSpacing: CGFloat = 6"))
        #expect(source.contains("static let hideTextBelowWidth: CGFloat = 780"))
        #expect(source.contains("static let symbolPointSize: CGFloat = 14"))
        #expect(source.contains("static let iconOnlyHitSize: CGFloat = 28"))
    }

    /// 验证工具栏使用横向 titleAndIcon 与 padded iconOnly，并支持通过持久化开关隐藏文字。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func toolbarUsesHorizontalTitleAndIconOrPaddedIconOnly() throws {
        let source = try toolbarSource()

        #expect(source.contains("@AppStorage(\"toolbarShowsText\")"))
        #expect(source.contains("private var showsToolbarText: Bool"))
        #expect(source.contains("windowWidth >= ToolbarMetrics.hideTextBelowWidth"))
        #expect(source.contains("private struct ToolbarAdaptiveLabelStyle: LabelStyle"))
        #expect(source.contains("Label(title, systemImage: systemImage)"))
        #expect(source.contains(".labelStyle(ToolbarAdaptiveLabelStyle(showsText: showsToolbarText))"))
        #expect(source.contains("HStack(spacing: ToolbarMetrics.titleAndIconSpacing)"))
        #expect(source.contains("if showsText"))
        #expect(source.contains("configuration.title"))
        #expect(source.contains("ToolbarMetrics.iconOnlyPadding"))
        #expect(source.contains(".foregroundStyle(.primary)"))
        #expect(!source.contains("VStack(spacing: 2)"))
        #expect(!source.contains("ToolbarIconLabelStyle"))
    }

    /// 验证工具栏自定义标签保留原生 Label 语义，让 macOS 溢出菜单自己绘制居中文字。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func toolbarIconLabelsKeepNativeLabelSemanticsForOverflowMenuRows() throws {
        let source = try toolbarSource()

        #expect(source.contains("Label(title, systemImage: systemImage)"))
        #expect(source.contains("configuration.icon"))
        #expect(source.contains("configuration.title"))
        #expect(!source.contains(".alignmentGuide(.firstTextBaseline)"))
        #expect(!source.contains(".alignmentGuide(.lastTextBaseline)"))
    }

    /// 验证导入和导出入口仍作为真实按钮/菜单保留，不会被文本横排布局挤没。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func importAndExportUseCompactToolbarIconLabels() throws {
        let source = try toolbarSource()

        #expect(source.contains("toolbarIconButton(\"Import\", systemImage: \"square.and.arrow.down\")"))
        #expect(source.contains("toolbarIconLabel(\"Export\", systemImage: \"square.and.arrow.up\")"))
        #expect(source.contains("Label(title, systemImage: systemImage)"))
    }

    /// 验证主窗口会把可用宽度传给工具栏，以便先隐藏文字再依赖系统溢出。
    ///
    /// - Throws: 无法读取 ContentView 源码时抛出文件读取错误。
    @Test func contentViewPassesWindowWidthToToolbar() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("MainWindowContentWidthKey"))
        #expect(source.contains("ToolbarView(windowWidth: mainWindowContentWidth)"))
    }

    /// 验证左右分栏最小宽度为 10pt，便于拖到极窄仍可调回。
    ///
    /// - Throws: 无法读取 ContentView 源码时抛出文件读取错误。
    @Test func splitPanesAllowTenPointMinimumWidth() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("TextEditorView()\n                        .frame(minWidth: 10)"))
        #expect(source.contains("treePanel\n                        .frame(minWidth: 10)"))
    }

    /// 验证 ContentView 现在承载了树面板搜索框，包括 Enter 提交处理。
    ///
    /// - Throws: 无法读取 ContentView 源码时抛出文件读取错误。
    @Test func contentViewHostsTreeSearchWithEnterSubmit() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("NativeTreeSearchField"))
        #expect(source.contains("insertNewline(_:)"))
        #expect(source.contains("func control(_ control: NSControl, textView: NSTextView, doCommandBy"))
    }
}
