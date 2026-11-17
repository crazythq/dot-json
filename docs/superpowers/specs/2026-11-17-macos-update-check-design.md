# macOS 启动检查更新设计

## 目标

在 DotJSON macOS 应用中提供「检查更新」能力：启动时（可开关）查询 GitHub Releases，发现新版本后弹窗引导用户打开 Release 页面自行下载；并在菜单与 Settings 中提供手动检查入口。不做应用内下载替换（无 Developer ID / 公证前提下不可靠）。

## 范围

- 每次启动：若 `autoCheckUpdates == true`，后台检查一次最新 Release。
- 发现新版本且未跳过该版本时弹窗：
  - **Download** — 打开该 Release 的 `html_url`
  - **Skip This Version** — 记住该版本，自动检查不再提示
  - **Remind Later** — 仅关闭弹窗，下次启动仍可提示
- Settings → General：
  - Toggle：`Check for Updates Automatically`（默认开启）
  - Button：`Check for Updates…`
- 应用菜单：`Check for Updates…`（About 附近）
- 手动检查不受自动检查开关影响；即使某版本曾 Skip，手动检查仍可再次提示该版本
- 网络/GitHub 不可达时的错误处理（见下文）

## 非目标

- Sparkle / 应用内静默下载与替换
- Developer ID 签名、公证、appcast
- Homebrew Cask 更新
- GitHub 镜像、代理、自动重试队列
- CLI（`--cli`）路径下的更新检查
- uTools / Raycast 端更新

## 架构

三块职责分离：

| 模块 | 职责 |
|------|------|
| `UpdateChecker` | 请求 GitHub API、解析、与本地版本比较；返回结构化结果，不弹 UI |
| `UpdatePromptCoordinator` | 决定是否弹窗（开关、skip、自动 vs 手动）；展示弹窗与打开 URL |
| `AppPreferences` | 持久化 `autoCheckUpdates`、`skippedUpdateVersion` |

仓库固定为 `crazythq/dot-json`。不引入第三方依赖。

### API

```
GET https://api.github.com/repos/crazythq/dot-json/releases/latest
```

- 使用 `URLSession`，请求超时 **10 秒**
- 单次请求；失败不重试、不排队
- 从响应读取 `tag_name`、`html_url`
- `tag_name` 去掉可选前缀 `v` 后得到规范化版本字符串，与本地 `CFBundleShortVersionString` 做 semver（三段数字）比较
- GitHub `releases/latest` 本身排除 draft / prerelease；客户端不再额外过滤
- 并发：同一时刻只允许一次进行中的检查；后到的自动检查直接跳过，手动检查可取消/取代进行中的自动检查

### 结果枚举（示意）

- `.upToDate`
- `.available(version: String, releaseURL: URL)` — `version` 为去掉 `v` 后的规范化字符串
- `.unreachable` — 超时、无网络、DNS、HTTP 非 2xx（含 403/429）等
- `.invalidResponse` — JSON 损坏、缺字段、tag 非合法 semver

本地版本读取失败时，自动检查静默跳过；手动检查走失败提示。

## 交互与数据流

### 启动自动检查

1. 主窗口出现后异步检查（不阻塞 UI）
2. 仅当结果为 `.available` 且 `version != skippedUpdateVersion` 时弹窗
3. `.upToDate` / `.unreachable` / `.invalidResponse` → 静默结束
4. `autoCheckUpdates == false` → 不发起请求
5. `--cli` 模式 → 不检查

### 手动检查（菜单 + Settings）

| 结果 | 反馈 |
|------|------|
| `.available` | 三按钮弹窗（忽略 skip） |
| `.upToDate` | 「You're up to date」 |
| `.unreachable` / `.invalidResponse` | 「Couldn't check for updates」+ **Open Releases Page**（打开 `https://github.com/crazythq/dot-json/releases`） |

### 偏好键

| Key | 类型 | 默认 |
|-----|------|------|
| `dotjson.autoCheckUpdates` | Bool | `true`（未写入时） |
| `dotjson.skippedUpdateVersion` | String? | `nil`（存规范化版本，如 `1.2.0`，不含 `v`） |

菜单项使用 `CommandGroup(after: .appInfo)` 插入 `Check for Updates…`。

## 错误处理原则

GitHub 在部分网络环境下经常不可达，按一等公民处理：

- **自动检查**：任何失败静默；不弹错误、不 toast、不重试
- **手动检查**：明确失败文案 + 浏览器打开 Releases 列表页作为兜底
- 不区分超时 / 403 / 坏 JSON 给用户看细节（统一「无法检查」）；测试侧可区分枚举
- 不把成功结果缓存到磁盘；每次启动或手动触发重新请求即可

## 实现边界

- `UpdateChecker` 可注入 `URLSession`（或协议）以便单测 mock
- 弹窗风格与现有 `FileAssociationAlerts` 一致，优先 AppKit `NSAlert`，避免与 Settings 窗焦点纠缠
- 菜单项挂在现有 `DotJSONCommands`
- Settings UI 文案与现有 General/Editor 分区英文风格一致
- 不修改发布流水线；继续使用现有 GitHub Release 产物

## 验证

- 单测：semver 比较（相等 / 新 / 旧 / 非法）
- 单测：skip 对自动检查生效、对手动检查不生效
- 单测：开关关闭时启动路径不请求（可通过 spy/mock session 断言）
- 单测：mock 超时、403、坏 JSON、有更新、无更新 → 对应结果
- 源码结构测试：Settings 含 toggle + 按钮；Commands 含菜单项
- 跑完整 `swift test`
