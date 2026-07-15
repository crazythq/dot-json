# Toolbar Separator Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除 macOS 工具栏在编辑操作缺失时留下的孤立分隔符和留白。

**Architecture:** 让格式化、压缩和缩进控件保持为一个原生 `ToolbarItemGroup`，把清空、粘贴、复制和导出移动到紧随其后的独立 `ToolbarItemGroup`。两个组之间不使用 `Divider()`，由 AppKit 负责相邻工具栏组的可见性与布局。

**Tech Stack:** Swift 6、SwiftUI、AppKit、Swift Testing、Swift Package Manager（macOS 14+）。

## Global Constraints

- 仅修改 `mac/Sources/DotJSON/Views/ToolbarView.swift`。
- 不改变格式化、压缩、缩进、清空、粘贴、复制、导出的既有行为、文案、快捷键和帮助提示。
- 不增加依赖，也不改动当前工作区内其他未提交文件。

---

### Task 1: 拆分原生工具栏组

**Files:**
- Modify: `mac/Sources/DotJSON/Views/ToolbarView.swift:10-60`
- Create: `mac/Tests/DotJSONTests/ToolbarViewTests.swift`
- Test: `mac/Tests/DotJSONTests/TextEditorViewTests.swift`（现有剪贴板行为回归）

**Interfaces:**
- Consumes: `EditorViewModel` 的 `format()`、`minify()`、`clear()`、`pasteAndFormat(_:)` 与 `rawText`。
- Produces: 不含手工 `Divider()` 的两个相邻 `ToolbarItemGroup`。

- [ ] **Step 1: 写入会失败的工具栏结构回归测试**

创建 `mac/Tests/DotJSONTests/ToolbarViewTests.swift`，读取实际工具栏源码并断言没有手工 `Divider()`；这项断言在当前实现中会失败，直接覆盖“分隔符不得在编辑组隐藏后独立出现”的结构约束。

```swift
import Foundation
import Testing
@testable import DotJSON

struct ToolbarViewTests {
    /// 验证编辑工具栏组与文件操作组之间不使用会孤立显示的手工分隔符。
    @Test func toolbarDoesNotContainManualDivider() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DotJSON/Views/ToolbarView.swift")

        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(!source.contains("Divider()"))
    }
}
```

- [ ] **Step 2: 运行新增测试，验证它因现有分隔符失败**

Run: `swift test --package-path mac --filter ToolbarViewTests.toolbarDoesNotContainManualDivider`

Expected: FAIL，失败断言显示 `ToolbarView.swift` 仍包含 `Divider()`。

- [ ] **Step 3: 删除会孤立显示的手工分隔符**

在 `Picker` 的帮助提示之后移除：

```swift
            Divider()
```

- [ ] **Step 4: 为文件操作创建独立组**

在原编辑操作组的闭合 `}` 后新增一个 `ToolbarItemGroup`，并把 `清空` 至 `导出` 的既有按钮原样放入其中：

```swift
        ToolbarItemGroup {
            Button(action: { viewModel.clear() }) {
                Label("清空", systemImage: "trash")
            }
            .help("清空编辑器全部内容")

            Button(action: { pasteFromClipboard() }) {
                Label("粘贴", systemImage: "doc.on.clipboard")
            }
            .help("从剪贴板粘贴并自动格式化 JSON")
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button(action: { copyToClipboard() }) {
                Label("复制", systemImage: "doc.on.doc")
            }
            .help("复制全部内容到剪贴板")

            Menu {
                Button("导出格式化 JSON") { export(format: .formatted) }
                Button("导出压缩 JSON") { export(format: .minified) }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .help("将当前有效 JSON 导出为格式化或压缩文件")
        }
```

- [ ] **Step 5: 编译并运行自动化回归测试**

Run: `swift test --package-path mac`

Expected: 所有 `DotJSONTests` 通过，特别是 `TextEditorViewTests.standardPasteRoutesClipboardTextThroughHandler` 与 `TextEditorViewTests.pasteDoesNothingWhenClipboardHasNoPlainText` 继续通过。

- [ ] **Step 6: 人工验证系统工具栏布局**

Run: `swift run --package-path mac DotJSON`

Expected: 默认布局下四个文件操作仍可用；在“自定工具栏”中隐藏编辑操作后，清空按钮左侧没有单独横线或空白工具栏项。

- [ ] **Step 7: 提交实现**

```bash
git add mac/Sources/DotJSON/Views/ToolbarView.swift mac/Tests/DotJSONTests/ToolbarViewTests.swift
git commit -m "fix: 移除工具栏孤立分隔符"
```
