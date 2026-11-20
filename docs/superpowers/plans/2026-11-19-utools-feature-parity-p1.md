# uTools Feature Parity P1（编辑对齐）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 P0 模块化底座上补齐单文档编辑体验：保存/脏状态/另存为、Python↔JSON、树 Expand/Collapse All/Delete、简易编辑器查找、解析错误行定位（降级）。

**Architecture:** 新算法进 `lib/`（`python-literal.js`、树编辑辅助进 `json-core.js` 或 `lib/tree-edit.js`）；`state/document.js` 补齐脏状态语义；`app/main.js` + `index.html`/`index.css` 挂文字按钮与菜单项。行为对照 mac `EditorViewModel` / `PythonLiteralSerializer` / 树右键。

**Tech Stack:** 纯 HTML/CSS/JS、uTools Plugin API、Node 契约测试、无 npm 业务依赖。

**Spec:** `docs/superpowers/specs/2026-11-19-utools-feature-parity-design.md`（P1 行）

**Depends on:** P0 已合并进当前分支（commit 含 `lib/`/`state/`/`app/`/`window.services`）。

## Global Constraints

- 禁止在 `main` 上直接改代码；在 `feat/utools-parity-p0` 上继续，或新建 `feat/utools-parity-p1`（本计划 Task 0 选定后者）。
- 未经用户明确要求，不要 `git commit`（用户规则优先；本会话用户若已说「提交」则仅按其指示提交）。
- 工具栏保持**文字按钮**，无 macOS 图标。
- 不做拖放、Finder 关联、更新检查、CLI、多标签、Diff、JSONL、设置页（属 P2–P4）。
- `lib/` 不得依赖 `window` / DOM / `utools`。
- `files.maxLength` 保持 `1`。
- 程序化改写正文（格式化/粘贴/转换/删节点/打开）在成功后须正确维护 `isDirty`（见 Task 3）。

## File Structure

| File | Responsibility |
|------|----------------|
| `utools/lib/python-literal.js` | JSON → Python literal；Python/可修复文本 → 标准 JSON（复用 repair+format） |
| `utools/lib/json-core.js` | 增加 `deleteAtPath` / `collectDescendantIds`（或独立 `lib/tree-edit.js`）；解析错误行号辅助 |
| `utools/state/document.js` | 已有接口；必要时加 `savedSnapshot` 对齐「未保存」判断（可选，优先用 `isDirty`） |
| `utools/app/main.js` | 保存/另存为、转换、树菜单、编辑器查找、错误行提示 |
| `utools/index.html` | 文字按钮：保存、另存为、转 Python、转 JSON；编辑器查找条；右键菜单项 |
| `utools/index.css` | 查找条、错误行高亮/状态样式 |
| `utools/tests/run-python-literal.js` | Python 转换契约测试 |
| `utools/tests/run-tree-edit.js` | 删节点 / 子孙 id 契约测试 |
| `utools/README.md` | P1 验收清单 |

---

### Task 0: 功能分支

**Files:** None（仅 git）

**Interfaces:**
- Consumes: 当前 `feat/utools-parity-p0`（含 P0 commit）
- Produces: 分支 `feat/utools-parity-p1`

- [ ] **Step 1: 确认起点**

```bash
cd /Users/tt/Documents/workspace/project/dot-json
git branch --show-current
git log -1 --oneline
git status -sb
```

Expected: 在 `feat/utools-parity-p0`（或已含 P0 的等价提交）；工作区对 utools 宜干净。

- [ ] **Step 2: 创建 P1 分支**

```bash
git checkout -b feat/utools-parity-p1
```

Expected: 当前分支 `feat/utools-parity-p1`。

---

### Task 1: `lib/python-literal.js` + 契约测试

**Files:**
- Create: `utools/lib/python-literal.js`
- Create: `utools/tests/run-python-literal.js`
- Modify: `utools/index.html`（本任务末尾或 Task 4 再挂脚本；本任务先保证 Node 可测）

**Interfaces:**
- Consumes: `DotJSONCore.tryParse` / `repair` / `format` / `INDENTS`
- Produces: `DotJSONPython`
  - `toPython(text, indentKey) -> string`（失败 throw）
  - `toJSON(text, indentKey) -> string`（失败 throw；内部 repair+format）

- [ ] **Step 1: 写失败测试**

