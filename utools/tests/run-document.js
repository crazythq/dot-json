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