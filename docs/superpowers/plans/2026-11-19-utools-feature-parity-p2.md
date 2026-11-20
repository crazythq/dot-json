# uTools Feature Parity P2（多文档）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 uTools 插件增加多标签工作区：新建/激活/关闭/改名/复制、会话恢复（`session-v1.json`）、最近文件（最多 10）、`files.maxLength=20` 与打开对话框多选；`over` 改为新建标签装入文本。

**Architecture:** 新增无 DOM 的 `state/workspace.js`（标签列表 + 最近文件 + 序列化）；每个标签持有一个 `DotJSONDocument`；`app/main.js` 改为操作「当前激活文档」并渲染标签栏；会话经已有 `services.readSession` / `writeSession`；最近文件路径列表用 `utools.dbStorage`。

**Tech Stack:** 纯 HTML/CSS/JS、uTools Plugin API、Node 契约测试。

**Spec:** `docs/superpowers/specs/2026-11-19-utools-feature-parity-design.md`（P2）

**Depends on:** P1 已提交（`d302a95` 或其后继）。

## Global Constraints

- 禁止在 `main` 上直接改代码；从当前 `feat/utools-parity-p1` 建 `feat/utools-parity-p2`。
- 未经用户明确要求，不要 `git commit`。
- 工具栏保持文字按钮；不做窗口拖放。
- 标签上限 **20**；最近文件上限 **10**。
- 会话正文只写 `getPluginLocalDataPath()/session-v1.json`，不得写入 `dbStorage`。
- 最近文件只存路径字符串列表到 `dbStorage`（键名固定 `dotjson.recentFiles`）。
- `lib/` 与 `state/` 不得依赖 DOM / `utools`（workspace 纯逻辑；persist 适配放 app 或薄 wrapper）。
- 不做 Diff / JSONL / 设置页（P3/P4）。

## File Structure

| File | Responsibility |
|------|----------------|
| `utools/state/workspace.js` | 多标签 CRUD、激活、改名、复制、关闭策略、会话 snapshot 序列化/反序列化、最近文件列表 |
| `utools/state/document.js` | 已有单文档；可增加 `id` / `title` 字段辅助标签 |
| `utools/app/main.js` | 标签栏 UI、切换时同步 editor/tree、生命周期 ready/enter/out、多文件打开 |
| `utools/index.html` / `index.css` | 标签栏 DOM 与样式 |
| `utools/plugin.json` | `files.maxLength`: 20 |
| `utools/tests/run-workspace.js` | workspace 契约测试 |
| `utools/README.md` | P2 验收清单 |

### Session snapshot 格式（`session-v1.json`）

```json
{
  "version": 1,
  "activeIndex": 0,
  "tabs": [
    {
      "rawText": "...",
      "filePath": "/abs/or/null",
      "fileName": "a.json",
      "indentKey": "fourSpaces",
      "isDirty": false,
      "title": "可选显示名"
    }
  ]
}
```

说明：相对 mac「只存路径」，uTools 按规格把正文写入本地会话文件，以便恢复粘贴型未命名标签。

---

### Task 0: 功能分支

**Files:** None

- [ ] **Step 1**

```bash
cd /Users/tt/Documents/workspace/project/dot-json
git branch --show-current
git log -1 --oneline
git status -sb
```

Expected: 在 `feat/utools-parity-p1`，HEAD 含 P1；工作区对 utools 宜干净。

- [ ] **Step 2**

```bash
git checkout -b feat/utools-parity-p2
```

---

### Task 1: `state/workspace.js` + 契约测试

**Files:**
- Create: `utools/state/workspace.js`
- Create: `utools/tests/run-workspace.js`
- Modify: `utools/state/document.js`（可选：`create` 增加 `id`、`title`）