创建 `utools/tests/run-python-literal.js`：

```js
"use strict";

require("../lib/json-core.js");
require("../lib/python-literal.js");
const py = globalThis.DotJSONPython;
if (!py) {
  console.error("DotJSONPython missing");
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
  } catch (_e) {
    console.log(`ok   ${name}`);
  }
}

assertEqual(
  py.toPython('{"a":null,"b":true,"c":false,"d":"x"}', "fourSpaces").includes("None"),
  true,
  "toPython contains None"
);
assertEqual(
  py.toPython('{"a": {"b": [1, true, null]}}', "fourSpaces"),
  "{\n    'a': {\n        'b': [\n            1,\n            True,\n            None\n        ]\n    }\n}",
  "toPython nested indent"
);
assertEqual(
  py.toPython('{"s":"a\'b\\\\c\\nd"}', "fourSpaces").includes("'a\\'b\\\\c\\nd'"),
  true,
  "toPython escapes"
);
assertEqual(
  py.toJSON("{'a': True, 'b': None}", "twoSpaces"),
  '{\n  "a": true,\n  "b": null\n}',
  "toJSON via repair+format"
);
assertThrows(() => py.toPython("{bad", "fourSpaces"), "toPython invalid throws");
assertThrows(() => py.toJSON("{unquoted: True}", "fourSpaces"), "toJSON unrepairable throws");

if (failed) {
  console.error(`\n${failed} failed`);
  process.exit(1);
}
console.log("\nall passed");
```

- [ ] **Step 2: 跑测确认失败**

```bash
cd /Users/tt/Documents/workspace/project/dot-json/utools
node tests/run-python-literal.js
```

Expected: missing module 或 FAIL。

- [ ] **Step 3: 实现 `lib/python-literal.js`**

对照 `mac/Sources/DotJSONCore/PythonLiteralSerializer.swift`：

```js
(function (global) {
  "use strict";
  const core = global.DotJSONCore;

  function indentStr(indentKey) {
    return (core.INDENTS && core.INDENTS[indentKey]) || "    ";
  }

  function quote(value) {
    let escaped = "";
    const s = String(value);
    for (let i = 0; i < s.length; i += 1) {
      const code = s.charCodeAt(i);
      const ch = s[i];
      if (ch === "\\") escaped += "\\\\";
      else if (ch === "'") escaped += "\\'";
      else if (ch === "\n") escaped += "\\n";
      else if (ch === "\r") escaped += "\\r";
      else if (ch === "\t") escaped += "\\t";
      else if (code <= 0x1f) escaped += "\\x" + code.toString(16).padStart(2, "0");
      else escaped += ch;
    }
    return "'" + escaped + "'";
  }

  function pythonString(value, indent, level) {
    const prefix = indent.repeat(level);
    const childPrefix = indent.repeat(level + 1);
    if (value !== null && typeof value === "object" && !Array.isArray(value)) {
      const keys = Object.keys(value);
      if (!keys.length) return "{}";
      const items = keys.map(
        (k) => childPrefix + quote(k) + ": " + pythonString(value[k], indent, level + 1)
      );
      return "{\n" + items.join(",\n") + "\n" + prefix + "}";
    }
    if (Array.isArray(value)) {
      if (!value.length) return "[]";
      const items = value.map(
        (item) => childPrefix + pythonString(item, indent, level + 1)
      );
      return "[\n" + items.join(",\n") + "\n" + prefix + "]";
    }
    if (typeof value === "string") return quote(value);
    if (typeof value === "number") return String(value);
    if (typeof value === "boolean") return value ? "True" : "False";
    if (value === null) return "None";
    throw new Error("Unsupported value");
  }

  function toPython(text, indentKey) {
    let parsed = core.tryParse(text);
    if (!parsed.ok) {
      const repaired = core.repair(text);
      parsed = core.tryParse(repaired);
      if (!parsed.ok) throw new Error(parsed.error || "Cannot parse");
    }
    return pythonString(parsed.value, indentStr(indentKey), 0);
  }

  function toJSON(text, indentKey) {
    try {
      return core.format(text, indentKey);
    } catch (_e) {
      return core.format(core.repair(text), indentKey);
    }
  }

  global.DotJSONPython = { toPython, toJSON };
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 4: 跑测通过**

```bash
cd /Users/tt/Documents/workspace/project/dot-json/utools
node tests/run-python-literal.js
```

Expected: `all passed`。若 key 顺序导致嵌套用例失败，改为断言结构包含关系或按 `JSON.parse` 插入序锁定输入键序（输入已是确定序）。

---

### Task 2: 树编辑纯函数（delete / descendant ids）

**Files:**
- Create: `utools/lib/tree-edit.js`
- Create: `utools/tests/run-tree-edit.js`

**Interfaces:**
- Consumes: `DotJSONCore.buildRootTree` / `format` / `findNodeById` / `ancestorIds`
- Produces: `DotJSONTreeEdit`
  - `deleteNodeById(root, nodeId) -> { ok, value?, error? }`（根 id `"0"` 拒绝）
  - `descendantIds(root, nodeId) -> string[]`（含自身与全部子孙，用于 Expand/Collapse All）

- [ ] **Step 1: 写失败测试**

```js
"use strict";
require("../lib/json-core.js");
require("../lib/tree-edit.js");
const core = globalThis.DotJSONCore;
const edit = globalThis.DotJSONTreeEdit;
if (!edit) {
  console.error("DotJSONTreeEdit missing");
  process.exit(1);
}

