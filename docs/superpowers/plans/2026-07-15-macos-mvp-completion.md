# macOS MVP Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐 DotJSON macOS 客户端最终确认版规格中的 12 项 MVP 功能，并产出可测试、可启动、可接收 Finder 文件的 `.app`。

**Architecture:** 保持现有 SwiftUI 外壳、AppKit 文本/树视图和 `EditorViewModel` 单文档状态结构。纯数据行为放入 ViewModel/Model 并使用 Swift Testing 验证；macOS 系统交互留在 Commands、SwiftUI View 与 AppKit 包装层，文件错误统一回传 ViewModel 展示。

**Tech Stack:** Swift 6、SwiftUI、AppKit、Observation、Swift Testing、Swift Package Manager；macOS 14+；零第三方依赖。

## Global Constraints

- MVP 范围固定为双面板、树浏览、纯文本编辑、格式化、压缩、2/4 空格或 Tab 缩进、粘贴自动格式化、复制、清空、保存/另存为/导出、Finder 文件关联、语法校验与错误定位。
- 文本编辑器固定深色，不增加语法高亮和主题切换。
- 不实现 V1 多标签、搜索增强、持久历史，也不实现 V2 JSONL 导航和 JSON Diff。
- 文件格式仅处理 `.json`；保留现有 V1/V2 预备代码但不扩展它们。
- 新增公共类型和方法写中文文档注释，错误不得静默吞掉。

---

### Task 1: 编辑与导出核心行为

**Files:**
- Modify: `mac/Sources/DotJSON/ViewModel/EditorViewModel.swift`
- Test: `mac/Tests/DotJSONTests/EditorViewModelTests.swift`

**Interfaces:**
- Consumes: `JSONFormatter.format(_:indent:)`、`JSONFormatter.minify(_:)`。
- Produces: `EditorViewModel.ExportFormat`、`export(to:format:)`、`reportFileError(_:)`，以及缩进改变后对有效 JSON 的实时重排。

- [ ] **Step 1: 写失败测试**

```swift
@Test func changingIndentReformatsValidDocumentImmediately() {
    let vm = EditorViewModel()
    vm.rawText = #"{"outer":{"value":1}}"#
    vm.format()
    vm.indent = .twoSpaces
    #expect(vm.rawText.contains("\n  \"outer\""))
    #expect(!vm.rawText.contains("\n    \"outer\""))
}

@Test func exportFormattedAndMinifiedVariants() throws {
    let vm = EditorViewModel()
    vm.rawText = #"{"b":2,"a":1}"#
    let formattedURL = temporaryURL("formatted.json")
    let minifiedURL = temporaryURL("minified.json")
    defer { remove(formattedURL, minifiedURL) }
    try vm.export(to: formattedURL, format: .formatted)
    try vm.export(to: minifiedURL, format: .minified)
    #expect(try String(contentsOf: formattedURL).contains("\n"))
    #expect(!(try String(contentsOf: minifiedURL)).contains("\n"))
}

@Test func reportedFileErrorIsVisibleWithoutFakeLineNumber() {
    let vm = EditorViewModel()
    vm.reportFileError(CocoaError(.fileReadNoSuchFile))
    #expect(vm.errorMessage != nil)
    #expect(vm.errorLineNumber == 0)
}
```

- [ ] **Step 2: 运行定向测试，确认因接口缺失或行为不符而失败**

Run: `cd mac && swift test --filter EditorViewModelTests`

Expected: FAIL，失败原因分别指向 `export`/`reportFileError` 不存在与缩进未实时生效。

- [ ] **Step 3: 实现最小核心行为**

