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

// —— parseErrorLine（V8 position → 行号）——
assertEqual(core.parseErrorLine("{invalid"), 1, "error line");
assertEqual(
  core.parseErrorLine('{\n  "a": 1,\n  invalid\n}'),
  3,
  "error line multiline"
);
assertEqual(core.parseErrorLine(""), null, "error line empty returns null");

if (failed) {
  console.error(`\n${failed} failed`);
  process.exit(1);
}
console.log("\nall passed");
