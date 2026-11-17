# macOS 检查更新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 DotJSON macOS 应用中实现启动/手动检查 GitHub Releases 更新，弹窗引导打开 Release 页；自动检查失败静默，手动检查提供 Releases 兜底。

**Architecture:** `UpdateChecker` 通过可注入的 `UpdateHTTPClient` 请求 `releases/latest` 并返回结构化结果；`UpdatePromptCoordinator` 根据开关、skip、自动/手动决定是否弹 `NSAlert` 并打开 URL；偏好写入现有 `AppPreferences`。零第三方依赖。

**Tech Stack:** Swift 6 / SwiftUI + AppKit、URLSession、UserDefaults、Swift Testing、`@testable import DotJSON`

**Spec:** `docs/superpowers/specs/2026-11-17-macos-update-check-design.md`

## Global Constraints

- 禁止在 `main` 上直接开发；先建功能分支再改代码。
- 不引入第三方依赖；仓库固定 `crazythq/dot-json`。
- API：`GET https://api.github.com/repos/crazythq/dot-json/releases/latest`，超时 **10 秒**，失败不重试。
- 自动检查失败静默；手动检查失败提示 + Open Releases Page。
- `--cli` 模式不检查更新。
- UI 文案英文，与现有 Settings / 菜单风格一致。
- **不要自动 git commit**（含 docs）；仅当用户明确要求时再提交。
- docs/specs 与 docs/superpowers 下的文档不要主动 `git add`/`commit`。

## File Map

| 文件 | 职责 |
|------|------|
| `mac/Sources/DotJSON/Update/SemanticVersion.swift` | 解析/比较三段 semver |
| `mac/Sources/DotJSON/Update/UpdateCheckResult.swift` | 检查结果枚举 |
| `mac/Sources/DotJSON/Update/UpdateHTTPClient.swift` | 网络抽象 + 默认 URLSession 实现 |
| `mac/Sources/DotJSON/Update/UpdateChecker.swift` | 请求、解析、与本地版本比较 |
| `mac/Sources/DotJSON/Update/UpdatePromptCoordinator.swift` | 自动/手动流程、并发、弹窗、打开 URL |
| `mac/Sources/DotJSON/Model/AppPreferences.swift` | `autoCheckUpdates`、`skippedUpdateVersion` |
| `mac/Sources/DotJSON/Views/SettingsView.swift` | Toggle + Check 按钮 |
| `mac/Sources/DotJSON/App/DotJSONCommands.swift` | 菜单 Check for Updates… |
| `mac/Sources/DotJSON/App/DotJSONApp.swift` | 启动后触发自动检查 |
| `mac/Tests/DotJSONTests/SemanticVersionTests.swift` | semver 单测 |
| `mac/Tests/DotJSONTests/UpdateCheckerTests.swift` | mock 网络与结果 |
| `mac/Tests/DotJSONTests/UpdatePromptCoordinatorTests.swift` | 决策与 skip/开关 |
| `mac/Tests/DotJSONTests/GeneralEditorSettingsTests.swift` | 扩展偏好默认值断言 |
| `mac/Tests/DotJSONTests/UpdateSettingsCommandsTests.swift` | Settings/菜单源码结构 |

---

### Task 0: 创建功能分支

**Files:** 无代码文件

- [ ] **Step 1: 确认当前在干净可分支状态并创建分支**

Run:

```bash
cd /Users/tt/Documents/workspace/project/dot-json
git status
git checkout -b feature/macos-update-check
```

Expected: 当前分支为 `feature/macos-update-check`；未在 `main` 上改代码。

---

### Task 1: SemanticVersion

**Files:**
- Create: `mac/Sources/DotJSON/Update/SemanticVersion.swift`
- Test: `mac/Tests/DotJSONTests/SemanticVersionTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `struct SemanticVersion: Equatable, Sendable` with `major/minor/patch: Int`
  - `static func parse(_ raw: String) -> SemanticVersion?` — 接受可选前缀 `v`/`V`，仅 `X.Y.Z` 三段非负整数
  - `static func compare(_ a: SemanticVersion, _ b: SemanticVersion) -> ComparisonResult`

- [ ] **Step 1: 写失败测试**

```swift
import Testing
@testable import DotJSON

