# uTools Feature Parity P0（地基 + 重构）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有 `utools/` 拆成可测的 `lib/` + `state/` + `app/` 结构，补上对照 `DotJSONCore` 的契约测试，并把 preload 迁到 `window.services`；行为与现有 MVP 一致，为 P1–P4 铺路。

**Architecture:** 算法留在 `lib/json-core.js`（Node 可加载）；单文档状态进 `state/document.js`（无 DOM）；UI 事件进 `app/main.js`；`preload.js` 只暴露最小 `window.services`。不新增用户可见功能（除测试与目录结构外）。

**Tech Stack:** 纯 HTML/CSS/JS、uTools Plugin API、Node.js（跑测试）、无 npm 业务依赖。

**Spec:** `docs/superpowers/specs/2026-11-19-utools-feature-parity-design.md`

## Global Constraints

- 禁止在 `main` 上直接改代码；先建功能分支再实现。
- 未经用户明确要求，不要 `git commit`（用户规则优先于本计划中的提交习惯）。
- 工具栏保持文字按钮，不引入 macOS 风格图标。
- 不做窗口拖放、Finder 关联、自建更新、CLI。
- `lib/` 不得依赖 `window` / DOM / `utools`。
- preload 禁止把 `fs` 整包挂到 `window`；统一 `window.services`。
- `files.maxLength` 本阶段保持 `1`。
- 本计划只交付 **P0**；P1–P4 另写独立 plan。

## 后续计划（本文件不实现）

| 计划 | 范围 |
|------|------|
| P1 | 保存/脏状态/另存为、Python↔JSON、树 Expand/Collapse All/Delete、简易编辑器查找、错误定位 |
| P2 | 多标签、会话 `session-v1.json`、最近文件、`files.maxLength=20`、对话框多选 |
| P3 | `lib/json-diff.js` + Diff UI |
| P4 | `lib/jsonl.js`、设置页、扩展名含 jsonl |

## File Structure

| File | Responsibility |
|------|----------------|
| `utools/lib/json-core.js` | format / minify / repair / tree / path（已有；保证 Node 可加载） |
| `utools/state/document.js` | 单文档状态：文本、路径、缩进键、脏标记占位（P0 脏标记恒 false，接口先立好） |
| `utools/app/main.js` | DOM 绑定、树渲染、工具栏、`onPluginEnter`（从 `index.js` 迁出） |
| `utools/preload.js` | `window.services`：读写用户文件、读剪贴板、会话路径读写占位 |
| `utools/index.html` | 脚本改为加载 `lib` → `state` → `app` |
| `utools/index.js` | 删除或改为一行兼容说明后删除 |
| `utools/tests/run-json-core.js` | Node 契约测试入口 |
| `utools/README.md` | 目录、测试命令、手工验收 |

---

### Task 0: 功能分支

**Files:**
- None（仅 git 分支）

**Interfaces:**
- Consumes: 当前工作区
- Produces: 分支 `feat/utools-parity-p0`

- [ ] **Step 1: 确认分支与状态**

Run:

```bash
cd /Users/tt/Documents/workspace/project/dot-json
git branch --show-current
git status -sb
```

Expected: 宜在 `main`（或已基于最新 main）。未跟踪的 design/plan 可保留。

- [ ] **Step 2: 创建并切换分支**

```bash
git checkout -b feat/utools-parity-p0
```

Expected: 当前分支为 `feat/utools-parity-p0`。

---

### Task 1: json-core 契约测试（先写失败/再对齐现有实现）

**Files:**
- Create: `utools/tests/run-json-core.js`
- Modify: `utools/lib/json-core.js`（仅当测试暴露行为偏差时修；优先对齐 mac 用例）

**Interfaces:**
- Consumes: `globalThis.DotJSONCore`（`format`, `minify`, `repair`, `buildRootTree`, `copyValueText`）
- Produces: 可执行的 Node 测试；退出码 `0` 全过、非 `0` 有失败

- [ ] **Step 1: 写入测试运行器与用例**

