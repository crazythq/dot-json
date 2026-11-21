# DotJSON — uTools 插件

对照 macOS 版 DotJSON 核心能力实现的 uTools 插件：双面板编辑 + JSON 树浏览、格式化/压缩、修复、搜索与右键复制。

## 目录结构

```
utools/
├── plugin.json        # uTools 插件配置（入口 / 指令 / 高度）
├── preload.js         # Node/Electron 桥接（window.services）
├── index.html         # 插件 UI 入口
├── index.css          # 深色主题样式（对齐 Mac 应用配色）
├── app/
│   └── main.js        # UI 绑定、树渲染、utools 生命周期
├── state/
│   ├── document.js        # 单文档状态（文本 / 路径 / 脏标记 / 缩进 / 标题）
│   ├── preferences.js     # 默认缩进等偏好（P4）
│   └── workspace.js       # 多标签工作区、会话快照、最近文件列表（无 DOM）
├── lib/
│   ├── json-core.js       # 格式化 / 压缩 / 修复 / 树模型 / 错误行号
│   ├── json-diff.js       # 路径级 structured diff / apply（P3）
│   ├── jsonl.js           # JSONL 预解析 / 按行导航（P4）
│   ├── python-literal.js  # JSON ↔ Python literal
│   ├── safe-path.js       # 用户路径校验（preload 共用）
│   └── tree-edit.js       # 树删节点、子孙 id 收集
├── tests/
│   ├── run-json-core.js
│   ├── run-json-diff.js
│   ├── run-jsonl.js
│   ├── run-preferences.js
│   ├── run-document.js
│   ├── run-python-literal.js
│   ├── run-safe-path.js
│   ├── run-tree-edit.js
│   └── run-workspace.js
├── logo.png           # 插件图标（256×256）
├── icon.png           # 1024 源图标
└── README.md
```

- **preload**：仅暴露 [`window.services`](preload.js)（读写字面路径、剪贴板、会话文件占位 `readSession` / `writeSession`）。不暴露 `fs` 整包，不使用已废弃的 `window.dotjson`。
- **入口**：`index.html` 按 `lib` → `state`（`document` → `preferences` → `workspace`）→ `app` 顺序加载脚本。

## 在 uTools 中加载（开发模式）

