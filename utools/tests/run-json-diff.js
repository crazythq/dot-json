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

const cmpNumKeyRemove = D.compare('{"0":1}', "{}");
const removeZero = cmpNumKeyRemove.rows.find((r) => r.path === "0" && r.kind === "remove");
assert(!!removeZero, "numeric object key remove row");
assertEqual(
  removeZero && removeZero.pathParts,
  [{ type: "key", value: "0" }],
  "numeric object key pathParts is key"
);
const appliedRemoveZero = D.apply(
  removeZero,
  "toLeft",
  cmpNumKeyRemove.leftRoot,
  cmpNumKeyRemove.rightRoot
);
assertEqual(appliedRemoveZero.left, {}, "apply remove numeric object key toLeft");

const cmpNumKeyAdd = D.compare("{}", '{"0":1}');
const addZero = cmpNumKeyAdd.rows.find((r) => r.path === "0" && r.kind === "add");
assert(!!addZero, "numeric object key add row");
assertEqual(
  addZero && addZero.pathParts,
  [{ type: "key", value: "0" }],
  "numeric object key add pathParts is key"
);
const appliedAddZero = D.apply(
  addZero,
  "toRight",
  cmpNumKeyAdd.leftRoot,
  cmpNumKeyAdd.rightRoot
);
assertEqual(appliedAddZero.right, {}, "apply add numeric object key toRight");

const cmpDotKey = D.compare('{"a.b":1}', "{}");
const removeDot = cmpDotKey.rows.find((r) => r.path === "a.b" && r.kind === "remove");
assert(!!removeDot, "dotted object key remove row");
assertEqual(
  removeDot && removeDot.pathParts,
  [{ type: "key", value: "a.b" }],
  "dotted object key pathParts"
);
const appliedDot = D.apply(removeDot, "toLeft", cmpDotKey.leftRoot, cmpDotKey.rightRoot);
assertEqual(appliedDot.left, {}, "apply remove dotted object key toLeft");

let noPartsThrew = false;
try {
  D.apply({ kind: "remove", path: "0" }, "toLeft", { "0": 1 }, {});
} catch (_e) {
  noPartsThrew = true;
}
assert(noPartsThrew, "apply without pathParts throws");

const shrinkAll = D.applyAll(c3.rows, "toLeft", c3.leftRoot, c3.rightRoot).left;
assertEqual(shrinkAll, { items: [9] }, "applyAll shrink array ordered");

if (failed) process.exit(1);
console.log("\nall passed");
