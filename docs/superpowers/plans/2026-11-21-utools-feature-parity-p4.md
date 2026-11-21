# uTools Feature Parity P4（JSONL + 设置）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供 JSONL 浏览（上一条/下一条 + 记录列表 + 当前记录进编辑器/树）与插件内简单设置页（默认缩进，仅影响新建标签）。

**Architecture:** 解析逻辑在 `lib/jsonl.js`（对照 mac `JSONLPreparser`）；偏好在 `state/preferences.js`（无 DOM，`dbStorage` 键读写由 UI 调用）；UI 为 JSONL 导航条/记录列表 + 简易设置面板。打开 `.jsonl` 进入浏览模式；新建标签时应用默认缩进。

**Tech Stack:** 纯 HTML/CSS/JS、Node 契约测试、无 npm 业务依赖。

**Spec:** `docs/superpowers/specs/2026-11-19-utools-feature-parity-design.md`（P4）

**Depends on:** `feat/utools-parity-p0-p3`（含 review 修复 `4c338e8`）。

## Global Constraints

- 禁止在 `main` 上直接改代码；从 `feat/utools-parity-p0-p3` 建 `feat/utools-parity-p4`。
- 未经用户明确要求，不要 `git commit`。
- 工具栏文字按钮；不做拖放 / Finder 关联 / formatOnOpen / formatOnPaste。
- `lib/` 与 `state/` 不得依赖 DOM / `utools`。
- JSONL：按物理行切分；跳过纯空白行；非空白行均为候选记录；`isValid` 用 `JSON.parse` 判断。
- `LineInfo.index` 为**原始物理行号**（0-based，含被跳过空白行所占行号）；`parseLine(at)` 的 `at` 是 `lines` 数组下标，不是物理行号。
- 设置：默认缩进键 `dotjson.defaultIndent`；值仅 `twoSpaces` | `fourSpaces` | `tab`；非法/缺失回退 `fourSpaces`。
- 改默认缩进**不回写**已打开标签的 `indentKey`；仅 `newTab` / 新建空文档路径使用。

## File Structure

| File | Responsibility |
|------|----------------|
| `utools/lib/jsonl.js` | `DotJSONL.parse(raw)` → `{ lines, count, parseLine }` |
| `utools/state/preferences.js` | `DotJSONPreferences`：normalize / create / applyDefaultIndent |
| `utools/tests/run-jsonl.js` | 对照 `JSONLPreparserTests` |
| `utools/tests/run-preferences.js` | 默认缩进 normalize + 不污染已有 tab |
| `utools/app/main.js` | JSONL 模式 UI、打开扩展名、设置面板、新建标签用默认缩进 |
| `utools/index.html` / `index.css` | JSONL 导航 / 列表 / 设置面板 DOM 与样式 |
| `utools/plugin.json` | `files` `extensions` 增加 `jsonl` / `JSONL` |
| `utools/README.md` | P4 验收清单 |

### JSONL 模型

```js
// DotJSONL.parse(rawContent) -> preparser
{
  lines: Array<{ index: number, rawText: string, byteOffset: number, isValid: boolean }>,
  count: number, // === lines.length
  parseLine(at: number): unknown | null  // JSON.parse 成功返回值；越界或无效返回 null
}
```

### Preferences 模型

```js
DotJSONPreferences = {
  STORAGE_KEY_DEFAULT_INDENT: "dotjson.defaultIndent",
  normalizeIndentKey(raw): "twoSpaces"|"fourSpaces"|"tab",
  create(stored): { defaultIndent: ... },
  // 仅当 doc 无自定义需求时：给新建 doc 设 indentKey
}
```

---

### Task 0: 功能分支

- [ ] 确认在 `feat/utools-parity-p0-p3` 且含 `4c338e8`；`git checkout -b feat/utools-parity-p4`。

---

### Task 1: `lib/jsonl.js` + 契约测试

**Interfaces:** `DotJSONL`
- `parse(rawContent: string) -> { lines, count, parseLine(at) }`

- [ ] **Step 1: 写测试** `utools/tests/run-jsonl.js`：

