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

    /// 验证工具栏提供单文件 JSON 导入入口，并复用视图模型的加载与错误反馈契约。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func toolbarProvidesJSONImportAction() throws {
        let source = try toolbarSource()

        #expect(source.contains("toolbarIconButton(\"导入\", systemImage: \"square.and.arrow.down\")"))
        #expect(source.contains("private func importDocument()"))
        #expect(source.contains("panel.allowsMultipleSelection = false"))
        #expect(source.contains("try viewModel.loadDocument(from: url)"))
        #expect(source.contains("viewModel.reportFileError(error)"))
    }

    /// 验证导入和导出入口保留在同一个原生工具栏分组中。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func importAndExportShareToolbarGroup() throws {
        let source = try toolbarSource()

        #expect(source.contains("// ── 导入/导出 ──\n        ToolbarItem {"))
        #expect(source.contains("ControlGroup {"))
        #expect(source.contains("toolbarIconButton(\"导入\", systemImage: \"square.and.arrow.down\")"))
        #expect(source.contains("toolbarIconLabel(\"导出\", systemImage: \"square.and.arrow.up\")"))
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
    }

    /// 验证工具栏图标文字使用上下布局，并支持通过持久化开关隐藏文字。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func toolbarIconTitlesStackBelowIconsAndCanBeHidden() throws {
        let source = try toolbarSource()

        #expect(source.contains("@AppStorage(\"toolbarShowsText\")"))
        #expect(source.contains("private struct ToolbarIconLabelStyle: LabelStyle"))
        #expect(source.contains("Label(title, systemImage: systemImage)"))
        #expect(source.contains(".labelStyle(ToolbarIconLabelStyle(showsText: toolbarShowsText))"))
        #expect(source.contains("VStack(spacing: 2)"))
        #expect(source.contains("if showsText"))
        #expect(source.contains("configuration.title"))
        #expect(source.contains(".frame(width: 42, height: showsText ? 42 : 30"))
        #expect(!source.contains(".labelStyle(.titleAndIcon)"))
        #expect(!source.contains(".labelStyle(.iconOnly)"))
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

        #expect(source.contains("toolbarIconButton(\"导入\", systemImage: \"square.and.arrow.down\")"))
        #expect(source.contains("toolbarIconLabel(\"导出\", systemImage: \"square.and.arrow.up\")"))
        #expect(source.contains("Label(title, systemImage: systemImage)"))
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
