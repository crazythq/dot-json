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

const withBlank = L.parse('{"a":1}\n\n{"b":2}');
assertEqual(withBlank.count, 2, "blank skipped count");
assertEqual(withBlank.lines[0].index, 0, "blank skip physical 0");
assertEqual(withBlank.lines[1].index, 2, "blank skip physical 2");
assert(withBlank.lines[1].byteOffset > withBlank.lines[0].byteOffset, "byteOffset increases");

if (failed) process.exit(1);
console.log("\nall passed");
