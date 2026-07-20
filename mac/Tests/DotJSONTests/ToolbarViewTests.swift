import Foundation
import Testing
@testable import DotJSON

/// 工具栏布局的结构性回归测试。
///
/// 该测试确保文件操作组前没有手工分隔符，避免编辑操作被隐藏后留下孤立的横线与留白。
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

    /// 验证搜索框使用固定尺寸的原生控件，避免聚焦后被系统折叠成图标。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func searchFieldUsesFixedNativeToolbarControl() throws {
        let source = try toolbarSource()

        #expect(source.contains("ToolbarItem(placement: .principal)"))
        #expect(source.contains("NativeToolbarSearchField(text: $searchText)"))
        #expect(source.contains("private struct NativeToolbarSearchField: NSViewRepresentable"))
        #expect(source.contains("final class FixedToolbarSearchField: NSSearchField"))
        #expect(source.contains("override var intrinsicContentSize: NSSize"))
    }
}