创建 `utools/tests/run-json-core.js`：

```js
"use strict";

require("../lib/json-core.js");
const core = globalThis.DotJSONCore;
if (!core) {
  console.error("DotJSONCore missing after require");
  process.exit(1);
}

let failed = 0;

function assertEqual(actual, expected, name) {
  if (actual !== expected) {
    failed += 1;
    console.error(`FAIL ${name}\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`);
    return;
  }
  console.log(`ok   ${name}`);
}

function assertThrows(fn, name) {
  try {
    fn();
    failed += 1;
    console.error(`FAIL ${name} (expected throw)`);
  } catch (_err) {
    console.log(`ok   ${name}`);
  }
}

// —— format / minify（对照 mac JSONFormatterTests 语义）——
assertEqual(
  core.format('{"b":1,"a":2}', "twoSpaces"),
  '{\n  "a": 2,\n  "b": 1\n}',
  "format sorts keys with twoSpaces"
);

assertEqual(
  core.format('{"a":1}', "tab").includes("\t"),
  true,
  "format tab indent contains tab"
);

assertEqual(core.format("{}", "fourSpaces"), "{}", "format empty object");
assertEqual(core.format("[]", "fourSpaces"), "[]", "format empty array");
assertEqual(core.format("42", "fourSpaces"), "42", "format number");
assertEqual(core.format("true", "fourSpaces"), "true", "format bool");
assertEqual(core.format("null", "fourSpaces"), "null", "format null");

assertEqual(
  core.minify('{\n  "a": 1,\n  "b": 2\n}'),
  '{"a":1,"b":2}',
  "minify compact"
);

assertThrows(() => core.format("", "fourSpaces"), "format empty throws");
assertThrows(() => core.format("{bad", "fourSpaces"), "format invalid throws");

// —— repair（对照 mac JSONRepairerTests 核心用例）——
assertEqual(
  core.repair("{\n  \"enabled\": true\n}\n"),
  "{\n  \"enabled\": true\n}\n",
  "repair preserves valid JSON"
);

assertEqual(
  core.repair("{'enabled': True, 'items': [None, {'ok': False}]}"),
  '{"enabled": true, "items": [null, {"ok": false}]}',
  "repair nested python collections"
);

assertEqual(
  core.repair("{'message': 'True None False', 'TrueValue': True}"),
  '{"message": "True None False", "TrueValue": true}',
  "repair keeps token words inside strings"
);

assertEqual(
  core.repair("{\n  'items': [1, 2,],\n  'ok': True,\n}\n"),
  '{\n  "items": [1, 2],\n  "ok": true\n}\n',
  "repair trailing commas without reformatting layout aggressively"
);

assertEqual(
  core.repair("Result:\n```python\n{\n  'ok': True,\n}\n```\n"),
  '{\n  "ok": true\n}\n',
  "repair extracts markdown fence"
);

assertThrows(
  () => core.repair("```json\n{}\n```\n```json\n[]\n```"),
  "repair rejects multiple fences"
);

assertThrows(() => core.repair("{'x': NaN}"), "repair rejects NaN");

// —— tree / path / copyValue ——
const built = core.buildRootTree('{"name":"Alice","age":30}');
assertEqual(built.ok, true, "buildRootTree ok");
assertEqual(built.root.jsonPath, "$", "root path is $");
const age = built.root.children.find((c) => c.key === "age");
const name = built.root.children.find((c) => c.key === "name");
assertEqual(!!age && !!name, true, "children include age and name");
assertEqual(age.jsonPath, "$.age", "age path");
assertEqual(name.jsonPath, "$.name", "name path");
assertEqual(core.copyValueText(name), "Alice", "copyValue strips string quotes");

const arr = core.buildRootTree("[10,20]");
assertEqual(arr.root.children[0].jsonPath, "$[0]", "array index path");

if (failed) {
  console.error(`\n${failed} failed`);
  process.exit(1);
}
console.log("\nall passed");
```

- [ ] **Step 2: 跑测试（允许先红）**

Run:

```bash
cd /Users/tt/Documents/workspace/project/dot-json/utools
node tests/run-json-core.js
```

Expected: 若现有 `repair` 与 mac 用例有偏差 → FAIL（记下失败项）。若已一致 → 全绿，可跳过 Step 3 中无需修改的部分。

- [ ] **Step 3: 修 `lib/json-core.js` 直到对齐**

只改 `repair` / `format` 等纯函数实现，使 Step 1 用例通过。禁止为迁就测试弱化断言（除非某条 mac 行为在 JS 端有文档化的已知差异——若出现，先停下来问用户，不要擅自降级规格）。

- [ ] **Step 4: 再跑测试确认全绿**

```bash
cd /Users/tt/Documents/workspace/project/dot-json/utools
node tests/run-json-core.js
```

Expected: 打印 `all passed`，退出码 `0`。

---

### Task 2: `state/document.js`（无 DOM 单文档状态）

**Files:**
- Create: `utools/state/document.js`
- Create: `utools/tests/run-document.js`

**Interfaces:**
- Consumes: 无
- Produces:
  - `DotJSONDocument.create()` → `{ rawText, filePath, fileName, indentKey, isDirty }`
  - `DotJSONDocument.setText(doc, text, { markDirty?: boolean })`
  - `DotJSONDocument.setFile(doc, { filePath, fileName })`
  - `DotJSONDocument.clearFile(doc)`
  - `DotJSONDocument.setIndent(doc, indentKey)`
  - `DotJSONDocument.markSaved(doc)`（`isDirty = false`）
  - `DotJSONDocument.markDirty(doc)`（`isDirty = true`）

- [ ] **Step 1: 写失败测试**

创建 `utools/tests/run-document.js`：

```js
"use strict";

require("../state/document.js");
const Doc = globalThis.DotJSONDocument;
if (!Doc) {
  console.error("DotJSONDocument missing");
  process.exit(1);
}

let failed = 0;
function assertEqual(actual, expected, name) {
  if (actual !== expected) {
    failed += 1;
    console.error(`FAIL ${name}: expected ${JSON.stringify(expected)} got ${JSON.stringify(actual)}`);
    return;
  }
  console.log(`ok   ${name}`);
}

const doc = Doc.create();
assertEqual(doc.rawText, "", "create empty text");
assertEqual(doc.filePath, null, "create null path");
assertEqual(doc.indentKey, "fourSpaces", "default indent");
assertEqual(doc.isDirty, false, "create clean");

Doc.setText(doc, '{"a":1}', { markDirty: true });
assertEqual(doc.rawText, '{"a":1}', "setText");
assertEqual(doc.isDirty, true, "dirty after setText");

Doc.setFile(doc, { filePath: "/tmp/a.json", fileName: "a.json" });
assertEqual(doc.filePath, "/tmp/a.json", "setFile path");
assertEqual(doc.fileName, "a.json", "setFile name");

Doc.markSaved(doc);
assertEqual(doc.isDirty, false, "markSaved");

Doc.clearFile(doc);
assertEqual(doc.filePath, null, "clearFile");
assertEqual(doc.fileName, "", "clearFile name");

Doc.setIndent(doc, "twoSpaces");
assertEqual(doc.indentKey, "twoSpaces", "setIndent");

if (failed) {
  console.error(`\n${failed} failed`);
  process.exit(1);
}
console.log("\nall passed");
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd /Users/tt/Documents/workspace/project/dot-json/utools
node tests/run-document.js
```

Expected: `DotJSONDocument missing` 或 FAIL，退出码非 0。

- [ ] **Step 3: 实现 `state/document.js`**

