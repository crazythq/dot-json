# uTools Feature Parity P3（JSON Diff）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移植路径级 JSON Diff（对照 `DotJSONCore.JSONDiff`）并提供简化双栏 UI：对比、单条/全部应用到左或右，写回选定标签。

**Architecture:** 纯逻辑在 `lib/json-diff.js`（对 `JSON.parse` 得到的 JS 值做 structured diff / apply）；UI 为可开关的 Diff 面板（非独立窗口）：左右选标签或粘贴文本、差异列表、应用按钮。行级 LCS 可选实现，超 2MB 合计跳过（对齐 mac soft limit）。

**Tech Stack:** 纯 HTML/CSS/JS、Node 契约测试、无 npm 业务依赖。

**Spec:** `docs/superpowers/specs/2026-11-19-utools-feature-parity-design.md`（P3）

**Depends on:** P2 已提交（`9cd081a` 或其后继）。

## Global Constraints

- 禁止在 `main` 上直接改代码；从 `feat/utools-parity-p2` 建 `feat/utools-parity-p3`。
- 未经用户明确要求，不要 `git commit`。
- 工具栏文字按钮；不做拖放 / JSONL / 设置页。
- `lib/` 不得依赖 DOM / `utools`。
- Diff 规则对齐 mac：`add` / `remove` / `change`；数组按**下标**对比（不按内容重排匹配）；对象键集合并集排序后递归。
- 路径字符串格式对齐 mac `JSONPath.description`：根下键为 `b`，嵌套 `items.1`（点分隔；数组下标用数字段），**无** `$` 前缀。
- `softInputByteLimit = 2000000`（UTF-8 字节近似可用 `Buffer.byteLength` 或 `TextEncoder`）。

## File Structure

| File | Responsibility |
|------|----------------|
| `utools/lib/json-diff.js` | `compare` / `apply` / `applyAll` / 可选 `makeLineDiff` |
| `utools/tests/run-json-diff.js` | 契约测试（对照 mac JSONDiffTests 核心用例） |
| `utools/app/main.js` | Diff 面板开关、装载左右文本、应用写回标签 |
| `utools/index.html` / `index.css` | Diff 面板 DOM 与样式 |
| `utools/README.md` | P3 验收清单 |

### JS 值模型（相对 Swift JSONNode）

- 输入：两侧 JSON **文本**；内部 `JSON.parse`（非法则 throw `{ side:'left'|'right', message }`）。
- Row：`{ kind, path: string, leftValue, rightValue }`（value 为 JS 值或 `undefined` 表示缺失）。
- Apply 在克隆的 JS 对象/数组上 set/delete；返回新的 `{ left, right }` 值，再 `JSON.stringify`/`DotJSONCore.format` 写回。

---

### Task 0: 功能分支

- [ ] 确认在 `feat/utools-parity-p2` 且 HEAD 含 P2；`git checkout -b feat/utools-parity-p3`。

---

### Task 1: `lib/json-diff.js` + 契约测试

**Interfaces:** `DotJSONDiff`
- `SOFT_INPUT_BYTE_LIMIT = 2000000`
- `compare(leftText, rightText, indentKey?) -> { rows, leftPretty, rightPretty, leftRoot, rightRoot, lineDiff }`
  - `lineDiff`: `{ kind:'available', rows: LineRow[] }` 或 `{ kind:'skipped', message }`
- `apply(row, direction, leftRoot, rightRoot) -> { left, right }`；`direction` 为 `'toLeft'|'toRight'`
- `applyAll(rows, direction, leftRoot, rightRoot) -> { left, right }`
- `pathString(parts)` 内部用；测试断言 `row.path === 'b'` 等

- [ ] **Step 1: 写测试** `utools/tests/run-json-diff.js`（对照 mac）：