```js
"use strict";
require("../lib/jsonl.js");
const L = globalThis.DotJSONL;
if (!L) { console.error("missing"); process.exit(1); }

let failed = 0;
function assert(cond, name) {
  if (!cond) { failed += 1; console.error("FAIL", name); }
  else console.log("ok  ", name);
}
function assertEqual(a, e, name) {
  if (JSON.stringify(a) !== JSON.stringify(e)) {
    failed += 1;
    console.error("FAIL", name, a, e);
  } else console.log("ok  ", name);
}

const p1 = L.parse('{"id":1,"name":"Alice"}\n{"id":2,"name":"Bob"}\n{"id":3,"name":"Charlie"}');
assertEqual(p1.count, 3, "simple count");
assert(p1.lines.every((x) => x.isValid), "all valid");

const p2 = L.parse('{"id":1}\nnot json\n{"id":2}');
assertEqual(p2.count, 3, "invalid still counted");
assertEqual(p2.lines[0].isValid, true, "line0 valid");
assertEqual(p2.lines[1].isValid, false, "line1 invalid");
assertEqual(p2.lines[2].isValid, true, "line2 valid");

const p3 = L.parse('{"x":100}\n{"y":200}');
assertEqual(p3.parseLine(0), { x: 100 }, "parseLine 0");
assertEqual(p3.parseLine(99), null, "oob null");

assertEqual(L.parse("").count, 0, "empty");
assertEqual(L.parse('{"a":1}\n\n').count, 1, "skip blank");
assertEqual(L.parse("   \n  ").count, 0, "whitespace only");

const pUni = L.parse('{"名称":"测试","emoji":"😀"}\n{"值":100}');
assertEqual(pUni.count, 2, "unicode count");

const unix = L.parse('{"a":1}\n{"b":2}\n{"c":3}');
assertEqual(unix.count, 3, "unix newlines");
assertEqual(unix.lines[0].index, 0, "physical index 0");
assertEqual(unix.lines[1].index, 1, "physical index 1");

if (failed) process.exit(1);
console.log("\nall passed");
```

- [ ] **Step 2: 跑测应 FAIL**（缺模块）

Run: `node utools/tests/run-jsonl.js`  
Expected: `missing` 或类似失败

- [ ] **Step 3: 实现** `utools/lib/jsonl.js`（IIFE 挂 `globalThis.DotJSONL`；Node 与浏览器均可）：

行为对齐 mac：
- `rawContent.split` 按 `\n` / `\r\n`（可用 `String(raw).replace(/\r\n/g, "\n").split("\n")`）
- 空白行（`trim` 后空）跳过，但仍累加 `byteOffset`（UTF-8；Node 用 `Buffer.byteLength`，浏览器 `TextEncoder`）
- 非空白行：`JSON.parse` try/catch 得 `isValid`；`index` 为物理行号；`rawText` 为原行（不去 trim 内容两侧以外的空白用于 parse——与 mac 一致：整行 `JSONParser.parse(line)`，空白行才 trim 判断）
- `parseLine(at)`：越界或 `!isValid` → `null`；否则 `JSON.parse(rawText)` 返回值

- [ ] **Step 4: 跑测 PASS**

Run: `node utools/tests/run-jsonl.js`  
Expected: `all passed`

- [ ] **Step 5:** 在 `index.html` 于 `json-diff.js` 之后增加 `<script src="lib/jsonl.js"></script>`（若尚未加）。

---

### Task 2: `state/preferences.js` + 契约测试

**Interfaces:** `DotJSONPreferences`
- `STORAGE_KEY_DEFAULT_INDENT = "dotjson.defaultIndent"`
- `normalizeIndentKey(raw) -> string`
- `create(partial?) -> { defaultIndent }`
- `applyToNewDoc(doc, prefs)`：`Doc.setIndent(doc, prefs.defaultIndent)`（依赖已加载的 `DotJSONDocument`）

- [ ] **Step 1: 写测试** `utools/tests/run-preferences.js`：