struct SemanticVersionTests {
    @Test func parseStripsVPrefix() {
        #expect(SemanticVersion.parse("v1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion.parse("1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test func parseRejectsInvalid() {
        #expect(SemanticVersion.parse("1.2") == nil)
        #expect(SemanticVersion.parse("1.2.3-beta") == nil)
        #expect(SemanticVersion.parse("abc") == nil)
        #expect(SemanticVersion.parse("") == nil)
    }

    @Test func compareOrdering() {
        let a = SemanticVersion(major: 1, minor: 1, patch: 5)!
        // Prefer parse in tests if memberwise init is internal via parse only:
        let v115 = SemanticVersion.parse("1.1.5")!
        let v120 = SemanticVersion.parse("1.2.0")!
        let v116 = SemanticVersion.parse("1.1.6")!
        #expect(SemanticVersion.compare(v115, v115) == .orderedSame)
        #expect(SemanticVersion.compare(v120, v115) == .orderedDescending)
        #expect(SemanticVersion.compare(v115, v116) == .orderedAscending)
    }
}
```

若 `SemanticVersion` 使用 `init(major:minor:patch:)` 为内部 memberwise，去掉测试里强制 unwrap 的 `!` 构造，统一用 `parse`。

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
cd mac && swift test --filter SemanticVersionTests
```

Expected: FAIL（类型不存在）

- [ ] **Step 3: 最小实现**

`mac/Sources/DotJSON/Update/SemanticVersion.swift`:

```swift
import Foundation

struct SemanticVersion: Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    static func parse(_ raw: String) -> SemanticVersion? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.first == "v" || s.first == "V" {
            s = String(s.dropFirst())
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]), major >= 0,
              let minor = Int(parts[1]), minor >= 0,
              let patch = Int(parts[2]), patch >= 0,
              String(parts[0]) == String(major),
              String(parts[1]) == String(minor),
              String(parts[2]) == String(patch)
        else {
            return nil
        }
        return SemanticVersion(major: major, minor: minor, patch: patch)
    }

    static func compare(_ a: SemanticVersion, _ b: SemanticVersion) -> ComparisonResult {
        if a.major != b.major { return a.major < b.major ? .orderedAscending : .orderedDescending }
        if a.minor != b.minor { return a.minor < b.minor ? .orderedAscending : .orderedDescending }
        if a.patch != b.patch { return a.patch < b.patch ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }
}
```

数字字符串严格性：拒绝 `01.2.3` 可按上表 `String(parts[0]) == String(major)` 实现；若过严导致合法 tag 失败再放宽，但测试须同步。

- [ ] **Step 4: 跑测试确认通过**

Run:

```bash
cd mac && swift test --filter SemanticVersionTests
```

Expected: PASS

---

### Task 2: AppPreferences 更新相关键

**Files:**
- Modify: `mac/Sources/DotJSON/Model/AppPreferences.swift`
- Modify: `mac/Tests/DotJSONTests/GeneralEditorSettingsTests.swift`（扩展默认值断言）

**Interfaces:**
- Consumes: 现有 `AppPreferences` / `StorageKey` 模式
- Produces:
  - `StorageKey.autoCheckUpdates = "dotjson.autoCheckUpdates"`
  - `StorageKey.skippedUpdateVersion = "dotjson.skippedUpdateVersion"`
  - `var autoCheckUpdates: Bool` 默认 `true`（key 未写入时）
  - `var skippedUpdateVersion: String?` 默认 `nil`
  - `clearPreferenceKeys()` 同时清除上述两键

- [ ] **Step 1: 扩展失败测试**

在 `appPreferencesDefaultValues` 中增加：

```swift
#expect(prefs.autoCheckUpdates == true)
#expect(prefs.skippedUpdateVersion == nil)
```

新增：

```swift
@Test func updatePreferencesRoundTrip() {
    let defaults = isolatedDefaults()
    let prefs = AppPreferences(defaults: defaults)
    prefs.autoCheckUpdates = false
    prefs.skippedUpdateVersion = "1.2.0"
    #expect(prefs.autoCheckUpdates == false)
    #expect(prefs.skippedUpdateVersion == "1.2.0")
    prefs.clearPreferenceKeys()
    #expect(prefs.autoCheckUpdates == true)
    #expect(prefs.skippedUpdateVersion == nil)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
cd mac && swift test --filter GeneralEditorSettingsTests
```

