import Foundation
import Testing
@testable import DotJSON

/// 工具栏布局的结构性回归测试。
///
/// 该测试确保文件操作组前没有手工分隔符，避免编辑操作被隐藏后留下孤立的横线与留白。
struct ToolbarViewTests {
    /// 验证编辑工具栏组与文件操作组之间不使用会孤立显示的手工分隔符。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func toolbarDoesNotContainManualDivider() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ToolbarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(!source.contains("Divider()"))
    }

    /// 验证工具栏提供单文件 JSON 导入入口，并复用视图模型的加载与错误反馈契约。
    ///
    /// - Throws: 无法读取工具栏源码时抛出文件读取错误。
    @Test func toolbarProvidesJSONImportAction() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ToolbarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("Label(\"导入\", systemImage: \"square.and.arrow.down\")"))
        #expect(source.contains("private func importDocument()"))
        #expect(source.contains("panel.allowsMultipleSelection = false"))
        #expect(source.contains("try viewModel.loadDocument(from: url)"))
        #expect(source.contains("viewModel.reportFileError(error)"))
    }
}