**Interfaces:** `DotJSONWorkspace`
- `create() -> workspace`：`{ tabs: Doc[], activeIndex, recentFiles: string[], nextUntitled: number }`
- `MAX_TABS = 20`, `MAX_RECENT = 10`
- `ensureTab(ws)`：若无标签则 newTab
- `newTab(ws) -> { ok, error? }`
- `activate(ws, index)`
- `activeDoc(ws) -> doc|null`
- `closeTab(ws, index) -> { ok }`（至少关到 0 时自动 newTab 空文档，对齐「始终有一页」）
- `duplicateTab(ws, index) -> { ok, error? }`
- `renameTab(ws, index, title)`
- `openPath(ws, { filePath, fileName, rawText, indentKey? })`：同路径已打开则激活；否则 newTab 装入；达上限返回 error
- `addRecent(ws, filePath)` / `clearRecent(ws)`
- `toSnapshot(ws) -> object` / `fromSnapshot(snapshot) -> workspace`

- [ ] **Step 1: 写失败测试** `utools/tests/run-workspace.js`

```js
"use strict";
require("../state/document.js");
require("../state/workspace.js");
const WS = globalThis.DotJSONWorkspace;
const Doc = globalThis.DotJSONDocument;
if (!WS) { console.error("missing"); process.exit(1); }

let failed = 0;
function assertEqual(a, e, name) {
  if (JSON.stringify(a) !== JSON.stringify(e)) {
    failed += 1;
    console.error("FAIL", name, a, e);
    return;
  }
  console.log("ok  ", name);
}

let ws = WS.create();
WS.ensureTab(ws);
assertEqual(ws.tabs.length, 1, "ensure one tab");
assertEqual(ws.activeIndex, 0, "active 0");

for (let i = 0; i < 19; i += 1) assertEqual(WS.newTab(ws).ok, true, "newTab " + i);
assertEqual(WS.newTab(ws).ok, false, "21st tab rejected");
assertEqual(ws.tabs.length, 20, "max 20");

WS.activate(ws, 3);
assertEqual(ws.activeIndex, 3, "activate 3");

Doc.setText(WS.activeDoc(ws), "x", { markDirty: true });
const dup = WS.duplicateTab(ws, 3);
assertEqual(dup.ok, false, "dup at max fails"); // already 20

// shrink then dup
ws = WS.create();
WS.ensureTab(ws);
Doc.setText(ws.tabs[0], '{"a":1}', { markDirty: true });
WS.renameTab(ws, 0, "Mine");
assertEqual(ws.tabs[0].title, "Mine", "rename");
assertEqual(WS.duplicateTab(ws, 0).ok, true, "dup ok");
assertEqual(ws.tabs.length, 2, "two after dup");
assertEqual(ws.tabs[1].rawText, '{"a":1}', "dup copies text");

WS.openPath(ws, { filePath: "/tmp/a.json", fileName: "a.json", rawText: "{}" });
WS.openPath(ws, { filePath: "/tmp/a.json", fileName: "a.json", rawText: "{}" });
assertEqual(ws.tabs.filter((t) => t.filePath === "/tmp/a.json").length, 1, "dedupe path");

WS.addRecent(ws, "/tmp/a.json");
WS.addRecent(ws, "/tmp/b.json");
WS.addRecent(ws, "/tmp/a.json");
assertEqual(ws.recentFiles[0], "/tmp/a.json", "recent mru");
assertEqual(ws.recentFiles.length, 2, "recent unique");

const snap = WS.toSnapshot(ws);
const ws2 = WS.fromSnapshot(snap);
assertEqual(ws2.tabs.length, ws.tabs.length, "snapshot roundtrip count");
assertEqual(ws2.activeIndex, ws.activeIndex, "snapshot active");

if (failed) process.exit(1);
console.log("\nall passed");
```

- [ ] **Step 2: 跑红**

```bash
cd utools && node tests/run-workspace.js
```

- [ ] **Step 3: 实现 `state/workspace.js`**（及 document 的 `title` 字段若测试需要）

实现须满足上述接口；`closeTab` 若关掉最后一个则立即 `newTab`；`fromSnapshot` 非法/空则 `create+ensureTab`。

- [ ] **Step 4: 跑绿**

```bash
node tests/run-workspace.js
```

---

### Task 2: 标签栏 UI + 切换同步

**Files:**
- Modify: `utools/index.html`、`index.css`、`app/main.js`

