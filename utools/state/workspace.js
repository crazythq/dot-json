/**
 * 多标签工作区（无 DOM）。标签上限 20；最近文件上限 10。
 */
(function (global) {
  "use strict";

  const MAX_TABS = 20;
  const MAX_RECENT = 10;

  function Doc() {
    return global.DotJSONDocument;
  }

  function create() {
    return {
      tabs: [],
      activeIndex: 0,
      recentFiles: [],
      nextUntitled: 1,
    };
  }

  function ensureTab(ws) {
    if (!ws.tabs.length) newTab(ws);
  }

  function newTab(ws) {
    if (ws.tabs.length >= MAX_TABS) {
      return { ok: false, error: "max tabs" };
    }
    const doc = Doc().create();
    const n = ws.nextUntitled;
    ws.nextUntitled += 1;
    doc.title = "Untitled " + n;
    ws.tabs.push(doc);
    ws.activeIndex = ws.tabs.length - 1;
    return { ok: true };
  }

  function activate(ws, index) {
    if (index < 0 || index >= ws.tabs.length) return;
    ws.activeIndex = index;
  }

  function activeDoc(ws) {
    if (!ws.tabs.length) return null;
    const i = ws.activeIndex;
    if (i < 0 || i >= ws.tabs.length) return null;
    return ws.tabs[i];
  }

  function closeTab(ws, index) {
    if (index < 0 || index >= ws.tabs.length) return { ok: false };
    ws.tabs.splice(index, 1);
    if (!ws.tabs.length) {
      newTab(ws);
      return { ok: true };
    }
    if (index < ws.activeIndex) {
      ws.activeIndex -= 1;
    } else if (ws.activeIndex >= ws.tabs.length) {
      ws.activeIndex = ws.tabs.length - 1;
    }
    return { ok: true };
  }

  function cloneDoc(src) {
    const doc = Doc().create();
    doc.title = src.title || "";
    doc.rawText = src.rawText == null ? "" : String(src.rawText);
    doc.filePath = src.filePath == null ? null : src.filePath;
    doc.fileName = src.fileName == null ? "" : String(src.fileName);
    doc.indentKey = src.indentKey || "fourSpaces";
    doc.isDirty = !!src.isDirty;
    return doc;
  }

  function duplicateTab(ws, index) {
    if (index < 0 || index >= ws.tabs.length) {
      return { ok: false, error: "invalid index" };
    }
    if (ws.tabs.length >= MAX_TABS) {
      return { ok: false, error: "max tabs" };
    }
    const copy = cloneDoc(ws.tabs[index]);
    copy.filePath = null;
    copy.fileName = "";
    if (copy.title) copy.title = copy.title + " copy";
    ws.tabs.splice(index + 1, 0, copy);
    ws.activeIndex = index + 1;
    return { ok: true };
  }

  function renameTab(ws, index, title) {
    if (index < 0 || index >= ws.tabs.length) return;
    ws.tabs[index].title = title == null ? "" : String(title);
  }

  function openPath(ws, info) {
    const filePath = info && info.filePath ? String(info.filePath) : "";
    if (filePath) {
      for (let i = 0; i < ws.tabs.length; i += 1) {
        if (ws.tabs[i].filePath === filePath) {
          ws.activeIndex = i;
          return { ok: true };
        }
      }
    }
    if (ws.tabs.length >= MAX_TABS) {
      return { ok: false, error: "max tabs" };
    }
    const result = newTab(ws);
    if (!result.ok) return result;
    const doc = activeDoc(ws);
    Doc().setText(doc, info && info.rawText != null ? info.rawText : "", {});
    Doc().setFile(doc, {
      filePath: filePath || null,
      fileName: info && info.fileName ? String(info.fileName) : "",
    });
    if (info && info.indentKey) Doc().setIndent(doc, info.indentKey);
    doc.title = "";
    Doc().markSaved(doc);
    return { ok: true };
  }

  function addRecent(ws, filePath) {
    if (!filePath) return;
    const path = String(filePath);
    const next = [path];
    for (let i = 0; i < ws.recentFiles.length; i += 1) {
      if (ws.recentFiles[i] !== path) next.push(ws.recentFiles[i]);
    }
    ws.recentFiles = next.slice(0, MAX_RECENT);
  }

  function clearRecent(ws) {
    ws.recentFiles = [];
  }

  function toSnapshot(ws) {
    return {
      version: 1,
      activeIndex: ws.activeIndex,
      nextUntitled: ws.nextUntitled,
      tabs: ws.tabs.map(function (t) {
        return {
          rawText: t.rawText,
          filePath: t.filePath,
          fileName: t.fileName,
          indentKey: t.indentKey,
          isDirty: !!t.isDirty,
          title: t.title || "",
        };
      }),
    };
  }

  function fromSnapshot(snapshot) {
    if (!snapshot || typeof snapshot !== "object" || !Array.isArray(snapshot.tabs)) {
      const ws = create();
      ensureTab(ws);
      return ws;
    }
    if (!snapshot.tabs.length) {
      const ws = create();
      ensureTab(ws);
      return ws;
    }
    const ws = create();
    ws.nextUntitled =
      typeof snapshot.nextUntitled === "number" && snapshot.nextUntitled > 0
        ? snapshot.nextUntitled
        : 1;
    for (let i = 0; i < snapshot.tabs.length && ws.tabs.length < MAX_TABS; i += 1) {
      const src = snapshot.tabs[i] || {};
      const doc = Doc().create();
      doc.title = src.title == null ? "" : String(src.title);
      doc.rawText = src.rawText == null ? "" : String(src.rawText);
      doc.filePath = src.filePath == null ? null : String(src.filePath);
      doc.fileName = src.fileName == null ? "" : String(src.fileName);
      doc.indentKey = src.indentKey || "fourSpaces";
      doc.isDirty = !!src.isDirty;
      ws.tabs.push(doc);
    }
    if (!ws.tabs.length) {
      ensureTab(ws);
      return ws;
    }
    let ai = typeof snapshot.activeIndex === "number" ? snapshot.activeIndex : 0;
    if (ai < 0) ai = 0;
    if (ai >= ws.tabs.length) ai = ws.tabs.length - 1;
    ws.activeIndex = ai;
    return ws;
  }

  global.DotJSONWorkspace = {
    MAX_TABS,
    MAX_RECENT,
    create,
    ensureTab,
    newTab,
    activate,
    activeDoc,
    closeTab,
    duplicateTab,
    renameTab,
    openPath,
    addRecent,
    clearRecent,
    toSnapshot,
    fromSnapshot,
  };
})(typeof window !== "undefined" ? window : globalThis);
