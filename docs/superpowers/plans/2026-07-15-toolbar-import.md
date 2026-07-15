# Toolbar Import Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 macOS 工具栏增加“导入”按钮，以系统文件选择框加载一个 JSON 文件。

**Architecture:** `ToolbarView` 负责展示按钮和调起 `NSOpenPanel`，保持与现有导出面板相同的 AppKit 边界。文件类型校验、读取、当前文件状态与最近文件更新全部复用 `EditorViewModel.loadDocument(from:)`；异常统一写入 `reportFileError(_:)`。

**Tech Stack:** Swift 5.9+、SwiftUI、AppKit、Swift Testing、Swift Package Manager。

## Global Constraints

- 目标平台为 macOS 14+，不得引入第三方依赖。
- 只允许选择单个 `.json` 文件。
- 导入不能创建新的文件读取或 JSON 校验逻辑，必须调用 `loadDocument(from:)`。
- 失败必须通过 `reportFileError(_:)` 呈现，不能静默吞掉错误。
- 不改变菜单“打开”、拖放、Finder/Dock 打开或导出行为。

---

### Task 1: 工具栏导入入口

**Files:**
- Modify: `mac/Tests/DotJSONTests/ToolbarViewTests.swift`
- Modify: `mac/Sources/DotJSON/Views/ToolbarView.swift`

**Interfaces:**
- Consumes: `EditorViewModel.loadDocument(from url: URL) throws` 与 `EditorViewModel.reportFileError(_ error: any Error)`。
- Produces: `ToolbarView` 的私有方法 `importDocument()`，由“导入”按钮调用。

- [ ] **Step 1: 写入失败测试**

在 `ToolbarViewTests` 内新增以下测试，验证源码中具备可见的导入入口，以及该入口复用唯一的文档加载契约：

```swift
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
```

- [ ] **Step 2: 运行测试并确认失败**

Run: `swift test --filter ToolbarViewTests/toolbarProvidesJSONImportAction`

Expected: FAIL，断言无法在当前 `ToolbarView.swift` 中找到导入按钮或 `importDocument()`。

- [ ] **Step 3: 实现最小导入操作**

在文件操作 `ToolbarItemGroup` 的清空按钮之前增加：

```swift
Button(action: { importDocument() }) {
    Label("导入", systemImage: "square.and.arrow.down")
}
.help("导入 JSON 文件")
```

并在 `ToolbarView` 中、`export(format:)` 之前新增：

```swift
/// 打开系统文件选择框，并将选中的 JSON 文件加载到当前编辑器。
private func importDocument() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        do {
            try viewModel.loadDocument(from: url)
        } catch {
            viewModel.reportFileError(error)
        }
    }
}
```

- [ ] **Step 4: 运行定向测试并确认通过**

Run: `swift test --filter ToolbarViewTests/toolbarProvidesJSONImportAction`

Expected: PASS，测试数为 1，失败数为 0。

- [ ] **Step 5: 运行完整回归测试**

Run: `swift test`

Expected: PASS，所有现有测试与新增工具栏测试均通过。

- [ ] **Step 6: 提交功能改动**

```bash
git add mac/Sources/DotJSON/Views/ToolbarView.swift mac/Tests/DotJSONTests/ToolbarViewTests.swift
git commit -m "feat(mac): 增加 JSON 导入按钮"
```
