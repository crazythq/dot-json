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
assertEqual(Pref.STORAGE_KEY_DEFAULT_INDENT, "dotjson.defaultIndent", "storage key");
assertEqual(Pref.STORAGE_KEY_AUTO_FORMAT, "dotjson.autoFormat", "auto format key");
assertEqual(Pref.create({}).autoFormat, true, "autoFormat default on");
assertEqual(Pref.create({ autoFormat: false }).autoFormat, false, "autoFormat off");
assertEqual(Pref.normalizeAutoFormat("false"), false, "normalize false string");
assertEqual(Pref.normalizeAutoFormat(true), true, "normalize true");

const ws = WS.create();
WS.ensureTab(ws);
Doc.setIndent(ws.tabs[0], "twoSpaces");
const prefs = Pref.create({ defaultIndent: "tab" });
assertEqual(ws.tabs[0].indentKey, "twoSpaces", "existing untouched");
WS.newTab(ws);
Pref.applyToNewDoc(WS.activeDoc(ws), prefs);
assertEqual(WS.activeDoc(ws).indentKey, "tab", "new tab gets default");

if (failed) process.exit(1);
console.log("\nall passed");