1. 安装 [uTools](https://www.u-tools.cn/) 与「uTools 开发者工具」插件。
2. 打开「uTools 开发者工具」→ **新建项目** / **选择插件**。
3. 插件目录选本仓库的 `utools/`（需包含 `plugin.json`）。
4. 保存后，主搜索框输入 `json` 或 `dotjson` 即可打开。

也可：在开发者工具中直接「选择本地插件目录」指向本 `utools/` 文件夹。

## 功能清单（P0）

| 功能 | 说明 | 对应 Mac 应用 |
|------|------|----------------|
| 双面板 | 左文本编辑 / 右树浏览，可拖拽分栏 | ContentView 双栏 |
| 格式化 / 压缩 | 工具栏**文字按钮**；缩进 2 / 4 / Tab | FM-01 ~ FM-03 |
| 修复 | Markdown 围栏、True/False/None、尾逗号、单引号等保守修复 | JSONRepairer |
| 粘贴自动格式化 | 粘贴后尝试 format，失败则 repair 再 format | ED-05 |
| 清空 / 复制全文 | 工具栏 | TB-03 |
| 打开 / 导出文件 | 系统对话框；也可匹配 `.json` 文件进入 | FL-01 / FL-04 |
| 树浏览 + 类型着色 | string / number / bool·null / 容器 | TR-01 ~ TR-02 |
| 双击展开收起 | 容器节点 | TR-03 |
| 树搜索 | 防抖 200ms，↑↓ / Enter 切换命中并展开祖先 | SE-03 ~ SE-08 |
| 右键菜单 | Copy Key / Value / JSON Path | CM-01 ~ CM-03 |
| 指令 | `json` / `dotjson`；选中文本 over（P0 覆盖当前；P2 见下节）；`.json` 文件匹配 | — |

## 功能清单（P1）

| 功能 | 说明 |
|------|------|
| 保存 / 另存为 | 工具栏文字按钮；已关联路径时保存写入该路径 |
| 脏标记 | 标题栏或状态区提示未保存；保存成功后清除 |
| ⌘S | 焦点在编辑器时快捷保存（uTools / Electron 环境） |
| 转 Python / 转 JSON | 工具栏；Python 侧经 repair 再 format 为标准 JSON |
| 树 Expand All / Collapse All | 右键或工具区批量展开 / 收起 |
| 树 Delete | 删除选中节点并回写正文；**根节点不可删** |
| 编辑器查找 | 简易查找条：下一项 / 上一项 |
| 解析错误行号 | 能从引擎 message 提取位置时显示行号；否则仅原文（降级） |

## 功能清单（P2）

| 功能 | 说明 |
|------|------|
| 多标签 | 新建、切换、关闭、双击/菜单改名、复制标签 |
| 标签上限 | 最多 **20** 个；超出时提示 |
| 会话恢复 | 退出插件再进入，从 `session-v1.json` 恢复标签与激活项（**uTools 人工**） |
| 最近文件 | 最多 **10** 条路径，MRU，经 `utools.dbStorage` |
| 多文件打开 | 打开对话框多选；`plugin.json` 中 `files.maxLength: 20` |
| over 指令 | 选中文本「用 DotJSON 打开」→ **新建标签**装入，不覆盖当前未保存内容（**uTools 人工**） |

分阶段实现计划：[docs/superpowers/plans/2026-11-19-utools-feature-parity-p2.md](../docs/superpowers/plans/2026-11-19-utools-feature-parity-p2.md)

## 功能清单（P3）

| 功能 | 说明 |
|------|------|
| JSON Diff | 工具栏「对比」打开 Diff 面板 |
| 左右来源 | 选择标签或粘贴；默认左=当前标签、右=另一标签 |
| 差异列表 | 路径、kind（add/remove/change）、左右值摘要 |
| 单条应用 | 选中一行 → 应用到左 / 应用到右 |
| 全部应用 | 全部到左 / 全部到右；写回对应标签并标记脏 |
| 非法 JSON | 对比时一侧 parse 失败 → 状态栏报错（含左右标识） |
| 契约测试 | `node tests/run-json-diff.js` |

分阶段实现计划：[docs/superpowers/plans/2026-11-19-utools-feature-parity-p3.md](../docs/superpowers/plans/2026-11-19-utools-feature-parity-p3.md)

## 功能清单（P4）

| 功能 | 说明 |
|------|------|
| JSONL 浏览 | 工具栏「JSONL」或打开 `.jsonl` 进入；上一条 / 下一条 / 记录列表 |
| 当前记录 | 编辑器与树只展示当前记录；无效行可定位并提示 |
| 保存 | 写回多行 JSONL（记录用 `\n` 拼接；原空白行位置不保留；合法记录切走时 minify 回单行） |
| 会话 | 快照含 `jsonlMode`（记录列表与当前下标），恢复后仍为浏览模式 |
| 设置 | 工具栏「设置」；默认缩进存 `dbStorage`（`dotjson.defaultIndent`） |
| 默认缩进作用域 | **仅新建标签**；已打开文档的缩进不变 |
| 文件匹配 / 打开 | `plugin.json` 与打开对话框接受 `jsonl` |

分阶段实现计划：[docs/superpowers/plans/2026-11-21-utools-feature-parity-p4.md](../docs/superpowers/plans/2026-11-21-utools-feature-parity-p4.md)

## 明确不做

窗口内拖放、Finder 关联、自建 GitHub 更新、CLI、`dotjson` 打进插件、macOS SF Symbols 工具栏图标。完整矩阵见：

[docs/superpowers/specs/2026-11-19-utools-feature-parity-design.md](../docs/superpowers/specs/2026-11-19-utools-feature-parity-design.md)

## 契约测试

在 `utools/` 目录下：

```bash
cd utools
for f in tests/run-*.js; do node "$f" || exit 1; done
```

或逐个运行：`run-document.js`、`run-json-core.js`、`run-json-diff.js`、`run-jsonl.js`、`run-preferences.js`、`run-python-literal.js`、`run-safe-path.js`、`run-tree-edit.js`、`run-workspace.js`。均应退出码 `0`，且不依赖 DOM / `utools`。

## P0 手工验收（uTools 开发者模式）

1. 加载本目录插件，指令 `json` 可打开。
2. 格式化 / 压缩 / 修复 / 缩进与改前一致。
3. 打开 / 导出文件可用。
4. 选中文本 →「用 DotJSON 打开」仍可用。
5. 选中 `.json` 文件匹配仍可用（P2 起最多 20 个，见 P2 清单）。
6. 工具栏为文字按钮，无 macOS 图标栏。

## P1 验收清单

在 uTools 开发者模式中逐项确认（Node 项见下节）：

1. **保存 / 另存为 / ⌘S** — 有路径时保存写盘；另存为可选新路径；⌘S 触发保存。
2. **脏标记** — 编辑正文后出现未保存提示；保存成功后清除。
3. **转 Python / 转 JSON** — 合法 JSON 与可修复 Python 文本往返正确。
4. **树 Expand All / Collapse All / Delete** — 批量展开收起可用；Delete 更新正文；根节点不可删。
5. **编辑器查找** — 查找条上一项 / 下一项跳转正确。
6. **非法 JSON 错误** — 解析失败时，能提取行号则展示行号，否则显示原始错误（降级）。
7. **契约测试** — `node tests/run-*.js` 全部通过（见上节命令）。

## P2 验收清单

**Node（自动化）**

1. **契约测试** — 在 `utools/` 下执行 `for f in tests/run-*.js; do node "$f" || exit 1; done`，含 `run-workspace.js`，全部退出码 `0`。

**uTools 开发者模式（人工）**

2. **多标签** — 新建 / 切换 / 关闭 / 改名 / 复制标签行为正确。
3. **标签上限 20** — 第 21 个标签被拒绝并有提示。
4. **会话恢复** — 打开多个标签（含未保存、未关联路径）后退出插件再进入，标签与激活项恢复。
5. **最近文件** — 打开文件后出现在最近列表；超过 10 条时淘汰最旧项。
6. **多选打开** — 系统打开对话框可多选 JSON；从搜索匹配多个 `.json` 文件时各进一标签。
7. **over** — 选中文本用 DotJSON 打开时新建标签，不冲掉当前标签未保存内容。
8. **P1 回归** — 上节 P1 清单 1–6 仍通过。

## P3 验收清单

**Node（自动化）**

1. **契约测试** — 在 `utools/` 下执行 `for f in tests/run-*.js; do node "$f" || exit 1; done`，含 `run-json-diff.js`，全部退出码 `0`。

**uTools 开发者模式（人工）**

2. **打开对比** — 工具栏「对比」显示 Diff 面板；可关闭。
3. **差异列表** — 两标签（或左右文本）内容不同 JSON 时列出 path / kind。
4. **单条应用** — 选中一行应用到左或右后，对应标签正文更新且变脏；激活标签时编辑器同步。
5. **全部应用** — 全部到左 / 全部到右后内容与预期一致。
6. **非法 JSON** — 一侧非法 JSON 时对比失败并有可读错误提示。
7. **P2 回归** — 上节 P2 清单 2–8 仍通过。

## P4 验收清单

**Node（自动化）**

1. **契约测试** — 在 `utools/` 下执行 `for f in tests/run-*.js; do node "$f" || exit 1; done`，含 `run-jsonl.js`、`run-preferences.js`，全部退出码 `0`。

**uTools 开发者模式（人工）**

2. **打开 `.jsonl`** — 进入浏览模式；上一条 / 下一条 / 列表跳转正确。
3. **无效行** — 可定位且状态栏提示。
4. **保存** — 写回多行 JSONL。
5. **设置默认缩进** — 新建标签用新缩进；旧标签不变。
6. **files / 对话框** — 可匹配或打开 jsonl。
7. **P3 回归** — 上节 P3 清单 2–7 仍通过。

## 本地 UI 预览（可选）

在浏览器直接打开 `index.html` 可看布局与示例 JSON（无 `utools` / preload 时文件对话框与剪贴板能力不可用）。完整能力需在 uTools 开发者模式加载。