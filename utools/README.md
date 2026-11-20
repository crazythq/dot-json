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
│   └── document.js    # 单文档状态（文本 / 路径 / 脏标记 / 缩进）
├── lib/
│   ├── json-core.js       # 格式化 / 压缩 / 修复 / 树模型 / 错误行号
│   ├── python-literal.js  # JSON ↔ Python literal
│   └── tree-edit.js       # 树删节点、子孙 id 收集
├── tests/
│   ├── run-json-core.js       # json-core 契约测试
│   ├── run-document.js        # document 契约测试
│   ├── run-python-literal.js  # Python 转换契约测试
│   └── run-tree-edit.js       # 树编辑契约测试
├── logo.png           # 插件图标（256×256）
├── icon.png           # 1024 源图标
└── README.md
```

- **preload**：仅暴露 [`window.services`](preload.js)（读写字面路径、剪贴板、会话文件占位 `readSession` / `writeSession`）。不暴露 `fs` 整包，不使用已废弃的 `window.dotjson`。
- **入口**：`index.html` 按 `lib` → `state` → `app` 顺序加载脚本。

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
| 指令 | `json` / `dotjson`；选中文本 over；`.json` 文件匹配（**单文件**，`files.maxLength: 1`） | — |

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

## 未移植 / 后续阶段

P1 仍不包含多标签、Diff、JSONL、设置页、拖放等。完整能力矩阵与分阶段计划见：

[docs/superpowers/specs/2026-11-19-utools-feature-parity-design.md](../docs/superpowers/specs/2026-11-19-utools-feature-parity-design.md)

明确不做：窗口内拖放、Finder 关联、自建 GitHub 更新、CLI、`dotjson` 打进插件、macOS SF Symbols 工具栏图标。

## 契约测试

在 `utools/` 目录下：

```bash
cd utools
for f in tests/run-*.js; do node "$f" || exit 1; done
```

或逐个运行：`run-document.js`、`run-json-core.js`、`run-python-literal.js`、`run-tree-edit.js`。均应退出码 `0`，且不依赖 DOM / `utools`。

## P0 手工验收（uTools 开发者模式）

1. 加载本目录插件，指令 `json` 可打开。
2. 格式化 / 压缩 / 修复 / 缩进与改前一致。
3. 打开 / 导出文件可用。
4. 选中文本 →「用 DotJSON 打开」仍可用。
5. 选中 `.json` 文件匹配仍可用（单文件）。
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

## 本地 UI 预览（可选）

在浏览器直接打开 `index.html` 可看布局与示例 JSON（无 `utools` / preload 时文件对话框与剪贴板能力不可用）。完整能力需在 uTools 开发者模式加载。