"use strict";
require("../state/document.js");
require("../state/workspace.js");
const WS = globalThis.DotJSONWorkspace;
const Doc = globalThis.DotJSONDocument;
if (!WS) { console.error("missing"); process.exit(1); }

let failed = 0;
function assertEqual(a, e, name) {
  if (JSON.stringify(a) !== JSON.stringify(e)) {
    failed += 1;
    console.error("FAIL", name, a, e);
    return;
  }
  console.log("ok  ", name);
}

let ws = WS.create();
WS.ensureTab(ws);
assertEqual(ws.tabs.length, 1, "ensure one tab");
assertEqual(ws.activeIndex, 0, "active 0");

for (let i = 0; i < 19; i += 1) assertEqual(WS.newTab(ws).ok, true, "newTab " + i);
assertEqual(WS.newTab(ws).ok, false, "21st tab rejected");
assertEqual(ws.tabs.length, 20, "max 20");

WS.activate(ws, 3);
assertEqual(ws.activeIndex, 3, "activate 3");

Doc.setText(WS.activeDoc(ws), "x", { markDirty: true });
const dup = WS.duplicateTab(ws, 3);
assertEqual(dup.ok, false, "dup at max fails"); // already 20

// shrink then dup
ws = WS.create();
WS.ensureTab(ws);
Doc.setText(ws.tabs[0], '{"a":1}', { markDirty: true });
WS.renameTab(ws, 0, "Mine");
assertEqual(ws.tabs[0].title, "Mine", "rename");
assertEqual(WS.duplicateTab(ws, 0).ok, true, "dup ok");
assertEqual(ws.tabs.length, 2, "two after dup");
assertEqual(ws.tabs[1].rawText, '{"a":1}', "dup copies text");

WS.openPath(ws, { filePath: "/tmp/a.json", fileName: "a.json", rawText: "{}" });
WS.openPath(ws, { filePath: "/tmp/a.json", fileName: "a.json", rawText: "{}" });
assertEqual(ws.tabs.filter((t) => t.filePath === "/tmp/a.json").length, 1, "dedupe path");

WS.addRecent(ws, "/tmp/a.json");
WS.addRecent(ws, "/tmp/b.json");
WS.addRecent(ws, "/tmp/a.json");
assertEqual(ws.recentFiles[0], "/tmp/a.json", "recent mru");
assertEqual(ws.recentFiles.length, 2, "recent unique");

const snap = WS.toSnapshot(ws);
const ws2 = WS.fromSnapshot(snap);
assertEqual(ws2.tabs.length, ws.tabs.length, "snapshot roundtrip count");
assertEqual(ws2.activeIndex, ws.activeIndex, "snapshot active");

if (failed) process.exit(1);
console.log("\nall passed");