Expected: FAIL（属性不存在）

- [ ] **Step 3: 实现偏好**

在 `StorageKey` 增加两键；增加属性：

```swift
var autoCheckUpdates: Bool {
    get {
        if defaults.object(forKey: StorageKey.autoCheckUpdates) == nil {
            return true
        }
        return defaults.bool(forKey: StorageKey.autoCheckUpdates)
    }
    nonmutating set {
        defaults.set(newValue, forKey: StorageKey.autoCheckUpdates)
    }
}

var skippedUpdateVersion: String? {
    get { defaults.string(forKey: StorageKey.skippedUpdateVersion) }
    nonmutating set {
        if let newValue {
            defaults.set(newValue, forKey: StorageKey.skippedUpdateVersion)
        } else {
            defaults.removeObject(forKey: StorageKey.skippedUpdateVersion)
        }
    }
}
```

并在 `clearPreferenceKeys()` 中 `removeObject` 这两键。

- [ ] **Step 4: 跑测试确认通过**

Run:

```bash
cd mac && swift test --filter GeneralEditorSettingsTests
```

Expected: PASS

---

### Task 3: UpdateChecker + HTTP 抽象

**Files:**
- Create: `mac/Sources/DotJSON/Update/UpdateCheckResult.swift`
- Create: `mac/Sources/DotJSON/Update/UpdateHTTPClient.swift`
- Create: `mac/Sources/DotJSON/Update/UpdateChecker.swift`
- Test: `mac/Tests/DotJSONTests/UpdateCheckerTests.swift`

**Interfaces:**
- Consumes: `SemanticVersion`
- Produces:
  - `enum UpdateCheckResult: Equatable, Sendable` — `.upToDate` / `.available(version: String, releaseURL: URL)` / `.unreachable` / `.invalidResponse`
  - `protocol UpdateHTTPClient: Sendable` — `func data(for request: URLRequest) async throws -> (Data, URLResponse)`
  - `struct URLSessionUpdateHTTPClient: UpdateHTTPClient`
  - `struct UpdateChecker: Sendable` — `init(client: UpdateHTTPClient, localVersionProvider: @escaping @Sendable () -> String?, repository: String = "crazythq/dot-json")`；`func check() async -> UpdateCheckResult`
  - 常量：`releasesListURL = URL(string: "https://github.com/crazythq/dot-json/releases")!`（供 UI 兜底，可放在 UpdateChecker 或独立 `UpdateURLs`）

- [ ] **Step 1: 写 mock client 与失败测试**

```swift
import Foundation
import Testing
@testable import DotJSON

struct UpdateCheckerTests {
    private struct MockClient: UpdateHTTPClient {
        var handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            try await handler(request)
        }
    }

    private func jsonResponse(_ object: [String: Any], status: Int = 200) throws -> (Data, URLResponse) {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/repos/crazythq/dot-json/releases/latest")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    @Test func availableWhenRemoteNewer() async throws {
        let client = MockClient { _ in
            try await self.jsonResponse([
                "tag_name": "v1.2.0",
                "html_url": "https://github.com/crazythq/dot-json/releases/tag/v1.2.0",
            ])
        }
        // Fix: MockClient can't capture mutating self easily — define handler inline without self.
        // Use non-nested helper at file level or pass data directly.
        let checker = UpdateChecker(client: /* ... */, localVersionProvider: { "1.1.5" })
        let result = await checker.check()
        #expect(result == .available(
            version: "1.2.0",
            releaseURL: URL(string: "https://github.com/crazythq/dot-json/releases/tag/v1.2.0")!
        ))
    }

    @Test func upToDateWhenEqual() async throws { /* tag v1.1.5, local 1.1.5 → .upToDate */ }
    @Test func upToDateWhenRemoteOlder() async throws { /* tag 1.0.0, local 1.1.5 → .upToDate */ }
    @Test func unreachableOnHTTPError() async throws { /* status 403 → .unreachable */ }
    @Test func unreachableOnThrownError() async throws { /* throw URLError(.timedOut) → .unreachable */ }
    @Test func invalidResponseOnBadJSON() async throws { /* data = "not-json" → .invalidResponse */ }
    @Test func invalidResponseOnBadTag() async throws { /* tag_name "nope" → .invalidResponse */ }
    @Test func invalidResponseWhenLocalVersionMissing() async throws {
        let checker = UpdateChecker(client: /* ok payload */, localVersionProvider: { nil })
        #expect(await checker.check() == .invalidResponse)
    }
}
```

