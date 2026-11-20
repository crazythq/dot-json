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

const dotted = core.buildRootTree('{"a.b":1,"c":2}');
const dottedKey = dotted.root.children.find((c) => c.key === "a.b");
const delDotted = edit.deleteNodeById(dotted.root, dottedKey.id);
assertEqual(delDotted.ok, true, "delete dotted key ok");
assertEqual(delDotted.value, { c: 2 }, "value after delete a.b key");

const dottedNested = core.buildRootTree('{"a.b":1,"a":{"b":2}}');
const dottedOnly = dottedNested.root.children.find((c) => c.key === "a.b");
const delDottedOnly = edit.deleteNodeById(dottedNested.root, dottedOnly.id);
assertEqual(delDottedOnly.ok, true, "delete a.b leaves nested a.b");
assertEqual(delDottedOnly.value, { a: { b: 2 } }, "value after delete literal a.b");

const bracketKey = core.buildRootTree('{"x[0]":9,"y":1}');
const bracketNode = bracketKey.root.children.find((c) => c.key === "x[0]");
const delBracket = edit.deleteNodeById(bracketKey.root, bracketNode.id);
assertEqual(delBracket.ok, true, "delete bracket key ok");
assertEqual(delBracket.value, { y: 1 }, "value after delete x[0] key");

const arrBuilt = core.buildRootTree("[10,20,30]");
const mid = arrBuilt.root.children[1];
const delMid = edit.deleteNodeById(arrBuilt.root, mid.id);
assertEqual(delMid.ok, true, "delete array index ok");
assertEqual(delMid.value, [10, 30], "value after delete index 1");

if (failed) process.exit(1);
console.log("\nall passed");