```swift
enum ExportFormat: Sendable {
    case formatted
    case minified
}

var indent: JSONFormatter.Indent = .fourSpaces {
    didSet {
        guard indent != oldValue,
              let formatted = try? JSONFormatter.format(rawText, indent: indent) else { return }
        rawText = formatted
    }
}

func export(to url: URL, format: ExportFormat) throws {
    let output: String
    switch format {
    case .formatted:
        output = try JSONFormatter.format(rawText, indent: indent)
    case .minified:
        output = try JSONFormatter.minify(rawText)
    }
    try output.write(to: url, atomically: true, encoding: .utf8)
}

func reportFileError(_ error: any Error) {
    errorMessage = error.localizedDescription
    errorLineNumber = 0
}
```

- [ ] **Step 4: 重跑定向测试并确认通过**

Run: `cd mac && swift test --filter EditorViewModelTests`

Expected: PASS，EditorViewModelTests 无失败。

### Task 2: 系统粘贴、错误行号和行号标记

**Files:**
- Create: `mac/Sources/DotJSON/Views/LineNumberRulerView.swift`
- Modify: `mac/Sources/DotJSON/Views/TextEditorView.swift`
- Modify: `mac/Sources/DotJSON/ViewModel/EditorViewModel.swift`
- Test: `mac/Tests/DotJSONTests/EditorViewModelTests.swift`

**Interfaces:**
- Consumes: `EditorViewModel.pasteAndFormat(_:)`、`errorLineNumber`、`errorMessage`。
- Produces: `JSONTextView.onPaste`，以及随可见区域绘制并标红错误行的 `LineNumberRulerView`。

- [ ] **Step 1: 收紧错误行定位测试**

```swift
@Test func errorLineNumberPointsToInvalidSecondLine() {
    let vm = EditorViewModel()
    vm.rawText = "{\n  \"a\": bad\n}"
    #expect(vm.errorLineNumber == 2)
}
```

- [ ] **Step 2: 运行测试，确认现有错误文本解析不能稳定返回第 2 行时失败**

Run: `cd mac && swift test --filter errorLineNumberPointsToInvalidSecondLine`

Expected: 在现有 Foundation 错误格式下 FAIL；若当前 SDK 恰好通过，则添加非法第三行用例，确保字符索引换算边界被覆盖。

- [ ] **Step 3: 以 Foundation 错误中的字符索引计算行号，并接入标准粘贴**

```swift
final class JSONTextView: NSTextView {
    var onPaste: ((String) -> Void)?

    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }
        onPaste?(text)
    }
}
```

`TextEditorView` 创建 `JSONTextView`，把回调连接到 `pasteAndFormat(_:)`；滚动视图安装 `LineNumberRulerView`，在更新阶段同步 `errorLineNumber` 与 tooltip。行号尺只绘制可见字符范围，错误行使用红色，其余行使用灰色。

- [ ] **Step 4: 运行 EditorViewModel 测试并构建 UI 代码**

Run: `cd mac && swift test --filter EditorViewModelTests && swift build`

Expected: 测试通过且 SwiftUI/AppKit 代码编译成功。

### Task 3: 文件命令、导出菜单和拖放

**Files:**
- Modify: `mac/Sources/DotJSON/App/DotJSONCommands.swift`
- Modify: `mac/Sources/DotJSON/Views/ToolbarView.swift`
- Modify: `mac/Sources/DotJSON/Views/ContentView.swift`
- Modify: `mac/Sources/DotJSON/App/DotJSONApp.swift`

**Interfaces:**
- Consumes: `load(from:)`、`save(to:)`、`export(to:format:)`、`reportFileError(_:)`。
- Produces: Open/Save/Save As/Export 的非静默系统操作，以及 Finder/Dock URL 与窗口文件拖放入口。

- [ ] **Step 1: 将所有文件操作改为显式错误回传**

```swift
do {
    try viewModel.load(from: url)
} catch {
    viewModel.reportFileError(error)
}
```

Open Recent、Open、Save、Save As 和 Export 都采用相同模式；新文档上的 ⌘S 不禁用，而是进入 Save As。

- [ ] **Step 2: 添加导出格式菜单**