let failed = 0;
function assertEqual(a, e, name) {
  if (JSON.stringify(a) !== JSON.stringify(e)) {
    failed += 1;
    console.error(`FAIL ${name}`, a, e);
    return;
  }
  console.log(`ok   ${name}`);
}

const built = core.buildRootTree('{"a":1,"b":{"c":2}}');
const root = built.root;
const bNode = root.children.find((c) => c.key === "b");
const cNode = bNode.children[0];

const delRoot = edit.deleteNodeById(root, "0");
assertEqual(delRoot.ok, false, "cannot delete root");

const delC = edit.deleteNodeById(root, cNode.id);
assertEqual(delC.ok, true, "delete nested ok");
assertEqual(delC.value, { a: 1, b: {} }, "value after delete c");

const delB = edit.deleteNodeById(root, bNode.id);
assertEqual(delB.ok, true, "delete b ok");
assertEqual(delB.value, { a: 1 }, "value after delete b");

const ids = edit.descendantIds(root, bNode.id).sort();
assertEqual(ids.includes(bNode.id) && ids.includes(cNode.id), true, "descendants include self+child");

if (failed) process.exit(1);
console.log("\nall passed");
```

- [ ] **Step 2: 跑红**

```bash
node tests/run-tree-edit.js
```

- [ ] **Step 3: 实现 `lib/tree-edit.js`**

```js
(function (global) {
  "use strict";

  function cloneValue(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function deleteByJsonPath(value, jsonPath) {
    if (jsonPath === "$") {
      return { ok: false, error: "cannotDeleteRoot" };
    }
    const path = jsonPath.slice(1); // drop leading $
    const parts = [];
    let i = 0;
    while (i < path.length) {
      if (path[i] === ".") {
        i += 1;
        let start = i;
        while (i < path.length && path[i] !== "." && path[i] !== "[") i += 1;
        parts.push({ type: "key", key: path.slice(start, i) });
      } else if (path[i] === "[") {
        i += 1;
        let start = i;
        while (i < path.length && path[i] !== "]") i += 1;
        parts.push({ type: "index", index: Number(path.slice(start, i)) });
        i += 1; // ]
      } else {
        return { ok: false, error: "badPath" };
      }
    }
    const copy = cloneValue(value);
    let cursor = copy;
    for (let p = 0; p < parts.length - 1; p += 1) {
      const part = parts[p];
      cursor = part.type === "key" ? cursor[part.key] : cursor[part.index];
      if (cursor === undefined) return { ok: false, error: "missing" };
    }
    const last = parts[parts.length - 1];
    if (last.type === "key") {
      if (!Object.prototype.hasOwnProperty.call(cursor, last.key)) {
        return { ok: false, error: "missing" };
      }
      delete cursor[last.key];
    } else {
      if (!Array.isArray(cursor) || last.index < 0 || last.index >= cursor.length) {
        return { ok: false, error: "missing" };
      }
      cursor.splice(last.index, 1);
    }
    return { ok: true, value: copy };
  }

  function deleteNodeById(root, nodeId) {
    if (!root || nodeId === "0" || nodeId === root.id) {
      return { ok: false, error: "cannotDeleteRoot" };
    }
    const node = global.DotJSONCore.findNodeById(root, nodeId);
    if (!node) return { ok: false, error: "missing" };
    return deleteByJsonPath(root.value, node.jsonPath);
  }

  function descendantIds(root, nodeId) {
    const node = global.DotJSONCore.findNodeById(root, nodeId);
    if (!node) return [];
    const out = [];
    function walk(n) {
      out.push(n.id);
      (n.children || []).forEach(walk);
    }
    walk(node);
    return out;
  }

  global.DotJSONTreeEdit = { deleteNodeById, descendantIds };
})(typeof window !== "undefined" ? window : globalThis);
```

- [ ] **Step 4: 跑绿**

```bash
node tests/run-tree-edit.js
```

---

### Task 3: 保存 / 脏状态 / 另存为（UI + document 语义）

**Files:**
- Modify: `utools/index.html`
- Modify: `utools/app/main.js`
- Modify: `utools/index.css`（可选：脏标记 `•` 文件名）

**Interfaces:**
- Consumes: `window.services.writeTextFile`、`utools.showSaveDialog`、`DotJSONDocument`
- Produces: 按钮「保存」「另存为」；`⌘S`/`Ctrl+S` 保存（有路径则写回，否则另存为）；成功 `markSaved`；用户编辑与程序化成功改写后的脏语义如下：
  - 用户 `input` → `markDirty`
  - 打开文件 / 清空 → `markSaved`（已有）
  - 格式化/压缩/修复/粘贴成功/转换成功/删节点写回 → `markDirty`（内容相对磁盘已变）
  - 导出成功且路径更新 → `markSaved`

- [ ] **Step 1: HTML 增加文字按钮**

在打开/导出那一组加入：

```html
<button type="button" id="btn-save" title="保存">保存</button>
<button type="button" id="btn-save-as" title="另存为">另存为</button>
```

文件标签旁可显示脏标记：`<span id="dirty-mark" hidden>•</span>`。

- [ ] **Step 2: `main.js` 实现 `saveDocument` / `saveDocumentAs` / `updateDirtyMark`**

伪代码要点：

```js
function updateDirtyMark() {
  const mark = document.getElementById("dirty-mark");
  if (mark) mark.hidden = !doc.isDirty;
}

function saveDocument() {
  if (!doc.filePath) return saveDocumentAs();
  try {
    services.writeTextFile(doc.filePath, els.editor.value);
    Doc.setText(doc, els.editor.value, { markDirty: false });
    Doc.markSaved(doc);
    updateDirtyMark();
    setStatus(`已保存 ${doc.fileName}`, "ok");
  } catch (err) {
    setStatus(`保存失败: ${err.message || err}`, "error");
  }
}

function saveDocumentAs() {
  // showSaveDialog → writeTextFile → setFile → markSaved
}
```

将 `⌘S` 从「导出」改为调用 `saveDocument`。

凡 `setEditorText` 用于 format/minify/repair/paste/convert/delete 写回处，成功后 `Doc.markDirty(doc)` 并 `updateDirtyMark()`（打开/清空仍 `markSaved`）。

- [ ] **Step 3: 浏览器冒烟**

打开 `index.html`，编辑后文件名旁应可脏；无 `utools` 时保存可提示不支持或回退另存为不可用——状态栏明确错误即可。

---

### Task 4: 工具栏「转 Python / 转 JSON」

**Files:**
- Modify: `utools/index.html`（脚本加入 `python-literal.js`；按钮）
- Modify: `utools/app/main.js`

**Interfaces:**
- Consumes: `DotJSONPython.toPython` / `toJSON`、当前 `doc.indentKey`

- [ ] **Step 1: HTML**

在修复按钮旁：

```html
<button type="button" id="btn-to-python" title="转为 Python 字面量">转 Python</button>
<button type="button" id="btn-to-json" title="转为标准 JSON">转 JSON</button>
```

`<script src="lib/python-literal.js"></script>` 放在 `json-core.js` 之后、`state/document.js` 之前。

- [ ] **Step 2: 绑定**

成功则 `setEditorText` 新文本并 `markDirty`；失败状态栏错误、保留原文。

- [ ] **Step 3: 回归**

```bash
node tests/run-json-core.js
node tests/run-python-literal.js
node tests/run-document.js
```

---

### Task 5: 树右键 Expand All / Collapse All / Delete

**Files:**
- Modify: `utools/index.html`（菜单项）
- Modify: `utools/app/main.js`
- Modify: `utools/index.html` 脚本加入 `tree-edit.js`

**Interfaces:**
- Consumes: `DotJSONTreeEdit.descendantIds` / `deleteNodeById`、`DotJSONCore.format`

- [ ] **Step 1: 菜单 HTML**

```html
<li data-action="expand-all">Expand All</li>
<li data-action="collapse-all">Collapse All</li>
<li data-action="delete-node">Delete Node</li>
```

- [ ] **Step 2: 处理**

- `expand-all`：`descendantIds` 全部 `state.expanded.add`
- `collapse-all`：子孙 id 从 `expanded` 删除；若含自身则收起（根策略：collapse 根时保留根展开亦可，对齐 mac「当前节点及子」——收起子树时节点本身可保持可见为折叠）
- `delete-node`：确认 `window.confirm`；`deleteNodeById`；成功则 `format` 写回编辑器并 `markDirty`；根拒绝并 `setStatus` 错误

- [ ] **Step 3: 跑 `run-tree-edit.js` + 手工点树菜单**

---

### Task 6: 简易编辑器查找（降级）

**Files:**
- Modify: `utools/index.html`（文本面板 header 增加查找条）
- Modify: `utools/app/main.js`
- Modify: `utools/index.css`

**Interfaces:**
- 查找条：`input#editor-search`、上一项/下一项按钮、计数
- `⌘F`/`Ctrl+F` 在编辑器聚焦时聚焦该查找条（不再完全交给浏览器默认；textarea 内拦截）

- [ ] **Step 1: HTML** 在 `.pane-editor .pane-header` 增加与树搜索类似的控件（文字按钮 ↑↓）。

- [ ] **Step 2: 逻辑**

对 `els.editor.value` 做大小写敏感的 `indexOf` 收集所有命中 offset；下一项/上一项选中对应子串（`setSelectionRange` + `scroll` 尽力）；计数 `i/n`。空查询清空。

- [ ] **Step 3: 冒烟** 输入文本、查找跳转。

---

### Task 7: 解析错误行定位（降级）

**Files:**
- Modify: `utools/lib/json-core.js`（可选 `parseErrorLine(text)`）
- Modify: `utools/app/main.js` / `index.css`

**Interfaces:**
- Produces: 解析失败时状态栏含行号（若可解析）；树区错误文案含 `line N`；尽量 `textarea` 选中该行（无完整行号标尺）

- [ ] **Step 1: 测试**（可放 `run-json-core.js` 追加）

```js
// 若实现 parseErrorLine：
// assertEqual(core.parseErrorLine('{invalid'), 1, "error line")
```

从 `JSON.parse` 异常 message 提取位置（V8 `position`）换算行号；无法提取则返回 `null`，UI 仅显示原始错误。

- [ ] **Step 2: `refreshTree` 失败分支** 调用并更新状态栏 / 尝试选中行。

---

### Task 8: README P1 验收清单

**Files:**
- Modify: `utools/README.md`

- [ ] **Step 1: 写入 P1 清单**

1. 保存 / 另存为 / ⌘S  
2. 编辑后脏标记；保存后清除  
3. 转 Python / 转 JSON  
4. 树 Expand All / Collapse All / Delete（根不可删）  
5. 编辑器查找上/下一项  
6. 非法 JSON 时错误含行号（能提取时）  
7. `node tests/run-*.js` 全绿  

- [ ] **Step 2: 跑全套 Node 测试；uTools 点验能做的项，不能做的在报告标明。**

---

## P1 完成标准

- 上述 Node 测试全绿。
- 能力矩阵 P1「能做/降级」项具备对应用户任务。
- 无 P2+ 功能混入；文字工具栏；无 commit 除非用户要求。

## Spec Coverage

| Spec P1 项 | Task |
|------------|------|
| 保存/脏状态/另存为 | 3 |
| Python ↔ JSON | 1, 4 |
| Expand/Collapse All、Delete | 2, 5 |
| 简易编辑器查找 | 6 |
| 错误定位降级 | 7 |
| README 验收 | 8 |
