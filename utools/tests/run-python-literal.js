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