```js
/**
 * 单文档状态（无 DOM）。P0 建立接口；P1 接上真实保存/脏状态 UI。
 */
(function (global) {
  "use strict";

  function create() {
    return {
      rawText: "",
      filePath: null,
      fileName: "",
      indentKey: "fourSpaces",
      isDirty: false,
    };
  }

  function setText(doc, text, opts) {
    const options = opts || {};
    doc.rawText = text == null ? "" : String(text);
    if (options.markDirty) doc.isDirty = true;
  }

  function setFile(doc, info) {
    doc.filePath = info && info.filePath ? String(info.filePath) : null;
    doc.fileName = info && info.fileName ? String(info.fileName) : "";
  }

  function clearFile(doc) {
    doc.filePath = null;
    doc.fileName = "";
  }

  function setIndent(doc, indentKey) {
    doc.indentKey = indentKey || "fourSpaces";
  }

  function markSaved(doc) {
    doc.isDirty = false;
  }

  function markDirty(doc) {
    doc.isDirty = true;
  }

  global.DotJSONDocument = {
    create,
    setText,
    setFile,
    clearFile,
    setIndent,
    markSaved,
    markDirty,
  };
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd /Users/tt/Documents/workspace/project/dot-json/utools
node tests/run-document.js
```

Expected: `all passed`，退出码 `0`。

---

### Task 3: preload 迁到 `window.services`

**Files:**
- Modify: `utools/preload.js`
- Modify: `utools/app/main.js`（Task 4 创建；本任务先改 preload，Task 4 再改调用方）

**Interfaces:**
- Consumes: Node `fs`、Electron `clipboard`、可选 `utools.getPluginLocalDataPath`
- Produces: `window.services`：
  - `readTextFile(filePath: string): string`
  - `writeTextFile(filePath: string, content: string): void`
  - `readClipboard(): string`
  - `writeClipboard(text: string): boolean`（可选保留；UI 优先 `utools.copyText`）
  - `readSession(): string | null`
  - `writeSession(content: string): void`

- [ ] **Step 1: 重写 `preload.js`**

```js
/**
 * DotJSON uTools preload — 最小本地能力桥。
 * 官方：统一命名空间、禁止把 fs 整包暴露给前端。
 */
const fs = require("fs");
const path = require("path");
const { clipboard } = require("electron");

const SESSION_FILE = "session-v1.json";

function sessionPath() {
  if (typeof utools !== "undefined" && typeof utools.getPluginLocalDataPath === "function") {
    return path.join(utools.getPluginLocalDataPath(), SESSION_FILE);
  }
  return null;
}

window.services = {
  readTextFile(filePath) {
    return fs.readFileSync(filePath, "utf8");
  },

  writeTextFile(filePath, content) {
    fs.writeFileSync(filePath, content, "utf8");
  },

  readClipboard() {
    return clipboard.readText() || "";
  },

  writeClipboard(text) {
    clipboard.writeText(String(text ?? ""));
    return true;
  },

  readSession() {
    const file = sessionPath();
    if (!file || !fs.existsSync(file)) return null;
    return fs.readFileSync(file, "utf8");
  },

  writeSession(content) {
    const file = sessionPath();
    if (!file) return;
    fs.writeFileSync(file, String(content ?? ""), "utf8");
  },
};
```

- [ ] **Step 2: 确认不再存在 `window.dotjson`**

在 `utools/` 内搜索：

```bash
cd /Users/tt/Documents/workspace/project/dot-json
rg "window\\.dotjson|api\\.read|api\\.write" utools/
```

Expected: preload 无 `window.dotjson`；旧 `index.js` 若仍引用，将在 Task 4 一并改掉。

---

### Task 4: 将 `index.js` 重构为 `app/main.js` 并改用 services + document

**Files:**
- Create: `utools/app/main.js`
- Modify: `utools/index.html`
- Delete: `utools/index.js`（迁移完成后）

**Interfaces:**
- Consumes: `DotJSONCore`、`DotJSONDocument`、`window.services`、`utools.*`
- Produces: 与重构前相同的用户可见行为（双栏、工具栏文字按钮、打开/导出、树、搜索、右键复制、onPluginEnter）

- [ ] **Step 1: 创建 `app/main.js`**

把现有 `utools/index.js` 逻辑迁入，并做这些替换（保持其余行为）：

1. 顶部：