```js
"use strict";
require("../state/document.js");
require("../state/preferences.js");
require("../state/workspace.js");
const Pref = globalThis.DotJSONPreferences;
const Doc = globalThis.DotJSONDocument;
const WS = globalThis.DotJSONWorkspace;
if (!Pref || !Doc || !WS) { console.error("missing"); process.exit(1); }

let failed = 0;
function assertEqual(a, e, name) {
  if (JSON.stringify(a) !== JSON.stringify(e)) {
    failed += 1;
    console.error("FAIL", name, a, e);
  } else console.log("ok  ", name);
}

assertEqual(Pref.normalizeIndentKey("twoSpaces"), "twoSpaces", "keep two");
assertEqual(Pref.normalizeIndentKey("nope"), "fourSpaces", "bad -> four");
assertEqual(Pref.normalizeIndentKey(null), "fourSpaces", "null -> four");
assertEqual(Pref.create({}).defaultIndent, "fourSpaces", "create default");
assertEqual(Pref.create({ defaultIndent: "tab" }).defaultIndent, "tab", "create tab");

const ws = WS.create();
WS.ensureTab(ws);
Doc.setIndent(ws.tabs[0], "twoSpaces");
const prefs = Pref.create({ defaultIndent: "tab" });
// 改偏好不碰已有 tab
assertEqual(ws.tabs[0].indentKey, "twoSpaces", "existing untouched");
WS.newTab(ws);
Pref.applyToNewDoc(WS.activeDoc(ws), prefs);
assertEqual(WS.activeDoc(ws).indentKey, "tab", "new tab gets default");

if (failed) process.exit(1);
console.log("\nall passed");
```

- [ ] **Step 2–4:** FAIL → 实现 → PASS

实现要点：
```js
const ALLOWED = { twoSpaces: 1, fourSpaces: 1, tab: 1 };
function normalizeIndentKey(raw) {
  return ALLOWED[raw] ? raw : "fourSpaces";
}
function create(partial) {
  return { defaultIndent: normalizeIndentKey(partial && partial.defaultIndent) };
}
function applyToNewDoc(doc, prefs) {
  if (!doc || !prefs) return;
  global.DotJSONDocument.setIndent(doc, prefs.defaultIndent);
}
```

- [ ] **Step 5:** `index.html` 在 `document.js` 后、`workspace.js` 前或后加载 `preferences.js`（须在 `workspace` 使用前可用；`applyToNewDoc` 在 UI 调 `newTab` 之后调用即可）。

---

### Task 3: JSONL 浏览 UI

**Files:**
- Modify: `utools/index.html`, `utools/index.css`, `utools/app/main.js`, `utools/plugin.json`

**行为：**
1. 工具栏增加文字按钮「JSONL」（或打开 `.jsonl` 自动进入）；设置面板入口「设置」。
2. JSONL 模式条（编辑器上方或树上方）：`上一条` / `下一条` / `第 i / N 条`（i 为 1-based 展示）；无效行状态栏提示。
3. 左侧或树旁记录列表：每项显示 `#n` + 截断 `rawText`；无效项加 class；点击跳转。
4. 选中记录：`editor` 设为该行 `rawText`（或 format 成功时的 pretty）；树按该记录解析；**不**把整份 JSONL 当单 JSON 解析。
5. 文档级状态：在 `doc` 上挂 `jsonlMode: { rawFull, recordIndex }` 或 `state.jsonl` 按 active doc 绑定；切标签时恢复/清除 UI。
6. 打开：`isJsonFileName` → `isAllowedOpenName` 接受 `json` 与 `jsonl`；对话框 filters 增加 jsonl；`plugin.json` files extensions 增加 `jsonl`/`JSONL`。
7. 打开 jsonl 文件：读全文进 `jsonlMode.rawFull`，`parse`，定位第一条，展示；`filePath` 仍关联。
8. 在 JSONL 模式编辑当前记录后「写回记录」：更新 `lines[i].rawText` 并重建 `rawFull`（可选 P4 最小：切换记录前把 editor 写回当前行）。保存文件时写 `rawFull`。

最小写回策略（P4 必做）：
- `flushJsonlRecordToBuffer()`：离开当前 recordIndex 前，用 `els.editor.value` 更新该行（单行；若用户插入换行则视为该记录原文，重建时按「整份 rawFull 由 lines + 原空白行结构」——**简化**：P4 用 `lines.map(l => l.rawText).join("\n")` 作为保存正文，不保留被跳过的空白行位置（可接受降级；在 README 注明）。