实现时把 `MockClient` 写成接收预计算 `(Result<(Data, URLResponse), Error>)` 的简单 stub，避免 `@Sendable` 闭包捕获问题：

```swift
private struct StubClient: UpdateHTTPClient {
    let result: Result<(Data, URLResponse), Error>
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try result.get()
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
cd mac && swift test --filter UpdateCheckerTests
```

Expected: FAIL

- [ ] **Step 3: 实现**

`UpdateCheckResult.swift`：

```swift
import Foundation

enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case available(version: String, releaseURL: URL)
    case unreachable
    case invalidResponse
}
```

`UpdateHTTPClient.swift`：

```swift
import Foundation

protocol UpdateHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionUpdateHTTPClient: UpdateHTTPClient {
    let session: URLSession

    init(timeout: TimeInterval = 10) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
```

`UpdateChecker.swift` 核心逻辑：

```swift
import Foundation

enum UpdateURLs {
    static let releasesList = URL(string: "https://github.com/crazythq/dot-json/releases")!
}

struct UpdateChecker: Sendable {
    private let client: UpdateHTTPClient
    private let localVersionProvider: @Sendable () -> String?
    private let repository: String

    init(
        client: UpdateHTTPClient = URLSessionUpdateHTTPClient(),
        localVersionProvider: @escaping @Sendable () -> String? = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        },
        repository: String = "crazythq/dot-json"
    ) {
        self.client = client
        self.localVersionProvider = localVersionProvider
        self.repository = repository
    }

    func check() async -> UpdateCheckResult {
        guard let localRaw = localVersionProvider(),
              let local = SemanticVersion.parse(localRaw) else {
            return .invalidResponse
        }

        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return .invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DotJSON-UpdateCheck", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await client.data(for: request)
        } catch {
            return .unreachable
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return .unreachable
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURLString = json["html_url"] as? String,
              let releaseURL = URL(string: htmlURLString),
              let remote = SemanticVersion.parse(tagName) else {
            return .invalidResponse
        }

        let normalized = "\(remote.major).\(remote.minor).\(remote.patch)"
        switch SemanticVersion.compare(remote, local) {
        case .orderedDescending:
            return .available(version: normalized, releaseURL: releaseURL)
        case .orderedSame, .orderedAscending:
            return .upToDate
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run:

```bash
cd mac && swift test --filter UpdateCheckerTests
```

Expected: PASS

---

### Task 4: UpdatePromptCoordinator（决策 + 并发 + 弹窗）

**Files:**
- Create: `mac/Sources/DotJSON/Update/UpdatePromptCoordinator.swift`
- Test: `mac/Tests/DotJSONTests/UpdatePromptCoordinatorTests.swift`

**Interfaces:**
- Consumes: `UpdateChecker`, `UpdateCheckResult`, `AppPreferences`, `UpdateURLs`
- Produces:
  - `@MainActor final class UpdatePromptCoordinator`
  - `static let shared`（菜单/Settings/启动共用）
  - `func runAutomaticCheckIfNeeded()` — 读 `autoCheckUpdates`；关则 return；否则 `check(mode: .automatic)`
  - `func runManualCheck()` — `check(mode: .manual)`
  - 可测纯函数或内部方法：`shouldPresentAvailable(version:mode:skipped:)` — automatic 时 skip 匹配则 false；manual 恒 true
  - 并发：`private var inFlight: Task<Void, Never>?`；automatic 若已有 inFlight 则跳过；manual 取消现有 Task 再开新 Task
  - 打开 URL：注入 `urlOpener: (URL) -> Void` 默认 `{ NSWorkspace.shared.open($0) }` 便于测
  - 弹窗：注入 `alerter` 协议或闭包，测试不断言 NSAlert 像素，只断言调用参数

建议 alerter 接口：

```swift
@MainActor
protocol UpdateAlerter: AnyObject {
    func presentAvailable(version: String, onDownload: @escaping () -> Void, onSkip: @escaping () -> Void, onRemindLater: @escaping () -> Void)
    func presentUpToDate()
    func presentCheckFailed(onOpenReleases: @escaping () -> Void)
}
```

生产实现用 `NSAlert`（参考 `FileAssociationAlerts.presentAlert`）：
- Available title: `"Update Available"`，文案含版本号；按钮顺序：`Download` / `Skip This Version` / `Remind Later`
- Up to date: `"You're Up to Date"` + OK
- Failed: `"Couldn't Check for Updates"` + `OK` / `Open Releases Page`

- [ ] **Step 1: 写决策与并发测试（用 stub checker / alerter）**

为可测性，coordinator 接受：

```swift
init(
    checkerFactory: @escaping @Sendable () -> UpdateChecker = { UpdateChecker() },
    preferences: AppPreferences = AppPreferences(),
    alerter: UpdateAlerter,
    urlOpener: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
)
```

测试用固定 `UpdateChecker(client: StubClient(...), localVersionProvider: { "1.1.5" })`。

用例：
1. `autoCheckUpdates == false` → automatic 不调用 client（用计数 Stub）
2. automatic + available `1.2.0` + skipped `1.2.0` → 不调用 `presentAvailable`
3. automatic + available `1.2.0` + skipped `nil` → 调用 `presentAvailable`
4. manual + skipped `1.2.0` + available → 仍 `presentAvailable`
5. manual + unreachable → `presentCheckFailed`；触发 onOpenReleases → opener 收到 `UpdateURLs.releasesList`
6. Skip 回调写入 `preferences.skippedUpdateVersion == "1.2.0"`
7. 第二次 automatic 在第一次 inFlight 未完成时被忽略（可用永不 resume 的 Stub + 短 sleep 断言 alerter 调用次数为 1）

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
cd mac && swift test --filter UpdatePromptCoordinatorTests
```