```js
"use strict";
require("../lib/json-core.js");
require("../lib/json-diff.js");
const D = globalThis.DotJSONDiff;
if (!D) { console.error("missing"); process.exit(1); }

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

const c1 = D.compare('{"a":1,"b":2}', '{"a":1,"b":3,"c":4}');
assert(c1.rows.some((r) => r.path === "b" && r.kind === "change"), "change b");
assert(c1.rows.some((r) => r.path === "c" && r.kind === "add"), "add c");

const c2 = D.compare('{"items":[1,2]}', '{"items":[1,3]}');
assert(c2.rows.some((r) => r.path === "items.1" && r.kind === "change"), "array index path");

const c3 = D.compare('{"items":[1,2,3]}', '{"items":[9]}');
assert(c3.rows.some((r) => r.path === "items.0" && r.kind === "change"), "shrink change 0");
assert(c3.rows.some((r) => r.path === "items.1" && r.kind === "remove"), "shrink remove 1");
assert(c3.rows.some((r) => r.path === "items.2" && r.kind === "remove"), "shrink remove 2");

let threw = false;
try { D.compare("{", "{}"); } catch (_e) { threw = true; }
assert(threw, "left invalid throws");

const left = { x: 1 };
const right = { x: 2, y: 3 };
const cmp = D.compare(JSON.stringify(left), JSON.stringify(right));
const changeRow = cmp.rows.find((r) => r.path === "x");
const addRow = cmp.rows.find((r) => r.path === "y");
const toLeft = D.apply(changeRow, "toLeft", cmp.leftRoot, cmp.rightRoot);
assertEqual(toLeft.left.x, 2, "apply change toLeft");
const toRight = D.apply(addRow, "toRight", cmp.leftRoot, cmp.rightRoot);
assertEqual(Object.prototype.hasOwnProperty.call(toRight.right, "y"), false, "apply add toRight deletes y");

const left2 = { a: 1, b: 2 };
const right2 = { a: 9, c: 3 };
const cmp2 = D.compare(JSON.stringify(left2), JSON.stringify(right2));
const merged = D.applyAll(cmp2.rows, "toLeft", cmp2.leftRoot, cmp2.rightRoot).left;
assertEqual(merged, right2, "applyAll toLeft equals right");

if (failed) process.exit(1);
console.log("\nall passed");
```

- [ ] **Step 2: 跑红** `node tests/run-json-diff.js`

- [ ] **Step 3: 实现** `lib/json-diff.js`

核心算法（对照 Swift `structuredDiff` / `applyRowToTarget` / `sortRowsForApply`）：

1. `deepEqual` 后无 row。
2. 双方均为 plain object：键并集 `sorted`，仅右→add，仅左→remove，双方→递归。
3. 双方均为 array：按下标 0..max-1，缺失侧 add/remove，双方递归。
4. 否则 → 单条 `change`。
5. `path`：根为空串；子键 `parent ? parent+'.'+key : key`；子下标 `parent ? parent+'.'+index : String(index)`。
6. `apply`：在目标克隆上，按 path 分段（`.` 拆，数字段为 array index，否则 key）执行 set/delete；语义同 Swift 注释（add toLeft 写入 rightValue；add toRight 删除路径；等）。
7. `applyAll`：按 path 深度降序，同深 path 字符串降序。
8. `compare`：parse 两侧；算 rows；`leftPretty`/`rightPretty` 用 `DotJSONCore.format`；若两侧原文 UTF-8 长度之和 > limit，`lineDiff.skipped`，否则可实现简易 LCS 或先返回 `available: []` 并在测试中不强制行级（**本任务契约以上述 structured/apply 为准**；行级可 Task 1 末可选或 Task 2 UI 不做行视图）。

推荐 P3：**先实现 structured + apply，行级 LCS 可省略 UI**；若实现 `makeLineDiff`，补一个小测试即可。

- [ ] **Step 4: 跑绿**

---

### Task 2: Diff 面板 UI（简化）

**Files:** `index.html`、`index.css`、`app/main.js`

- [ ] **Step 1: HTML**  
  - 工具栏按钮「对比」  
  - 面板 `#diff-panel`（默认 hidden）：左/右来源 `<select>`（当前标签列表）+ 「用当前标签」快捷；左右只读或可编辑 textarea 显示 pretty JSON；中间/下方差异表（path、kind、左右摘要）；按钮：应用到左、应用到右、全部到左、全部到右、关闭  

- [ ] **Step 2: 打开 Diff**  
  - 默认左=当前标签，右=另一标签（若仅一页则右为空或同页提示选两个）  
  - 调用 `DotJSONDiff.compare`；失败状态栏错误  
  - 渲染 rows；选中一行后可单条 apply  

- [ ] **Step 3: 应用写回**  
  - apply 后用 `DotJSONCore.format` 得到文本  
  - 写回对应标签的 `Doc.setText` + `markDirty`；若该标签正激活则刷新 editor  
  - 重新 compare 刷新列表  

- [ ] **Step 4: 脚本** `json-diff.js` 挂在 `json-core.js` 之后  

- [ ] **Step 5: 冒烟** 两标签不同 JSON → 对比 → 应用到左 → 左标签变脏且内容更新  

---

### Task 3: README + 回归

- [ ] README 增加 P3 清单：打开对比、差异列表、单条/全部应用、非法 JSON 报错、`node tests/run-json-diff.js`  
- [ ] 跑全套 `run-*.js`；uTools GUI 标人工  

---

## P3 完成标准

- `run-json-diff.js` 全绿；Diff UI 可对比并写回标签；无 P4 功能；无 commit 除非用户要求。

## Spec Coverage

| Spec | Task |
|------|------|
| json-diff 对照移植 | 1 |
| 双栏对比/应用 UI | 2 |
| README | 3 |
