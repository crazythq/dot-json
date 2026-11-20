# uTools 插件对齐 macOS 功能设计

## 目标

在现有 `utools/` 插件上，尽量对齐 DotJSON macOS 应用的**功能行为**（能做同样的事），并尽量少留技术债：模块边界清晰、核心逻辑可测、与 `DotJSONCore` 行为可对照。

验收标准：功能行为对齐即可；布局、快捷键、视觉可按 uTools 习惯调整。工具栏继续使用**文字按钮**，不对齐 macOS SF Symbols 图标工具栏。

交付方式：分阶段实现，每阶段可独立在 uTools 开发者模式验证与发布。

## 非目标

- 像素级 / 视觉对齐 macOS
- macOS 工具栏图标移植
- 插件窗口内拖放打开文件
- Finder / 系统文件关联、Dock 打开
- 自建 GitHub Releases 更新检查（走 uTools 插件更新渠道）
- 将 `dotjson` CLI 打进插件
- 为共享 Swift 代码改架构（继续 JS 对照移植）
- Raycast 扩展（另案）

## 约束与官方依据

| 约束 | 依据 / 说明 |
|------|-------------|
| 插件配置 | [plugin.json](https://www.u-tools.cn/docs/development/plugin-json.html)：`main` / `logo` / `preload` / `features` / `pluginSetting` |
| 单例与高度 | 现有 `pluginSetting.single: true`；`height: 680`；可用 `utools.setExpandHeight` 动态调整 |
| 功能指令上限 | 同一 `feature` 最多 5 个功能指令，超出忽略 |
| 文件匹配 | `cmds` 中 `type: "files"`；`minLength` / `maxLength` 为**文件个数**；`payload` 为 `MatchFile[]`（`path` / `name` / `isFile` / `isDirectory`） |
| 选中文本 | `type: "over"`；`payload` 为文本 |
| 生命周期 | [事件](https://www.u-tools.cn/docs/api-reference/events.html)：`onPluginReady` / `onPluginEnter` / `onPluginOut` |
| 打开 / 保存对话框 | [系统](https://www.u-tools.cn/docs/api-reference/system.html)：`showOpenDialog` → `string[] \| undefined`；`showSaveDialog` → `string \| undefined` |
| 写剪贴板 | [复制](https://www.u-tools.cn/docs/api-reference/copy.html)：`utools.copyText(text)` → `boolean` |
| 读剪贴板 | 官方无通用读 API；preload 内使用 Electron `clipboard.readText()`（[preload](https://www.u-tools.cn/docs/development/preload.html) 允许） |
| preload | CommonJS；Node **v20.19.1**；推荐统一命名空间；**禁止**把 `fs` 等整包直接暴露给前端 |
| 存储分层 | [数据存储](https://www.u-tools.cn/docs/development/storage.html) / [数据库](https://www.u-tools.cn/docs/api-reference/db.html)：简单配置用 `dbStorage`；大体量 / 高频会话用 `getPluginLocalDataPath()`；用户 JSON 文件走对话框路径 |

## 能力矩阵（macOS → uTools）

| 能力 | 判定 | 说明 |
|------|------|------|
| 双栏文本 + 树、面板分隔条调宽 | **能做** | 已有（面板分栏；与「文件拖放」无关） |
| 格式化 / 压缩 / 缩进 / 修复 | **能做** | 已有；契约测试锁齐 `DotJSONCore` |
| 粘贴自动格式化、清空、复制全文 | **能做** | 已有 |
| 打开 / 导出 | **能做** | 已有（`showOpenDialog` / `showSaveDialog`） |
| 保存 / 脏状态 / 另存为 | **能做** | 需补；路径经 preload 读写 |
| Python ↔ JSON | **能做** | 移植 core + 测试 |
| 树着色、展开收起、搜索 | **能做** | 已有 |
| 右键 Copy Key / Value / Path | **能做** | 已有 |
| 树 Expand All / Collapse All / Delete | **能做** | 需补；删节点写回编辑器；根不可删 |
| 编辑器查找 | **降级** | 简易查找条（上一项 / 下一项）；非 macOS 原生 Find Bar |
| 解析错误行号 + 行号标尺 | **降级** | 至少错误定位与提示；完整标尺不强制 |
| 多标签（改名 / 复制 / 关闭策略） | **能做** | 新建状态模型；上限对齐 mac **20** |
| 会话恢复 | **能做** | 正文快照写入插件本地数据目录 |
| 最近文件 | **能做** | 仅路径列表，上限 **10**（对齐 mac）；存 `dbStorage` |
| JSON Diff | **能做** | 移植 Diff 规则 + 简化双栏 UI |
| JSONL 浏览 | **能做** | 逻辑移植；文字入口；P4 起 `files` / 打开对话框扩展名增加 `jsonl` |
| 设置（默认缩进等） | **降级** | 插件内简单设置；不做独立可缩放 Settings 窗 |
| `files` 多文件匹配开多标签 | **能做** | 将 `maxLength` 从 1 提到与标签上限一致；超出截断并提示 |
| 对话框多选打开 | **能做** | `showOpenDialog` 可加 `multiSelections`（与窗口拖放无关） |
| 窗口内拖放开文件 | **不能做** | 不做 |
| Finder / 默认应用关联 | **不能做** | 无系统关联权限 |
| 启动检查 GitHub 更新 | **不能做** | 使用 uTools 插件更新渠道 |
| `dotjson` CLI | **不能做** | 属 mac 包产物 |
| macOS 工具栏图标 | **不能做** | 规格排除 |

## 架构

### 原则

1. **算法进 `lib/`**：可在 Node 下单测，不依赖 `window` / DOM / `utools`。
2. **状态进 `state/`**：工作区、文档、标签；无 DOM。
3. **UI 薄**：`app/`（或等价入口）只做绑定与渲染。
4. **preload 最小暴露**：读写用户指定路径、读剪贴板、读写插件本地数据目录中的会话文件。P0 将命名空间统一为官方推荐的 `window.services`（由现有 `window.dotjson` 迁移）；禁止扩大权限面，禁止把 `fs` 整包挂到 `window`。
5. **跨端一致靠契约测试**：同输入同输出对照 `DotJSONCore` / 现有 Swift 测试用例；UI 不保证快捷键与布局一致。

### 目标目录结构

```
utools/
├── plugin.json
├── preload.js
├── index.html
├── index.css
├── app/                    # UI 装配与事件（薄）
├── state/                  # Workspace / Document（无 DOM）
├── lib/
│   ├── json-core.js        # format / minify / repair / tree / path（已有，可拆分但不强制一次拆完）
│   ├── python-literal.js   # Python ↔ JSON
│   ├── json-diff.js        # Diff 规则（对照 DotJSONCore.JSONDiff）
│   └── jsonl.js            # JSONL 解析 / 导航
└── tests/                  # Node 契约测试
```

P0 先立边界与测试挂载点；后续阶段把新逻辑放进对应模块，避免继续堆厚单一 `index.js`。

## 数据流

### 启动与进入

1. `utools.onPluginReady`：加载偏好（`dbStorage`）+ 本地会话快照（若存在）。
2. `utools.onPluginEnter(action)` 按 `code` / `type` 分流：
   - `text`（功能指令）：进入插件；无外部 payload 时使用已恢复会话，否则空文档。
   - `over`：P1（单文档）将 `payload` 文本写入当前编辑器；P2 起**新建标签**装入该文本，避免覆盖未保存内容。
   - `files`：遍历 `MatchFile[]`，仅处理 `isFile === true` 且扩展名在允许列表内的项；达到标签上限则停止并提示截断。P0/P1 允许列表为 `json`；P4 起增加 `jsonl`。
3. `utools.onPluginOut`：将会话快照写入 `getPluginLocalDataPath()` 下固定文件名 `session-v1.json`（经 preload），避免仅存内存。

### 文件 I/O

- **打开**：`utools.showOpenDialog({ filters: [{ name: "JSON", extensions: ["json"] }], properties: ["openFile"] })`；P2 起 `properties` 增加 `multiSelections`；P4 起 `extensions` 增加 `jsonl`。
- **导出 / 另存为**：`utools.showSaveDialog({ filters: [{ name: "JSON", extensions: ["json"] }], ... })`。
- **保存**（已有路径）：preload 写回原路径；成功后清除脏标记。
- 用户取消对话框：无操作。
- 读写失败：状态栏错误；不假装已保存。

### 剪贴板

- 写出：优先 `utools.copyText`。
- 读入（粘贴并格式化）：preload `clipboard.readText()`。

### 存储分工

| 数据 | 存储 |
|------|------|
| 默认缩进、简易设置项 | `utools.dbStorage` |
| 最近文件路径列表（小） | `utools.dbStorage` |
| 多标签会话正文与元数据 | `utools.getPluginLocalDataPath()` + preload 文件 `session-v1.json` |
| 用户打开 / 导出的 JSON | 用户选定路径（对话框） |

说明：官方明确 `dbStorage` **不适用于**大量数据与高频写入；会话正文不得写入 `dbStorage`。

## 错误处理

| 场景 | 行为 |
|------|------|
| JSON 解析失败 | 状态栏错误；树区显示错误；保留编辑器原文 |
| 修复 / 转换失败 | 提示原因；保留原文 |
| 文件读写失败 | 状态栏错误；不更新「已保存」状态 |
| 删除树根节点 | 拒绝并提示 |
| 标签数达上限（20） | 提示；拒绝新建 / 再开 |
| 多文件匹配超出上限 | 只打开前 N 个并提示截断 |
| 对话框取消 | 静默无操作 |

## 分阶段计划

| 阶段 | 内容 | 可发布结果 |
|------|------|------------|
| **P0 地基** | 模块边界；现有 format / minify / repair / path 契约测试；工具栏保持文字按钮；preload 权限面梳理 | 可维护底座；行为锁死 |
| **P1 编辑对齐** | 保存 / 脏状态 / 另存为；Python ↔ JSON；树 Expand/Collapse All、Delete；简易编辑器查找；错误定位（降级） | 单文档体验对齐 |
| **P2 多文档** | 多标签 + 改名 / 复制 / 关闭；会话恢复（本地目录）；最近文件；`files.maxLength` 与对话框多选 | 多文档对齐；仍无拖放 |
| **P3 Diff** | `json-diff` 对照移植 + 双栏对比 / 应用 UI | Diff 可用 |
| **P4 JSONL + 设置** | JSONL 浏览；简单设置页（默认缩进等） | 功能面收束 |

不做清单（写死后不返工）：窗口拖放、Finder 关联、自建更新检查、CLI、mac 工具栏图标。

## 测试策略

1. **契约测试（必做）**：`utools/tests` 用 Node 加载 `lib/*`；用例输入输出对照 `mac` 侧 `DotJSONCore` 相关测试（format、minify、repair、JSON Path、Python 转换、Diff、JSONL）。
2. **手工验收**：每阶段在 uTools「开发者工具」加载本目录；清单写入该阶段 plan / README 小节。
3. **回归**：P0 起 CI 或本地脚本可跑 `node` 测试；不依赖启动 uTools GUI。

## 与现有代码的关系

- 保留已有 MVP：双栏、格式化 / 压缩 / 修复、粘贴格式化、打开 / 导出、树与搜索、右键复制、指令 `json` / `dotjson` / over / files。
- 在 P0 将逻辑从单体 `index.js` **迁出或划界**，避免在无边界情况下直接堆 P1–P4。
- `plugin.json` 的 `files.maxLength` 在 P2 再改为与标签上限一致；P0/P1 可保持 `1`。

## 成功标准

- 能力矩阵中「能做」项在对应阶段具备与 macOS 同等的用户可完成任务（输入输出语义一致）。
- 「降级」项有明确验收口径，不因追齐原生控件而反复改规格。
- 「不能做」项不出现在实现任务中。
- `lib/` 契约测试覆盖核心算法，且不依赖 DOM / `utools`。
- 会话与偏好存储符合官方分层，无「大会话进 dbStorage」技术债。