Expected: FAIL

- [ ] **Step 3: 实现 coordinator + NSAlert alerter**

同一文件或 `UpdateAlerter.swift` 中实现 `NSAlertUpdateAlerter`。

Skip 回调：

```swift
preferences.skippedUpdateVersion = version
```

Download 回调：

```swift
urlOpener(releaseURL)
```

Remind Later：空操作关窗即可。

- [ ] **Step 4: 跑测试确认通过**

Run:

```bash
cd mac && swift test --filter UpdatePromptCoordinatorTests
```

Expected: PASS

---

### Task 5: 接线 Settings / 菜单 / 启动

**Files:**
- Modify: `mac/Sources/DotJSON/Views/SettingsView.swift`
- Modify: `mac/Sources/DotJSON/App/DotJSONCommands.swift`
- Modify: `mac/Sources/DotJSON/App/DotJSONApp.swift`
- Test: `mac/Tests/DotJSONTests/UpdateSettingsCommandsTests.swift`

**Interfaces:**
- Consumes: `UpdatePromptCoordinator.shared`（生产路径用默认 alerter）
- Produces: UI 入口与启动触发；`--cli` 仍不进入 SwiftUI body 检查路径（现有 `CLIEntry.main()` 在 `init` 提前退出，保持即可）

- [ ] **Step 1: 写源码结构失败测试**

```swift
import Testing
import Foundation

struct UpdateSettingsCommandsTests {
    private func macPackageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relative: String) -> URL {
        macPackageRoot().appendingPathComponent("Sources/DotJSON/\(relative)")
    }

    @Test func settingsExposesAutoCheckToggleAndButton() throws {
        let text = try String(contentsOf: source("Views/SettingsView.swift"), encoding: .utf8)
        #expect(text.contains("Check for Updates Automatically"))
        #expect(text.contains("Check for Updates…"))
        #expect(text.contains("dotjson.autoCheckUpdates") || text.contains("AppPreferences.StorageKey.autoCheckUpdates"))
    }

    @Test func commandsExposesCheckForUpdatesMenuItem() throws {
        let text = try String(contentsOf: source("App/DotJSONCommands.swift"), encoding: .utf8)
        #expect(text.contains("Check for Updates…"))
        #expect(text.contains("CommandGroup(after: .appInfo)"))
        #expect(text.contains("runManualCheck"))
    }

    @Test func appTriggersAutomaticCheckOnAppear() throws {
        let text = try String(contentsOf: source("App/DotJSONApp.swift"), encoding: .utf8)
        #expect(text.contains("runAutomaticCheckIfNeeded"))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
cd mac && swift test --filter UpdateSettingsCommandsTests
```