```js
(() => {
  "use strict";

  const core = window.DotJSONCore;
  const Doc = window.DotJSONDocument;
  const services = window.services;

  const doc = Doc.create();
  // ... els 同原 index.js ...
```

2. 所有 `api.readTextFile` / `api.writeTextFile` / `api.readClipboard` / `api.writeClipboard` → `services.*`（`services` 缺失时与原来一样降级：`navigator.clipboard` / 状态栏错误）。

3. 用 `doc` 同步路径与正文：
   - `setEditorText` 内：`Doc.setText(doc, text, { markDirty: false })`（P0 打开/格式化不强制脏）；设置文件时 `Doc.setFile` / `clearFile`；`els.indent` 变更时 `Doc.setIndent`。
   - 编辑器 `input` 时：`Doc.setText(doc, els.editor.value, { markDirty: true })` 再 `scheduleParse`。
   - 读路径/文件名时以 `doc.filePath` / `doc.fileName` 为准（可与 `els.fileLabel` 同步）。

4. `copyText`：优先 `utools.copyText`，否则 `services.writeClipboard`。

5. 保留 splitter、树、搜索、context menu、`handlePluginEnter` 行为；`files` 仍只开第一个文件。

完整文件以当前 `index.js` 为底稿逐段迁移，不要重新发明交互。

- [ ] **Step 2: 更新 `index.html` 脚本顺序**

把底部脚本换成：

```html
  <script src="lib/json-core.js"></script>
  <script src="state/document.js"></script>
  <script src="app/main.js"></script>
</body>
</html>
```

- [ ] **Step 3: 删除旧 `utools/index.js`**

```bash
rm /Users/tt/Documents/workspace/project/dot-json/utools/index.js
```

- [ ] **Step 4: 回归契约测试**

```bash
cd /Users/tt/Documents/workspace/project/dot-json/utools
node tests/run-json-core.js
node tests/run-document.js
```

Expected: 两次 `all passed`。

- [ ] **Step 5: 浏览器冒烟（无 utools）**

用浏览器打开 `utools/index.html`：应看到示例 JSON、树、格式化/压缩/修复按钮可用。

---

### Task 5: README + 手工验收清单

**Files:**
- Modify: `utools/README.md`

**Interfaces:**
- Consumes: 新目录与测试命令
- Produces: 开发者可按文档加载插件与跑测试

- [ ] **Step 1: 更新 README 目录结构与功能说明**

目录改为包含 `app/`、`state/`、`tests/`；注明 preload 为 `window.services`；保留「未移植」列表并指向 design spec。

增加：

```markdown
## 契约测试

```bash
cd utools
node tests/run-json-core.js
node tests/run-document.js
```

## P0 手工验收（uTools 开发者模式）

1. 加载本目录插件，指令 `json` 可打开。
2. 格式化 / 压缩 / 修复 / 缩进与改前一致。
3. 打开 / 导出文件可用。
4. 选中文本 →「用 DotJSON 打开」仍可用。
5. 选中 `.json` 文件匹配仍可用（单文件）。
6. 工具栏为文字按钮，无 macOS 图标栏。
```

- [ ] **Step 2: 在 uTools 开发者模式按清单点验**

Expected: 清单 1–6 通过。

---

## P0 完成标准

- `node tests/run-json-core.js` 与 `node tests/run-document.js` 均为退出码 0。
- 无 `window.dotjson`；preload 仅 `window.services`。
- UI 入口为 `app/main.js`，状态为 `state/document.js`。
- 用户可见 MVP 行为不回退；无 P1+ 功能混入。

## Spec Coverage（自检）

| Spec 项（P0 相关） | Task |
|--------------------|------|
| 模块边界 lib/state/app | 2, 4 |
| format/minify/repair/path 契约测试 | 1 |
| preload → window.services | 3 |
| 工具栏文字按钮 | 4（保持） |
| files.maxLength 仍为 1 | 4（不改 plugin.json） |
| 不做拖放/更新/CLI | 全局约束 |
| session API 占位（writeSession/readSession） | 3（P2 才用） |