工具栏增加“导出”菜单，包含“格式化 JSON”和“压缩 JSON”；两个选项都打开 `NSSavePanel`，但调用不同的 `ExportFormat`，且导出不改变当前文件 URL 和修改状态。

- [ ] **Step 3: 接入 Finder/Dock 与窗口拖放**

```swift
.onOpenURL { url in
    do { try viewModel.load(from: url) }
    catch { viewModel.reportFileError(error) }
}
.onDrop(of: [.fileURL], isTargeted: nil) { providers in
    FileDropHandler.loadFirstJSON(from: providers, into: viewModel)
}
```

拖放只接受本地 `.json` URL；无法读取时展示错误，不改变已有文档。

- [ ] **Step 4: 构建确认系统交互层无编译错误**

Run: `cd mac && swift build`

Expected: Build complete，退出码 0。

### Task 4: `.app` 文件关联与可重复打包

**Files:**
- Modify: `mac/Info.plist`
- Modify: `mac/build-app.sh`

**Interfaces:**
- Consumes: SwiftPM 输出目录与 `Info.plist`。
- Produces: 注册 `public.json` Editor 角色、可以直接启动的 `DotJSON.app`。

- [ ] **Step 1: 让唯一 Info.plist 声明 JSON 文档类型**

在 `mac/Info.plist` 增加 `CFBundleDocumentTypes`，角色为 `Editor`、类型为 `public.json`、`LSHandlerRank` 为 `Default`。

- [ ] **Step 2: 消除打包脚本内重复 plist 和固定架构路径**

```bash
swift build
BUILD_DIR="$(swift build --show-bin-path)"
APP_DIR="$BUILD_DIR/DotJSON.app"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
```

资源 bundle 从动态 `BUILD_DIR` 复制；脚本继续使用 `set -e`，缺少二进制或图标时直接失败。

- [ ] **Step 3: 验证 plist 与 app bundle**

Run: `cd mac && plutil -lint Info.plist && ./build-app.sh && test -x "$(swift build --show-bin-path)/DotJSON.app/Contents/MacOS/DotJSON" && plutil -extract CFBundleDocumentTypes xml1 -o - "$(swift build --show-bin-path)/DotJSON.app/Contents/Info.plist"`

Expected: plist 为 OK、脚本退出码 0、app 可执行文件存在、输出包含 `public.json`。

### Task 5: MVP 回归、文档与提交

**Files:**
- Modify: `mac/README.md`（若不存在则 Create）
- Modify: `mac/Tests/DotJSONTests/EditorViewModelTests.swift`
- Modify: `mac/Tests/DotJSONTests/JSONFormatterTests.swift`

**Interfaces:**
- Consumes: Tasks 1-4 的全部 MVP 行为。
- Produces: MVP 功能清单、构建/运行说明和最终验证证据。

- [ ] **Step 1: 补齐 MVP 行为回归测试**

覆盖默认四空格、格式化、压缩、切换缩进实时重排、有效/无效粘贴、清空、加载、保存、两种导出、错误行定位和文件错误展示。已有等价测试保留，不重复测试 AppKit 实现细节。

- [ ] **Step 2: 更新 macOS 开发说明**

写明 `swift test`、`swift build`、`./build-app.sh`、生成 app 路径与 Finder 文件关联验证方式，并明确 V1/V2 不在本次范围。

- [ ] **Step 3: 运行完整验证**

Run: `cd mac && swift test && swift build && ./build-app.sh && plutil -lint Info.plist`

Expected: 全部测试 0 failures，两个构建命令退出码 0，plist 为 OK。

- [ ] **Step 4: 审核工作区并精确提交**

Run: `git status --short && git diff --check && git diff --stat && git diff --cached --stat`

只暂存 `mac/` 和本计划；保留用户已有的 `README.md`、`docs/json-viewer-proposal.html`、`raycast/`、`utools/` 改动。提交信息：`feat(mac): complete MVP workflow`。
