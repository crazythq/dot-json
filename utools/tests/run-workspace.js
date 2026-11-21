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
function assert(cond, name) {
  if (!cond) {
    failed += 1;
    console.error("FAIL", name);
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
assertEqual(Object.prototype.hasOwnProperty.call(snap, "recentFiles"), false, "snapshot omits recent");
assertEqual(Array.isArray(snap.tabs), true, "snapshot has tabs");
const ws2 = WS.fromSnapshot(snap);
assertEqual(ws2.tabs.length, ws.tabs.length, "snapshot roundtrip count");
assertEqual(ws2.activeIndex, ws.activeIndex, "snapshot active");
assertEqual(ws2.tabs.some((t) => t.isDirty), true, "snapshot preserves dirty");

const emptyWs = WS.fromSnapshot({ version: 1, tabs: [] });
assertEqual(emptyWs.tabs.length, 1, "empty snapshot gets one tab");
const badWs = WS.fromSnapshot(null);
assertEqual(badWs.tabs.length, 1, "null snapshot gets one tab");
const dirtySnap = WS.fromSnapshot({
  version: 1,
  activeIndex: 0,
  nextUntitled: 3,
  tabs: [{ rawText: '{"x":1}', filePath: null, fileName: "", indentKey: "twoSpaces", isDirty: true, title: "T" }],
});
assertEqual(dirtySnap.tabs[0].isDirty, true, "fromSnapshot isDirty");
assertEqual(dirtySnap.tabs[0].rawText, '{"x":1}', "fromSnapshot rawText");
assertEqual(dirtySnap.tabs[0].indentKey, "twoSpaces", "fromSnapshot indent");
assertEqual(dirtySnap.nextUntitled, 3, "fromSnapshot nextUntitled");

// closeTab: adjust activeIndex + last tab recreates
ws = WS.create();
WS.ensureTab(ws);
WS.newTab(ws);
WS.newTab(ws);
WS.activate(ws, 2);
assertEqual(WS.closeTab(ws, 0).ok, true, "closeTab ok");
assertEqual(ws.tabs.length, 2, "closeTab length");
assertEqual(ws.activeIndex, 1, "closeTab lowers active when left of active");
WS.activate(ws, 0);
assertEqual(WS.closeTab(ws, 1).ok, true, "close right of active");
assertEqual(ws.activeIndex, 0, "active stays when closing right");
assertEqual(WS.closeTab(ws, 0).ok, true, "close last");
assertEqual(ws.tabs.length, 1, "last close recreates");
assertEqual(ws.activeIndex, 0, "recreated active 0");
assert(!!ws.tabs[0].title, "recreated has untitled title");

// closeOthers
ws = WS.create();
WS.ensureTab(ws);
WS.newTab(ws);
WS.newTab(ws);
WS.activate(ws, 1);
assertEqual(WS.closeOthers(ws, 1).ok, true, "closeOthers ok");
assertEqual(ws.tabs.length, 1, "closeOthers keeps one");
assertEqual(ws.activeIndex, 0, "closeOthers active 0");

// openPath: same path refresh when clean
ws = WS.create();
WS.ensureTab(ws);
WS.openPath(ws, { filePath: "/tmp/r.json", fileName: "r.json", rawText: '{"v":1}' });
assertEqual(ws.tabs[0].rawText, '{"v":1}', "open initial");
const refresh = WS.openPath(ws, { filePath: "/tmp/r.json", fileName: "r.json", rawText: '{"v":2}' });
assertEqual(refresh.ok, true, "refresh ok");
assertEqual(refresh.refreshed, true, "refresh flag");
assertEqual(ws.tabs.length, 1, "refresh no new tab");
assertEqual(ws.tabs[0].rawText, '{"v":2}', "refreshed text");

Doc.setText(ws.tabs[0], '{"dirty":true}', { markDirty: true });
const keep = WS.openPath(ws, { filePath: "/tmp/r.json", fileName: "r.json", rawText: '{"v":9}' });
assertEqual(keep.refreshed, false, "dirty not refreshed");
assertEqual(ws.tabs[0].rawText, '{"dirty":true}', "dirty text kept");

// openPath: reuse empty untitled
ws = WS.create();
WS.ensureTab(ws);
assertEqual(ws.tabs.length, 1, "one empty");
const reused = WS.openPath(ws, { filePath: "/tmp/u.json", fileName: "u.json", rawText: "{}" });
assertEqual(reused.ok, true, "reuse empty ok");
assertEqual(ws.tabs.length, 1, "reuse empty no extra tab");
assertEqual(ws.tabs[0].filePath, "/tmp/u.json", "reuse empty path set");

if (failed) process.exit(1);
console.log("\nall passed");