**Interfaces:**
- HTML：`#tab-bar` 容器 + 「+」新建按钮
- 每个标签显示 `title || fileName || Untitled N`，脏则前缀 `•`
- 单击激活；双击改名（`prompt` 即可）；右键菜单：复制 / 关闭 / 关闭其他（文字项）
- 切换标签：把 `activeDoc` 的 `rawText`/`indent`/`file` 灌入 editor，并 `refreshTree`

- [ ] **Step 1: HTML/CSS** 在 toolbar 与 panes 之间插入标签栏。

- [ ] **Step 2: `main.js`** 用 `DotJSONWorkspace` 替换单一 `doc`；所有现有操作改为 `WS.activeDoc(ws)`；抽出 `renderTabs()` / `bindActiveDocToEditor()` / `flushEditorToActiveDoc()`（切换前写回）。

- [ ] **Step 3: 冒烟** 浏览器打开：多标签切换内容不串；+ 新建；关到最后一个仍剩一页。

---

### Task 3: 会话恢复（ready / out）

**Files:**
- Modify: `utools/app/main.js`
- Confirm: `utools/preload.js` 已有 `readSession`/`writeSession`

- [ ] **Step 1:** `utools.onPluginReady`：`services.readSession()` → `WS.fromSnapshot(JSON.parse(...))` → 渲染；无会话则 `ensureTab`。

- [ ] **Step 2:** `utools.onPluginOut`：`flushEditorToActiveDoc` → `services.writeSession(JSON.stringify(WS.toSnapshot(ws)))`。

- [ ] **Step 3:** 标签变更后可 debounce 写会话（可选，≥300ms）；至少 out 时必写。

- [ ] **Step 4:** 无 `utools` 时跳过，不抛错。

---

### Task 4: 最近文件

**Files:**
- Modify: `utools/app/main.js`、`index.html`

- [ ] **Step 1:** 键 `dotjson.recentFiles`：`utools.dbStorage.getItem/setItem`；与 `ws.recentFiles` 同步（ready 时读入，变更时写回）。

- [ ] **Step 2:** UI：工具栏或标签栏旁「最近」下拉/菜单（文字），点击路径则 `services.readTextFile` + `openPath`；失败状态栏错误并从 recent 移除可选。

- [ ] **Step 3:** 成功打开/保存路径时 `WS.addRecent`。

---

### Task 5: 多文件入口

**Files:**
- Modify: `utools/plugin.json`（`maxLength: 20`）
- Modify: `utools/app/main.js`

- [ ] **Step 1:** `plugin.json` files cmd `maxLength` → `20`。

- [ ] **Step 2:** `showOpenDialog` properties 加 `multiSelections`；对每个路径 `openPath`；达上限截断并 `setStatus` 提示。

- [ ] **Step 3:** `onPluginEnter` `files`：遍历 `MatchFile[]`，`isFile` 且扩展名 `json`；上限截断提示。

- [ ] **Step 4:** `over`：`newTab`（或 `openPath` 无路径）装入文本，**不覆盖**当前未保存标签内容（规格：P2 起新建标签）。

---

### Task 6: README P2 清单 + 回归

**Files:**
- Modify: `utools/README.md`

- [ ] **Step 1: 清单**

1. 多标签新建/切换/关闭/改名/复制  
2. 标签上限 20 有提示  
3. 退出再进恢复会话（uTools）  
4. 最近文件最多 10  
5. 打开对话框多选；files 匹配多文件  
6. over 新建标签不覆盖  
7. `node tests/run-workspace.js` 与既有 `run-*.js` 全绿  

- [ ] **Step 2: 跑全套 Node 测试；uTools 项标明人工。**

---

## P2 完成标准

- workspace 测试全绿；UI 多标签可用；会话与 recent 分层正确；`maxLength=20`；无拖放；无 P3+。

## Spec Coverage

| Spec P2 | Task |
|---------|------|
| 多标签改名/复制/关闭 | 1–2 |
| 会话 session-v1.json | 3 |
| 最近文件 10 / dbStorage | 4 |
| files.maxLength + 对话框多选 | 5 |
| over 新建标签 | 5 |
| README | 6 |