- [ ] **Step 1:** HTML：在 tab-bar 与 panes 之间或 editor-header 下增加：

```html
<div id="jsonl-bar" class="jsonl-bar" hidden>
  <button type="button" id="jsonl-prev">上一条</button>
  <span id="jsonl-pos" class="jsonl-pos">0 / 0</span>
  <button type="button" id="jsonl-next">下一条</button>
  <button type="button" id="jsonl-exit" title="退出 JSONL 浏览">退出浏览</button>
</div>
<!-- 树面板内列表 -->
<div id="jsonl-list" class="jsonl-list" hidden></div>
```

工具栏增加：`<button type="button" id="btn-jsonl">JSONL</button>`、`<button type="button" id="btn-settings">设置</button>`。

设置面板（简单 overlay）：

```html
<div id="settings-panel" class="settings-panel" hidden>
  <div class="settings-card">
    <h2>设置</h2>
    <label>默认缩进
      <select id="settings-default-indent">
        <option value="twoSpaces">2 spaces</option>
        <option value="fourSpaces">4 spaces</option>
        <option value="tab">Tab</option>
      </select>
    </label>
    <p class="settings-hint">仅影响新建标签，不改变已打开文档。</p>
    <button type="button" id="settings-close">关闭</button>
  </div>
</div>
```

- [ ] **Step 2:** CSS：`.jsonl-bar`、`.jsonl-list`、`.jsonl-list .is-invalid`、`.jsonl-list .is-active`、`.settings-panel` 遮罩与卡片（沿用现有深色变量，避免新紫色主题）。

- [ ] **Step 3:** `main.js` 核心函数（名称固定）：
  - `loadPreferences()` / `savePreferences()` — `dbStorage` get/set `Pref.STORAGE_KEY_DEFAULT_INDENT`
  - `enterJsonlMode(rawFull, opts)` / `exitJsonlMode()` / `showJsonlRecord(index)` / `flushJsonlRecordToBuffer()`
  - `openFileIntoWorkspace`：若扩展名 jsonl → enterJsonlMode
  - `btn-jsonl`：对当前编辑器全文 enterJsonlMode
  - `createNewTab`：`WS.newTab` 后 `Pref.applyToNewDoc(activeDoc(), prefs)`
  - `restoreSession` 后 `loadPreferences()`（偏好与会话独立）
  - 保存：若当前 doc 在 jsonl 模式，先 flush，再写 `rawFull`（`lines` join）

- [ ] **Step 4:** 手工验收清单写入 README（见 Task 4）。

---

### Task 4: README + 回归

- [ ] **Step 1:** README 增加 P4 表与目录结构（`jsonl.js` / `preferences.js` / 新测试）。

验收项：
- [ ] 打开 `.jsonl` 进入浏览；上一条/下一条/列表跳转
- [ ] 无效行可定位且状态提示
- [ ] 保存写回多行 JSONL
- [ ] 设置改默认缩进后，新建标签用新缩进；旧标签不变
- [ ] `files` / 打开对话框接受 jsonl
- [ ] `node utools/tests/run-*.js` 全部通过（含 `run-jsonl.js`、`run-preferences.js`）

- [ ] **Step 2:** 跑全套：

```bash
cd utools && node tests/run-json-core.js && node tests/run-python-literal.js && node tests/run-tree-edit.js && node tests/run-document.js && node tests/run-workspace.js && node tests/run-json-diff.js && node tests/run-safe-path.js && node tests/run-jsonl.js && node tests/run-preferences.js
```

Expected: 全部 `all passed`

---

## Self-Review

1. **Spec coverage:** JSONL 浏览 ✓；简单设置（默认缩进）✓；files/对话框扩展 jsonl ✓；dbStorage 偏好 ✓；不做 formatOnPaste 等 ✓。
2. **Placeholder scan:** 无 TBD；空白行不保留为已知降级并写 README。
3. **Types:** `DotJSONL.parse` / `parseLine`；`DotJSONPreferences.normalizeIndentKey` / `applyToNewDoc` 前后一致。