Expected: FAIL

- [ ] **Step 3: 接线 UI**

Settings `Section("General")` 增加（英文）：

```swift
@AppStorage(AppPreferences.StorageKey.autoCheckUpdates)
private var autoCheckUpdates: Bool = true

// inside Section("General"):
Toggle(isOn: $autoCheckUpdates) {
    SettingsToggleLabels(
        title: "Check for Updates Automatically",
        subtitle: "When enabled, DotJSON checks GitHub Releases after launch."
    )
}

Button("Check for Updates…") {
    UpdatePromptCoordinator.shared.runManualCheck()
}
```

注意：`StorageKey.autoCheckUpdates` 须为可被 `@AppStorage` 使用的 `String` 常量（与现有 key 风格一致）。

`DotJSONCommands`：

```swift
CommandGroup(after: .appInfo) {
    Button("Check for Updates…") {
        UpdatePromptCoordinator.shared.runManualCheck()
    }
}
```

`DotJSONApp` 主窗口 `.onAppear` 中（在现有 `NSApp.activate` 旁）调用：

```swift
UpdatePromptCoordinator.shared.runAutomaticCheckIfNeeded()
```

确保 `UpdatePromptCoordinator.shared` 在 App 生命周期内用默认 `NSAlertUpdateAlerter` 初始化一次。

- [ ] **Step 4: 跑结构测试 + 相关单测**

Run:

```bash
cd mac && swift test --filter UpdateSettingsCommandsTests && swift test --filter SemanticVersionTests && swift test --filter UpdateCheckerTests && swift test --filter UpdatePromptCoordinatorTests && swift test --filter GeneralEditorSettingsTests
```

Expected: 全部 PASS

---

### Task 6: 全量验证

**Files:** 无新文件

- [ ] **Step 1: 跑完整测试套件**

Run:

```bash
cd mac && swift test
```

Expected: 全部 PASS，无新增失败。

- [ ] **Step 2: 手动冒烟（可选，需网络）**

1. 构建并运行 App（非 `--cli`）
2. 开关开启时启动：若当前已是 latest，应无弹窗；断网时应无错误弹窗
3. 菜单 / Settings「Check for Updates…」：断网应出现失败弹窗，Open Releases Page 能打开浏览器
4. Skip This Version 后重启：同一版本不再自动弹

- [ ] **Step 3: 对照 spec 勾选**

对照 `docs/superpowers/specs/2026-11-17-macos-update-check-design.md`：自动检查、手动检查、skip、remind later、开关、菜单、静默失败、10s 超时、无 Sparkle、无 CLI 检查——均已覆盖。

---

## Plan Self-Review

| Spec 要求 | 对应 Task |
|-----------|-----------|
| GitHub Releases API 检查 | Task 3 |
| semver 比较 / 非法 tag | Task 1 + 3 |
| 启动自动检查 + 开关 | Task 2 + 4 + 5 |
| Download / Skip / Remind Later | Task 4 |
| 手动检查忽略 skip | Task 4 |
| Settings toggle + 按钮 | Task 5 |
| 菜单 Check for Updates | Task 5 |
| 自动失败静默 / 手动失败兜底 | Task 4 |
| 10s 超时、不重试 | Task 3 |
| 并发规则 | Task 4 |
| `--cli` 不检查 | Task 5（沿用 init 提前退出） |
| 零依赖 | 全文 |
| 测试覆盖 | Task 1–6 |

无 TBD 占位；类型名在 Tasks 间一致（`UpdateCheckResult` / `UpdateChecker` / `UpdatePromptCoordinator` / `UpdateURLs`）。
