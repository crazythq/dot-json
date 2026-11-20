(() => {
  "use strict";

  const core = window.DotJSONCore;
  const Diff = window.DotJSONDiff;
  const Doc = window.DotJSONDocument;
  const WS = window.DotJSONWorkspace;
  const py = window.DotJSONPython;
  const treeEdit = window.DotJSONTreeEdit;
  const services = window.services;

  let ws = WS.create();
  WS.ensureTab(ws);
  let sessionWriteTimer = null;
  const RECENT_KEY = "dotjson.recentFiles";

  const els = {
    editor: document.getElementById("editor"),
    tree: document.getElementById("tree"),
    status: document.getElementById("status"),
    fileLabel: document.getElementById("file-label"),
    indent: document.getElementById("indent-select"),
    treeSearch: document.getElementById("tree-search"),
    searchCount: document.getElementById("search-count"),
    editorSearch: document.getElementById("editor-search"),
    editorSearchCount: document.getElementById("editor-search-count"),
    menu: document.getElementById("context-menu"),
    tabMenu: document.getElementById("tab-context-menu"),
    recentMenu: document.getElementById("recent-menu"),
    btnRecent: document.getElementById("btn-recent"),
    tabList: document.getElementById("tab-list"),
    splitter: document.getElementById("splitter"),
    editorPane: document.querySelector(".pane-editor"),
    diffPanel: document.getElementById("diff-panel"),
    diffLeftSelect: document.getElementById("diff-left-select"),
    diffRightSelect: document.getElementById("diff-right-select"),
    diffLeftText: document.getElementById("diff-left-text"),
    diffRightText: document.getElementById("diff-right-text"),
    diffRows: document.getElementById("diff-rows"),
  };

  const state = {
    root: null,
    expanded: new Set(["0"]),
    selectedId: null,
    contextNodeId: null,
    tabMenuIndex: -1,
    matches: [],
    matchIndex: -1,
    editorMatches: [],
    editorMatchIndex: -1,
    searchTimer: null,
    editorSearchTimer: null,
    parseTimer: null,
    lastParseOk: true,
    diffCompare: null,
    diffSelectedPath: null,
    diffCompareTimer: null,
  };

  function activeDoc() {
    return WS.activeDoc(ws);
  }

  function tabDisplayName(doc, index) {
    if (doc.title) return doc.title;
    if (doc.fileName) return doc.fileName;
    return "Untitled " + (index + 1);
  }

  function flushEditorToActiveDoc() {
    const doc = activeDoc();
    if (!doc) return;
    Doc.setText(doc, els.editor.value, {});
    Doc.setIndent(doc, els.indent.value);
  }

  function persistSession() {
    if (!services || typeof services.writeSession !== "function") return;
    try {
      flushEditorToActiveDoc();
      services.writeSession(JSON.stringify(WS.toSnapshot(ws)));
    } catch (err) {
      /* 无 utools / 写失败时不抛 */
    }
  }

  function schedulePersistSession() {
    if (!services || typeof services.writeSession !== "function") return;
    if (sessionWriteTimer) clearTimeout(sessionWriteTimer);
    sessionWriteTimer = setTimeout(() => {
      sessionWriteTimer = null;
      persistSession();
    }, 300);
  }

  function loadRecentFromDb() {
    if (!window.utools || !utools.dbStorage || typeof utools.dbStorage.getItem !== "function") {
      return;
    }
    try {
      const stored = utools.dbStorage.getItem(RECENT_KEY);
      if (!Array.isArray(stored)) return;
      ws.recentFiles = stored
        .filter(function (p) {
          return typeof p === "string" && p;
        })
        .slice(0, WS.MAX_RECENT);
    } catch (err) {
      /* 无 utools / 读失败时不抛 */
    }
  }

  function persistRecent() {
    if (!window.utools || !utools.dbStorage || typeof utools.dbStorage.setItem !== "function") {
      return;
    }
    try {
      utools.dbStorage.setItem(RECENT_KEY, ws.recentFiles.slice());
    } catch (err) {
      /* 无 utools / 写失败时不抛 */
    }
  }

  function rememberRecent(filePath) {
    if (!filePath) return;
    WS.addRecent(ws, filePath);
    persistRecent();
  }

  function removeRecent(filePath) {
    if (!filePath) return;
    const path = String(filePath);
    ws.recentFiles = ws.recentFiles.filter(function (p) {
      return p !== path;
    });
    persistRecent();
  }

  function hideRecentMenu() {
    if (els.recentMenu) els.recentMenu.hidden = true;
  }

  function showRecentMenu() {
    if (!els.recentMenu || !els.btnRecent) return;
    els.recentMenu.innerHTML = "";
    if (!ws.recentFiles.length) {
      const empty = document.createElement("li");
      empty.className = "is-empty";
      empty.textContent = "暂无最近文件";
      els.recentMenu.appendChild(empty);
    } else {
      ws.recentFiles.forEach(function (filePath) {
        const item = document.createElement("li");
        item.dataset.path = filePath;
        item.textContent = filePath;
        item.title = filePath;
        els.recentMenu.appendChild(item);
      });
    }
    els.recentMenu.hidden = false;
    const btnRect = els.btnRecent.getBoundingClientRect();
    const menuRect = els.recentMenu.getBoundingClientRect();
    const maxX = window.innerWidth - menuRect.width - 4;
    const maxY = window.innerHeight - menuRect.height - 4;
    els.recentMenu.style.left = `${Math.max(0, Math.min(btnRect.left, maxX))}px`;
    els.recentMenu.style.top = `${Math.max(0, Math.min(btnRect.bottom + 2, maxY))}px`;
  }

  function openRecentPath(filePath) {
    if (!filePath) return;
    if (!services || typeof services.readTextFile !== "function") {
      setStatus("当前环境不支持打开文件", "error");
      return;
    }
    try {
      const content = services.readTextFile(filePath);
      const fileName = filePath.split(/[/\\]/).pop();
      flushEditorToActiveDoc();
      let rawText = content;
      try {
        rawText = core.format(content, els.indent.value);
      } catch (err) {
        rawText = content;
      }
      const result = WS.openPath(ws, {
        filePath,
        fileName,
        rawText,
        indentKey: els.indent.value,
      });
      if (!result.ok) {
        setStatus(result.error === "max tabs" ? "标签已达上限（20）" : "打开失败", "error");
        return;
      }
      bindActiveDocToEditor();
      rememberRecent(filePath);
      schedulePersistSession();
      setStatus(`已打开 ${fileName}`, "ok");
    } catch (err) {
      removeRecent(filePath);
      setStatus(`打开失败: ${err.message || err}`, "error");
    }
  }

  function restoreSession() {
    let raw = null;
    if (services && typeof services.readSession === "function") {
      try {
        raw = services.readSession();
      } catch (err) {
        raw = null;
      }
    }
    if (raw) {
      try {
        ws = WS.fromSnapshot(JSON.parse(raw));
      } catch (err) {
        WS.ensureTab(ws);
      }
    } else {
      WS.ensureTab(ws);
    }
    loadRecentFromDb();
    bindActiveDocToEditor();
  }

  function bindActiveDocToEditor() {
    const doc = activeDoc();
    if (!doc) return;
    els.editor.value = doc.rawText == null ? "" : String(doc.rawText);
    els.indent.value = doc.indentKey || "fourSpaces";
    state.expanded = new Set(["0"]);
    state.selectedId = null;
    state.matches = [];
    state.matchIndex = -1;
    state.editorMatches = [];
    state.editorMatchIndex = -1;
    syncFileLabel();
    updateDirtyMark();
    if (els.editorSearch.value) applyEditorSearch(els.editorSearch.value, { silent: true });
    else updateEditorSearchCount();
    refreshTree();
    renderTabs();
  }

  function renderTabs() {
    if (!els.tabList) return;
    els.tabList.innerHTML = "";
    ws.tabs.forEach((doc, index) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "tab-item" + (index === ws.activeIndex ? " is-active" : "");
      btn.setAttribute("role", "tab");
      btn.setAttribute("aria-selected", index === ws.activeIndex ? "true" : "false");
      btn.dataset.index = String(index);
      const label = tabDisplayName(doc, index);
      btn.textContent = doc.isDirty ? "• " + label : label;
      btn.title = label;
      btn.addEventListener("click", () => switchToTab(index));
      btn.addEventListener("dblclick", (event) => {
        event.preventDefault();
        renameTabAt(index);
      });
      btn.addEventListener("contextmenu", (event) => {
        event.preventDefault();
        showTabMenu(event.clientX, event.clientY, index);
      });
      els.tabList.appendChild(btn);
    });
  }

  function switchToTab(index) {
    if (index < 0 || index >= ws.tabs.length) return;
    if (index === ws.activeIndex) {
      renderTabs();
      return;
    }
    flushEditorToActiveDoc();
    WS.activate(ws, index);
    bindActiveDocToEditor();
    schedulePersistSession();
  }

  function createNewTab() {
    flushEditorToActiveDoc();
    const result = WS.newTab(ws);
    if (!result.ok) {
      setStatus("标签已达上限（20）", "error");
      return;
    }
    bindActiveDocToEditor();
    schedulePersistSession();
    setStatus("已新建标签", "ok");
  }

  function renameTabAt(index) {
    if (index < 0 || index >= ws.tabs.length) return;
    const doc = ws.tabs[index];
    const current = tabDisplayName(doc, index);
    const next = window.prompt("重命名标签", current);
    if (next == null) return;
    const trimmed = String(next).trim();
    if (!trimmed) return;
    WS.renameTab(ws, index, trimmed);
    renderTabs();
    if (index === ws.activeIndex) syncFileLabel();
    schedulePersistSession();
  }

  function closeTabAt(index) {
    if (index < 0 || index >= ws.tabs.length) return;
    flushEditorToActiveDoc();
    WS.closeTab(ws, index);
    bindActiveDocToEditor();
    schedulePersistSession();
  }

  function duplicateTabAt(index) {
    if (index < 0 || index >= ws.tabs.length) return;
    flushEditorToActiveDoc();
    const result = WS.duplicateTab(ws, index);
    if (!result.ok) {
      setStatus(result.error === "max tabs" ? "标签已达上限（20）" : "复制失败", "error");
      return;
    }
    bindActiveDocToEditor();
    schedulePersistSession();
    setStatus("已复制标签", "ok");
  }

  function closeOtherTabs(keepIndex) {
    if (keepIndex < 0 || keepIndex >= ws.tabs.length) return;
    flushEditorToActiveDoc();
    const keep = ws.tabs[keepIndex];
    ws.tabs = [keep];
    ws.activeIndex = 0;
    bindActiveDocToEditor();
    schedulePersistSession();
    setStatus("已关闭其他标签", "ok");
  }

  function hideTabMenu() {
    if (els.tabMenu) els.tabMenu.hidden = true;
    state.tabMenuIndex = -1;
  }

  function showTabMenu(x, y, index) {
    if (!els.tabMenu) return;
    state.tabMenuIndex = index;
    els.tabMenu.hidden = false;
    const rect = els.tabMenu.getBoundingClientRect();
    const maxX = window.innerWidth - rect.width - 4;
    const maxY = window.innerHeight - rect.height - 4;
    els.tabMenu.style.left = `${Math.max(0, Math.min(x, maxX))}px`;
    els.tabMenu.style.top = `${Math.max(0, Math.min(y, maxY))}px`;
  }

  Doc.setIndent(activeDoc(), els.indent.value);

  function setStatus(message, kind) {
    els.status.textContent = message;
    els.status.classList.remove("is-error", "is-ok");
    if (kind === "error") els.status.classList.add("is-error");
    if (kind === "ok") els.status.classList.add("is-ok");
  }

  function syncFileLabel() {
    const doc = activeDoc();
    els.fileLabel.textContent = doc && doc.fileName ? doc.fileName : "";
  }

  function updateDirtyMark() {
    const doc = activeDoc();
    const mark = document.getElementById("dirty-mark");
    if (mark) mark.hidden = !(doc && doc.isDirty);
    renderTabs();
  }

  function markProgrammaticDirty() {
    const doc = activeDoc();
    if (!doc) return;
    Doc.markDirty(doc);
    updateDirtyMark();
  }

  function copyText(text) {
    if (window.utools && typeof utools.copyText === "function") {
      utools.copyText(String(text ?? ""));
      return;
    }
    if (services && typeof services.writeClipboard === "function") {
      services.writeClipboard(text);
      return;
    }
    navigator.clipboard.writeText(String(text ?? ""));
  }

  function readClipboard() {
    if (services && typeof services.readClipboard === "function") {
      return services.readClipboard();
    }
    return "";
  }

  function setEditorText(text, opts) {
    const options = opts || {};
    const value = text == null ? "" : String(text);
    const doc = activeDoc();
    els.editor.value = value;
    if (doc) Doc.setText(doc, value, { markDirty: false });
    if (options.filePath && doc) {
      Doc.setFile(doc, {
        filePath: options.filePath,
        fileName: options.fileName || options.filePath.split(/[/\\]/).pop(),
      });
      syncFileLabel();
    } else if (options.clearFile && doc) {
      Doc.clearFile(doc);
      syncFileLabel();
    }
    if ((options.filePath || options.clearFile) && doc) {
      Doc.markSaved(doc);
    }
    updateDirtyMark();
    scheduleParse(options.immediate);
  }

  function scheduleParse(immediate) {
    clearTimeout(state.parseTimer);
    if (immediate) {
      refreshTree();
      return;
    }
    state.parseTimer = setTimeout(refreshTree, 180);
  }

  function refreshTree() {
    const text = els.editor.value;
    if (!text.trim()) {
      state.root = null;
      state.matches = [];
      state.matchIndex = -1;
      state.lastParseOk = true;
      els.tree.innerHTML = '<div class="tree-empty">输入 JSON 后在此显示树结构</div>';
      setStatus("空文档");
      updateSearchCount();
      return;
    }

    const built = core.buildRootTree(text);
    if (!built.ok) {
      state.root = null;
      state.matches = [];
      state.matchIndex = -1;
      const line = core.parseErrorLine(text);
      const lineHint = line != null ? `line ${line}` : null;
      const detail = lineHint ? `${built.error}\n${lineHint}` : built.error;
      els.tree.innerHTML = `<div class="tree-error">解析失败\n${escapeHtml(detail)}</div>`;
      setStatus(lineHint ? `${built.error} (${lineHint})` : built.error, "error");
      if (line != null && state.lastParseOk) selectEditorLine(line);
      state.lastParseOk = false;
      updateSearchCount();
      return;
    }

    state.root = built.root;
    state.lastParseOk = true;
    if (!state.expanded.has("0")) state.expanded.add("0");
    renderTree();
    applySearch(els.treeSearch.value, { silent: true });
    setStatus("有效 JSON", "ok");
  }

  function escapeHtml(text) {
    return String(text)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function renderTree() {
    if (!state.root) return;
    const frag = document.createDocumentFragment();
    const activeId =
      state.matchIndex >= 0 && state.matches[state.matchIndex]
        ? state.matches[state.matchIndex].id
        : null;
    const matchIds = new Set(state.matches.map((m) => m.id));

    function walk(node, depth) {
      const row = document.createElement("div");
      row.className = "tree-node";
      row.dataset.id = node.id;
      row.style.paddingLeft = `${8 + depth * 14}px`;

      if (state.selectedId === node.id) row.classList.add("is-selected");
      if (matchIds.has(node.id)) row.classList.add("is-match");
      if (activeId === node.id) row.classList.add("is-active-match");

      const hasChildren = node.children && node.children.length > 0;
      const expanded = state.expanded.has(node.id);
      const twistie = document.createElement("span");
      twistie.className = "tree-twistie" + (hasChildren ? "" : " is-leaf");
      twistie.textContent = hasChildren ? (expanded ? "▾" : "▸") : "·";
      row.appendChild(twistie);

      if (node.key !== "" && node.jsonPath !== "$") {
        const keyEl = document.createElement("span");
        keyEl.className = "tree-key";
        keyEl.textContent = node.key;
        row.appendChild(keyEl);
        const colon = document.createElement("span");
        colon.className = "tree-colon";
        colon.textContent = ":";
        row.appendChild(colon);
      }

      const valueEl = document.createElement("span");
      valueEl.className = `tree-value type-${node.type}`;
      valueEl.textContent = node.summary;
      row.appendChild(valueEl);

      frag.appendChild(row);

      if (hasChildren && expanded) {
        node.children.forEach((child) => walk(child, depth + 1));
      }
    }

    walk(state.root, 0);
    els.tree.innerHTML = "";
    els.tree.appendChild(frag);

    if (activeId) {
      const activeRow = els.tree.querySelector(`[data-id="${CSS.escape(activeId)}"]`);
      if (activeRow) activeRow.scrollIntoView({ block: "nearest" });
    }
  }

  function toggleExpand(id) {
    if (state.expanded.has(id)) state.expanded.delete(id);
    else state.expanded.add(id);
    renderTree();
  }

  function applySearch(query, opts) {
    const options = opts || {};
    state.matches = [];
    state.matchIndex = -1;
    if (!state.root || !query || !query.trim()) {
      updateSearchCount();
      if (!options.silent) renderTree();
      else renderTree();
      return;
    }

    core.collectSearchMatches(state.root, query.trim(), state.matches);
    if (state.matches.length) {
      state.matchIndex = 0;
      expandToMatch(state.matches[0].id);
    }
    updateSearchCount();
    renderTree();
  }

  function expandToMatch(id) {
    const ancestors = core.ancestorIds(state.root, id);
    ancestors.forEach((aid) => state.expanded.add(aid));
    state.expanded.add(id);
  }

  function updateSearchCount() {
    if (!els.treeSearch.value.trim() || !state.matches.length) {
      els.searchCount.textContent = state.matches.length ? "0/0" : "";
      return;
    }
    els.searchCount.textContent = `${state.matchIndex + 1}/${state.matches.length}`;
  }

  function gotoMatch(delta) {
    if (!state.matches.length) return;
    state.matchIndex = (state.matchIndex + delta + state.matches.length) % state.matches.length;
    expandToMatch(state.matches[state.matchIndex].id);
    updateSearchCount();
    renderTree();
  }

  function collectEditorOffsets(text, query) {
    const offsets = [];
    if (!query) return offsets;
    let from = 0;
    while (from <= text.length) {
      const idx = text.indexOf(query, from);
      if (idx === -1) break;
      offsets.push(idx);
      from = idx + query.length;
      if (query.length === 0) break;
    }
    return offsets;
  }

  function updateEditorSearchCount() {
    const query = els.editorSearch.value;
    if (!query) {
      els.editorSearchCount.textContent = "";
      return;
    }
    if (!state.editorMatches.length) {
      els.editorSearchCount.textContent = "0/0";
      return;
    }
    els.editorSearchCount.textContent = `${state.editorMatchIndex + 1}/${state.editorMatches.length}`;
  }

  function scrollEditorToOffset(offset) {
    const text = els.editor.value;
    const before = text.slice(0, offset);
    const lineIndex = before.split("\n").length - 1;
    const style = window.getComputedStyle(els.editor);
    const lineHeight = parseFloat(style.lineHeight) || parseFloat(style.fontSize) * 1.4 || 18;
    const paddingTop = parseFloat(style.paddingTop) || 0;
    const viewLines = Math.max(1, Math.floor(els.editor.clientHeight / lineHeight));
    const targetTop = paddingTop + lineIndex * lineHeight - lineHeight * Math.floor(viewLines / 3);
    els.editor.scrollTop = Math.max(0, targetTop);
  }

  /** 选中 textarea 中 1-based 行（尽力滚动到可视区）。 */
  function selectEditorLine(line) {
    if (line == null || line < 1) return;
    const text = els.editor.value;
    const lines = text.split("\n");
    const index = Math.min(line - 1, lines.length - 1);
    let start = 0;
    for (let i = 0; i < index; i += 1) {
      start += lines[i].length + 1;
    }
    const end = start + (lines[index] ? lines[index].length : 0);
    try {
      els.editor.focus();
      els.editor.setSelectionRange(start, end);
      scrollEditorToOffset(start);
    } catch (_err) {
      /* ignore selection failures in headless contexts */
    }
  }

  function selectEditorMatch(index) {
    const query = els.editorSearch.value;
    const start = state.editorMatches[index];
    if (start == null || !query) return;
    const end = start + query.length;
    els.editor.focus();
    els.editor.setSelectionRange(start, end);
    scrollEditorToOffset(start);
  }

  function applyEditorSearch(query, opts) {
    const options = opts || {};
    const q = query == null ? "" : String(query);
    state.editorMatches = [];
    state.editorMatchIndex = -1;
    if (!q) {
      updateEditorSearchCount();
      return;
    }
    state.editorMatches = collectEditorOffsets(els.editor.value, q);
    if (state.editorMatches.length) {
      state.editorMatchIndex = 0;
      if (!options.silent) selectEditorMatch(0);
    }
    updateEditorSearchCount();
  }

  function gotoEditorMatch(delta) {
    const query = els.editorSearch.value;
    if (!query) return;
    state.editorMatches = collectEditorOffsets(els.editor.value, query);
    if (!state.editorMatches.length) {
      state.editorMatchIndex = -1;
      updateEditorSearchCount();
      return;
    }
    if (state.editorMatchIndex < 0) state.editorMatchIndex = 0;
    else {
      state.editorMatchIndex =
        (state.editorMatchIndex + delta + state.editorMatches.length) % state.editorMatches.length;
    }
    selectEditorMatch(state.editorMatchIndex);
    updateEditorSearchCount();
  }

  function formatEditor() {
    try {
      const indent = els.indent.value;
      let text = els.editor.value;
      try {
        text = core.format(text, indent);
      } catch (err) {
        text = core.format(core.repair(text), indent);
      }
      setEditorText(text, { immediate: true });
      markProgrammaticDirty();
      setStatus("已格式化", "ok");
    } catch (err) {
      setStatus(err.message || String(err), "error");
    }
  }

  function minifyEditor() {
    try {
      let text = els.editor.value;
      try {
        text = core.minify(text);
      } catch (err) {
        text = core.minify(core.repair(text));
      }
      setEditorText(text, { immediate: true });
      markProgrammaticDirty();
      setStatus("已压缩", "ok");
    } catch (err) {
      setStatus(err.message || String(err), "error");
    }
  }

  function repairEditor() {
    try {
      const repaired = core.repair(els.editor.value);
      const indent = els.indent.value;
      const formatted = core.format(repaired, indent);
      setEditorText(formatted, { immediate: true });
      markProgrammaticDirty();
      setStatus("已修复并格式化", "ok");
    } catch (err) {
      setStatus(err.message || String(err), "error");
    }
  }

  function toPythonEditor() {
    try {
      const doc = activeDoc();
      const text = py.toPython(els.editor.value, doc ? doc.indentKey : els.indent.value);
      setEditorText(text, { immediate: true });
      markProgrammaticDirty();
      setStatus("已转为 Python", "ok");
    } catch (err) {
      setStatus(err.message || String(err), "error");
    }
  }

  function toJSONEditor() {
    try {
      const doc = activeDoc();
      const text = py.toJSON(els.editor.value, doc ? doc.indentKey : els.indent.value);
      setEditorText(text, { immediate: true });
      markProgrammaticDirty();
      setStatus("已转为 JSON", "ok");
    } catch (err) {
      setStatus(err.message || String(err), "error");
    }
  }

  async function pasteAndFormat() {
    const clip = readClipboard();
    if (!clip) {
      setStatus("剪贴板为空", "error");
      return;
    }
    try {
      const indent = els.indent.value;
      let text = clip;
      try {
        text = core.format(clip, indent);
      } catch (err) {
        text = core.format(core.repair(clip), indent);
      }
      setEditorText(text, { immediate: true });
      markProgrammaticDirty();
      setStatus("已粘贴并格式化", "ok");
    } catch (err) {
      setEditorText(clip, { immediate: true });
      markProgrammaticDirty();
      setStatus("已粘贴（未格式化）", "error");
    }
  }

  function hideMenu() {
    els.menu.hidden = true;
  }

  function showMenu(x, y, nodeId) {
    state.contextNodeId = nodeId;
    els.menu.hidden = false;
    const rect = els.menu.getBoundingClientRect();
    const maxX = window.innerWidth - rect.width - 4;
    const maxY = window.innerHeight - rect.height - 4;
    els.menu.style.left = `${Math.max(0, Math.min(x, maxX))}px`;
    els.menu.style.top = `${Math.max(0, Math.min(y, maxY))}px`;
  }

  function nodeById(id) {
    return state.root ? core.findNodeById(state.root, id) : null;
  }

  // —— events ——
  els.editor.addEventListener("input", () => {
    const doc = activeDoc();
    if (doc) Doc.setText(doc, els.editor.value, { markDirty: true });
    updateDirtyMark();
    scheduleParse(false);
    if (els.editorSearch.value) applyEditorSearch(els.editorSearch.value, { silent: true });
  });

  els.editor.addEventListener("keydown", (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "f") {
      event.preventDefault();
      els.editorSearch.focus();
      els.editorSearch.select();
      return;
    }
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
      event.preventDefault();
      saveDocument();
    }
  });

  els.editorSearch.addEventListener("input", () => {
    clearTimeout(state.editorSearchTimer);
    state.editorSearchTimer = setTimeout(() => applyEditorSearch(els.editorSearch.value), 120);
  });

  els.editorSearch.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      if (!state.editorMatches.length) applyEditorSearch(els.editorSearch.value);
      else gotoEditorMatch(event.shiftKey ? -1 : 1);
    } else if (event.key === "Escape") {
      event.preventDefault();
      els.editor.focus();
    }
  });

  document.getElementById("editor-search-prev").addEventListener("click", () => gotoEditorMatch(-1));
  document.getElementById("editor-search-next").addEventListener("click", () => gotoEditorMatch(1));

  document.getElementById("btn-format").addEventListener("click", formatEditor);
  document.getElementById("btn-minify").addEventListener("click", minifyEditor);
  document.getElementById("btn-repair").addEventListener("click", repairEditor);
  document.getElementById("btn-to-python").addEventListener("click", toPythonEditor);
  document.getElementById("btn-to-json").addEventListener("click", toJSONEditor);
  document.getElementById("btn-clear").addEventListener("click", () => {
    setEditorText("", { clearFile: true, immediate: true });
    setStatus("已清空");
  });
  document.getElementById("btn-paste").addEventListener("click", pasteAndFormat);
  document.getElementById("btn-copy").addEventListener("click", () => {
    copyText(els.editor.value);
    setStatus("已复制全文", "ok");
  });

  function summarizeDiffValue(value) {
    if (value === undefined) return "—";
    try {
      const text = JSON.stringify(value);
      if (text == null) return String(value);
      return text.length > 80 ? text.slice(0, 77) + "..." : text;
    } catch (err) {
      return String(value);
    }
  }

  function parseDiffSelectIndex(selectEl) {
    if (!selectEl) return -1;
    const raw = selectEl.value;
    if (raw === "" || raw == null) return -1;
    const index = Number(raw);
    return Number.isInteger(index) ? index : -1;
  }

  function fillDiffTabSelects(preferredLeft, preferredRight) {
    if (!els.diffLeftSelect || !els.diffRightSelect) return;
    const leftKeep = preferredLeft != null ? preferredLeft : parseDiffSelectIndex(els.diffLeftSelect);
    const rightKeep =
      preferredRight != null ? preferredRight : parseDiffSelectIndex(els.diffRightSelect);
    const makeOptions = (selectEl, selectedIndex) => {
      selectEl.innerHTML = "";
      const empty = document.createElement("option");
      empty.value = "";
      empty.textContent = "（未选择）";
      selectEl.appendChild(empty);
      ws.tabs.forEach((doc, index) => {
        const opt = document.createElement("option");
        opt.value = String(index);
        opt.textContent = tabDisplayName(doc, index);
        selectEl.appendChild(opt);
      });
      if (selectedIndex >= 0 && selectedIndex < ws.tabs.length) {
        selectEl.value = String(selectedIndex);
      } else {
        selectEl.value = "";
      }
    };
    makeOptions(els.diffLeftSelect, leftKeep);
    makeOptions(els.diffRightSelect, rightKeep);
  }

  function loadDiffSideFromTab(side) {
    const selectEl = side === "left" ? els.diffLeftSelect : els.diffRightSelect;
    const textEl = side === "left" ? els.diffLeftText : els.diffRightText;
    if (!selectEl || !textEl) return;
    const index = parseDiffSelectIndex(selectEl);
    if (index < 0 || index >= ws.tabs.length) {
      textEl.value = "";
      return;
    }
    if (index === ws.activeIndex) flushEditorToActiveDoc();
    const doc = ws.tabs[index];
    textEl.value = doc && doc.rawText != null ? String(doc.rawText) : "";
  }

  function renderDiffRows() {
    if (!els.diffRows) return;
    els.diffRows.innerHTML = "";
    const rows = state.diffCompare && state.diffCompare.rows ? state.diffCompare.rows : [];
    if (!rows.length) {
      const empty = document.createElement("div");
      empty.className = "diff-rows-empty";
      empty.textContent = state.diffCompare ? "无差异" : "选择两侧来源后对比";
      els.diffRows.appendChild(empty);
      return;
    }
    rows.forEach((row) => {
      const item = document.createElement("div");
      item.className = "diff-row";
      item.setAttribute("role", "option");
      item.dataset.path = row.path || "";
      item.dataset.kind = row.kind || "";
      if (state.diffSelectedPath != null && state.diffSelectedPath === row.path) {
        item.classList.add("is-selected");
      }
      const pathEl = document.createElement("span");
      pathEl.className = "diff-col-path";
      pathEl.textContent = row.path || "(root)";
      const kindEl = document.createElement("span");
      kindEl.className = "diff-col-kind";
      kindEl.textContent = row.kind || "";
      const leftEl = document.createElement("span");
      leftEl.className = "diff-col-left";
      leftEl.textContent = summarizeDiffValue(row.leftValue);
      leftEl.title = summarizeDiffValue(row.leftValue);
      const rightEl = document.createElement("span");
      rightEl.className = "diff-col-right";
      rightEl.textContent = summarizeDiffValue(row.rightValue);
      rightEl.title = summarizeDiffValue(row.rightValue);
      item.appendChild(pathEl);
      item.appendChild(kindEl);
      item.appendChild(leftEl);
      item.appendChild(rightEl);
      item.addEventListener("click", () => {
        state.diffSelectedPath = row.path;
        renderDiffRows();
      });
      els.diffRows.appendChild(item);
    });
  }

  function runDiffCompare(opts) {
    const options = opts || {};
    if (!Diff || typeof Diff.compare !== "function") {
      setStatus("Diff 模块未加载", "error");
      return false;
    }
    const leftText = els.diffLeftText ? els.diffLeftText.value : "";
    const rightText = els.diffRightText ? els.diffRightText.value : "";
    const leftIndex = parseDiffSelectIndex(els.diffLeftSelect);
    const rightIndex = parseDiffSelectIndex(els.diffRightSelect);
    if (leftIndex < 0 || rightIndex < 0) {
      state.diffCompare = null;
      state.diffSelectedPath = null;
      renderDiffRows();
      if (!options.silent) setStatus("请选择两个标签进行对比", "error");
      return false;
    }
    if (leftIndex === rightIndex && ws.tabs.length < 2) {
      state.diffCompare = null;
      state.diffSelectedPath = null;
      renderDiffRows();
      if (!options.silent) setStatus("请再打开一个标签后再对比", "error");
      return false;
    }
    const indentKey =
      (ws.tabs[leftIndex] && ws.tabs[leftIndex].indentKey) || els.indent.value || "fourSpaces";
    try {
      const result = Diff.compare(leftText, rightText, indentKey);
      state.diffCompare = result;
      if (
        state.diffSelectedPath != null &&
        !result.rows.some((row) => row.path === state.diffSelectedPath)
      ) {
        state.diffSelectedPath = null;
      }
      if (els.diffLeftText) els.diffLeftText.value = result.leftPretty;
      if (els.diffRightText) els.diffRightText.value = result.rightPretty;
      renderDiffRows();
      if (!options.silent) {
        setStatus(
          result.rows.length ? `发现 ${result.rows.length} 处差异` : "两侧相同",
          result.rows.length ? "ok" : "ok"
        );
      }
      return true;
    } catch (err) {
      state.diffCompare = null;
      state.diffSelectedPath = null;
      renderDiffRows();
      const side = err && err.side ? (err.side === "left" ? "左" : "右") : "";
      const message = err && err.message ? err.message : String(err);
      setStatus(side ? `${side}侧 JSON 无效: ${message}` : `对比失败: ${message}`, "error");
      return false;
    }
  }

  function scheduleDiffCompare() {
    clearTimeout(state.diffCompareTimer);
    state.diffCompareTimer = setTimeout(() => runDiffCompare({ silent: true }), 200);
  }

  function writeDiffValueToTab(tabIndex, value) {
    if (tabIndex < 0 || tabIndex >= ws.tabs.length) return "";
    const doc = ws.tabs[tabIndex];
    const indentKey = (doc && doc.indentKey) || els.indent.value || "fourSpaces";
    const text = core.format(JSON.stringify(value), indentKey);
    Doc.setText(doc, text, { markDirty: true });
    if (tabIndex === ws.activeIndex) {
      els.editor.value = text;
      updateDirtyMark();
      scheduleParse(true);
    } else {
      updateDirtyMark();
    }
    schedulePersistSession();
    return text;
  }

  function applyDiffDirection(direction, all) {
    if (!state.diffCompare) {
      setStatus("请先完成对比", "error");
      return;
    }
    const leftIndex = parseDiffSelectIndex(els.diffLeftSelect);
    const rightIndex = parseDiffSelectIndex(els.diffRightSelect);
    if (leftIndex < 0 || rightIndex < 0) {
      setStatus("请选择左右标签", "error");
      return;
    }
    let result;
    if (all) {
      result = Diff.applyAll(
        state.diffCompare.rows,
        direction,
        state.diffCompare.leftRoot,
        state.diffCompare.rightRoot
      );
    } else {
      const row = state.diffCompare.rows.find((r) => r.path === state.diffSelectedPath);
      if (!row) {
        setStatus("请先选中一条差异", "error");
        return;
      }
      result = Diff.apply(row, direction, state.diffCompare.leftRoot, state.diffCompare.rightRoot);
    }
    if (direction === "toLeft") {
      const text = writeDiffValueToTab(leftIndex, result.left);
      if (els.diffLeftText) els.diffLeftText.value = text;
    } else {
      const text = writeDiffValueToTab(rightIndex, result.right);
      if (els.diffRightText) els.diffRightText.value = text;
    }
    runDiffCompare({ silent: true });
    setStatus(all ? (direction === "toLeft" ? "已全部应用到左" : "已全部应用到右") : (direction === "toLeft" ? "已应用到左" : "已应用到右"), "ok");
  }

  function openDiffPanel() {
    if (!els.diffPanel) return;
    flushEditorToActiveDoc();
    const leftIndex = ws.activeIndex;
    let rightIndex = -1;
    if (ws.tabs.length >= 2) {
      rightIndex = leftIndex === 0 ? 1 : 0;
    }
    fillDiffTabSelects(leftIndex, rightIndex);
    loadDiffSideFromTab("left");
    loadDiffSideFromTab("right");
    state.diffSelectedPath = null;
    els.diffPanel.hidden = false;
    if (rightIndex < 0) {
      state.diffCompare = null;
      renderDiffRows();
      setStatus("请再打开一个标签后再对比", "error");
      return;
    }
    runDiffCompare();
  }

  function closeDiffPanel() {
    if (!els.diffPanel) return;
    els.diffPanel.hidden = true;
    clearTimeout(state.diffCompareTimer);
    state.diffCompareTimer = null;
  }

  document.getElementById("btn-diff").addEventListener("click", openDiffPanel);
  document.getElementById("diff-close").addEventListener("click", closeDiffPanel);
  document.getElementById("diff-left-current").addEventListener("click", () => {
    if (!els.diffLeftSelect) return;
    els.diffLeftSelect.value = String(ws.activeIndex);
    loadDiffSideFromTab("left");
    runDiffCompare();
  });
  document.getElementById("diff-right-current").addEventListener("click", () => {
    if (!els.diffRightSelect) return;
    els.diffRightSelect.value = String(ws.activeIndex);
    loadDiffSideFromTab("right");
    runDiffCompare();
  });
  if (els.diffLeftSelect) {
    els.diffLeftSelect.addEventListener("change", () => {
      loadDiffSideFromTab("left");
      runDiffCompare();
    });
  }
  if (els.diffRightSelect) {
    els.diffRightSelect.addEventListener("change", () => {
      loadDiffSideFromTab("right");
      runDiffCompare();
    });
  }
  if (els.diffLeftText) {
    els.diffLeftText.addEventListener("input", scheduleDiffCompare);
  }
  if (els.diffRightText) {
    els.diffRightText.addEventListener("input", scheduleDiffCompare);
  }
  document.getElementById("diff-apply-left").addEventListener("click", () => {
    applyDiffDirection("toLeft", false);
  });
  document.getElementById("diff-apply-right").addEventListener("click", () => {
    applyDiffDirection("toRight", false);
  });
  document.getElementById("diff-apply-all-left").addEventListener("click", () => {
    applyDiffDirection("toLeft", true);
  });
  document.getElementById("diff-apply-all-right").addEventListener("click", () => {
    applyDiffDirection("toRight", true);
  });
  if (els.diffPanel) {
    els.diffPanel.addEventListener("click", (event) => {
      if (event.target === els.diffPanel) closeDiffPanel();
    });
  }

  document.getElementById("btn-new-tab").addEventListener("click", createNewTab);

  if (els.tabMenu) {
    els.tabMenu.addEventListener("click", (event) => {
      const item = event.target.closest("li[data-action]");
      if (!item) return;
      const index = state.tabMenuIndex;
      const action = item.dataset.action;
      hideTabMenu();
      if (index < 0) return;
      if (action === "duplicate") duplicateTabAt(index);
      else if (action === "close") closeTabAt(index);
      else if (action === "close-others") closeOtherTabs(index);
    });
  }

  function isJsonFileName(name) {
    if (!name) return false;
    const lower = String(name).toLowerCase();
    return lower.endsWith(".json");
  }

  function openFileIntoWorkspace(filePath, fileName) {
    const content = services.readTextFile(filePath);
    let rawText = content;
    try {
      rawText = core.format(content, els.indent.value);
    } catch (err) {
      rawText = content;
    }
    const result = WS.openPath(ws, {
      filePath,
      fileName: fileName || filePath.split(/[/\\]/).pop(),
      rawText,
      indentKey: els.indent.value,
    });
    if (!result.ok) return result;
    rememberRecent(filePath);
    return result;
  }

  function openManyPaths(paths) {
    if (!paths || !paths.length) return;
    flushEditorToActiveDoc();
    let opened = 0;
    let truncated = false;
    let lastName = "";
    for (let i = 0; i < paths.length; i += 1) {
      const filePath = paths[i];
      if (!filePath) continue;
      const fileName = filePath.split(/[/\\]/).pop();
      try {
        const result = openFileIntoWorkspace(filePath, fileName);
        if (!result.ok) {
          if (result.error === "max tabs") {
            truncated = true;
            break;
          }
          setStatus("打开失败", "error");
          continue;
        }
        opened += 1;
        lastName = fileName;
      } catch (err) {
        setStatus(`打开失败: ${err.message || err}`, "error");
      }
    }
    bindActiveDocToEditor();
    schedulePersistSession();
    if (truncated) {
      setStatus(
        opened
          ? `已打开 ${opened} 个文件，其余因标签上限（20）未打开`
          : "标签已达上限（20）",
        "error"
      );
    } else if (opened === 1) {
      setStatus(`已打开 ${lastName}`, "ok");
    } else if (opened > 1) {
      setStatus(`已打开 ${opened} 个文件`, "ok");
    }
  }

  function openJsonViaDialog() {
    if (!window.utools || typeof utools.showOpenDialog !== "function" || !services) {
      setStatus("当前环境不支持打开文件", "error");
      return;
    }
    try {
      const paths = utools.showOpenDialog({
        title: "打开 JSON 文件",
        properties: ["openFile", "multiSelections"],
        filters: [
          { name: "JSON", extensions: ["json"] },
          { name: "All Files", extensions: ["*"] },
        ],
      });
      if (!paths || !paths.length) return;
      openManyPaths(paths);
    } catch (err) {
      setStatus(`打开失败: ${err.message || err}`, "error");
    }
  }

  function saveDocumentAs() {
    const doc = activeDoc();
    if (!window.utools || typeof utools.showSaveDialog !== "function" || !services) {
      setStatus("当前环境不支持另存为", "error");
      return;
    }
    try {
      const saved = utools.showSaveDialog({
        title: "另存为",
        defaultPath: (doc && doc.fileName) || "untitled.json",
        filters: [
          { name: "JSON", extensions: ["json"] },
          { name: "All Files", extensions: ["*"] },
        ],
      });
      if (!saved) return;
      services.writeTextFile(saved, els.editor.value);
      if (doc) {
        Doc.setText(doc, els.editor.value, { markDirty: false });
        Doc.setFile(doc, {
          filePath: saved,
          fileName: saved.split(/[/\\]/).pop(),
        });
        Doc.markSaved(doc);
      }
      rememberRecent(saved);
      syncFileLabel();
      updateDirtyMark();
      setStatus(`已另存为 ${doc ? doc.fileName : ""}`, "ok");
    } catch (err) {
      setStatus(`另存为失败: ${err.message || err}`, "error");
    }
  }

  function saveDocument() {
    const doc = activeDoc();
    if (!doc || !doc.filePath) return saveDocumentAs();
    if (!services || typeof services.writeTextFile !== "function") {
      setStatus("当前环境不支持保存", "error");
      return;
    }
    try {
      services.writeTextFile(doc.filePath, els.editor.value);
      Doc.setText(doc, els.editor.value, { markDirty: false });
      Doc.markSaved(doc);
      rememberRecent(doc.filePath);
      updateDirtyMark();
      setStatus(`已保存 ${doc.fileName}`, "ok");
    } catch (err) {
      setStatus(`保存失败: ${err.message || err}`, "error");
    }
  }

  function exportJsonViaDialog() {
    const doc = activeDoc();
    if (!window.utools || typeof utools.showSaveDialog !== "function" || !services) {
      copyText(els.editor.value);
      setStatus("已复制（无保存对话框时回退为复制）", "ok");
      return;
    }
    try {
      const saved = utools.showSaveDialog({
        title: "导出 JSON",
        defaultPath: (doc && doc.fileName) || "untitled.json",
        filters: [
          { name: "JSON", extensions: ["json"] },
          { name: "All Files", extensions: ["*"] },
        ],
      });
      if (!saved) return;
      services.writeTextFile(saved, els.editor.value);
      if (doc) {
        Doc.setFile(doc, {
          filePath: saved,
          fileName: saved.split(/[/\\]/).pop(),
        });
        Doc.markSaved(doc);
      }
      syncFileLabel();
      updateDirtyMark();
      setStatus(`已导出 ${doc ? doc.fileName : ""}`, "ok");
    } catch (err) {
      setStatus(`导出失败: ${err.message || err}`, "error");
    }
  }

  document.getElementById("btn-open").addEventListener("click", openJsonViaDialog);
  if (els.btnRecent) {
    els.btnRecent.addEventListener("click", (event) => {
      event.stopPropagation();
      if (els.recentMenu && !els.recentMenu.hidden) hideRecentMenu();
      else showRecentMenu();
    });
  }
  if (els.recentMenu) {
    els.recentMenu.addEventListener("click", (event) => {
      const item = event.target.closest("li[data-path]");
      if (!item) return;
      const filePath = item.dataset.path;
      hideRecentMenu();
      openRecentPath(filePath);
    });
  }
  document.getElementById("btn-save").addEventListener("click", saveDocument);
  document.getElementById("btn-save-as").addEventListener("click", saveDocumentAs);
  document.getElementById("btn-export").addEventListener("click", exportJsonViaDialog);

  els.indent.addEventListener("change", () => {
    const doc = activeDoc();
    if (doc) Doc.setIndent(doc, els.indent.value);
    if (!els.editor.value.trim()) return;
    formatEditor();
  });

  els.treeSearch.addEventListener("input", () => {
    clearTimeout(state.searchTimer);
    state.searchTimer = setTimeout(() => applySearch(els.treeSearch.value), 200);
  });

  els.treeSearch.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      clearTimeout(state.searchTimer);
      applySearch(els.treeSearch.value);
      if (state.matches.length) gotoMatch(event.shiftKey ? -1 : 1);
    }
  });

  document.getElementById("search-prev").addEventListener("click", () => gotoMatch(-1));
  document.getElementById("search-next").addEventListener("click", () => gotoMatch(1));

  els.tree.addEventListener("click", (event) => {
    const row = event.target.closest(".tree-node");
    if (!row) return;
    const id = row.dataset.id;
    state.selectedId = id;
    if (event.target.classList.contains("tree-twistie")) {
      const node = nodeById(id);
      if (node && node.children.length) toggleExpand(id);
      else renderTree();
      return;
    }
    renderTree();
  });

  els.tree.addEventListener("dblclick", (event) => {
    const row = event.target.closest(".tree-node");
    if (!row) return;
    const node = nodeById(row.dataset.id);
    if (node && node.children.length) toggleExpand(node.id);
  });

  els.tree.addEventListener("contextmenu", (event) => {
    const row = event.target.closest(".tree-node");
    if (!row) return;
    event.preventDefault();
    state.selectedId = row.dataset.id;
    renderTree();
    showMenu(event.clientX, event.clientY, row.dataset.id);
  });

  els.tree.addEventListener("keydown", (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "f") {
      event.preventDefault();
      els.treeSearch.focus();
      els.treeSearch.select();
    }
  });

  els.menu.addEventListener("click", (event) => {
    const item = event.target.closest("li[data-action]");
    if (!item) return;
    const node = nodeById(state.contextNodeId);
    hideMenu();
    if (!node) return;
    const action = item.dataset.action;
    if (action === "copy-key") {
      copyText(node.key);
      setStatus("已复制 Key", "ok");
    } else if (action === "copy-value") {
      copyText(core.copyValueText(node));
      setStatus("已复制 Value", "ok");
    } else if (action === "copy-path") {
      copyText(node.jsonPath);
      setStatus("已复制 JSON Path", "ok");
    } else if (action === "expand-all") {
      if (!state.root) return;
      treeEdit.descendantIds(state.root, node.id).forEach((id) => state.expanded.add(id));
      renderTree();
      setStatus("已全部展开", "ok");
    } else if (action === "collapse-all") {
      if (!state.root) return;
      const ids = treeEdit.descendantIds(state.root, node.id);
      ids.forEach((id) => {
        if (id === "0") return;
        state.expanded.delete(id);
      });
      if (!state.expanded.has("0")) state.expanded.add("0");
      renderTree();
      setStatus("已全部收起", "ok");
    } else if (action === "delete-node") {
      if (!state.root) return;
      if (node.id === "0" || node.id === state.root.id) {
        setStatus("无法删除根节点", "error");
        return;
      }
      if (!window.confirm("删除该节点及其子节点？")) return;
      const result = treeEdit.deleteNodeById(state.root, node.id);
      if (!result.ok) {
        setStatus(
          result.error === "cannotDeleteRoot" ? "无法删除根节点" : result.error || "删除失败",
          "error"
        );
        return;
      }
      try {
        const text = core.format(JSON.stringify(result.value), els.indent.value);
        setEditorText(text, { immediate: true });
        markProgrammaticDirty();
        if (state.selectedId === node.id) state.selectedId = null;
        setStatus("已删除节点", "ok");
      } catch (err) {
        setStatus(err.message || String(err), "error");
      }
    }
  });

  document.addEventListener("click", (event) => {
    if (!els.menu.hidden && !els.menu.contains(event.target)) hideMenu();
    if (els.tabMenu && !els.tabMenu.hidden && !els.tabMenu.contains(event.target)) hideTabMenu();
    if (
      els.recentMenu &&
      !els.recentMenu.hidden &&
      !els.recentMenu.contains(event.target) &&
      event.target !== els.btnRecent
    ) {
      hideRecentMenu();
    }
  });

  // splitter
  (() => {
    let dragging = false;
    els.splitter.addEventListener("mousedown", (event) => {
      dragging = true;
      event.preventDefault();
    });
    window.addEventListener("mousemove", (event) => {
      if (!dragging) return;
      const bounds = document.querySelector(".panes").getBoundingClientRect();
      const width = Math.min(Math.max(event.clientX - bounds.left, 180), bounds.width - 200);
      els.editorPane.style.width = `${width}px`;
    });
    window.addEventListener("mouseup", () => {
      dragging = false;
    });
  })();

  function handlePluginEnter(action) {
    const code = action && action.code;
    const type = action && action.type;
    const payload = action && action.payload;

    if (code === "dotjson-file" && type === "files" && Array.isArray(payload) && payload.length) {
      if (!services || typeof services.readTextFile !== "function") {
        setStatus("当前环境不支持打开文件", "error");
        return;
      }
      flushEditorToActiveDoc();
      let opened = 0;
      let truncated = false;
      let lastName = "";
      for (let i = 0; i < payload.length; i += 1) {
        const file = payload[i];
        if (!file || file.isFile !== true) continue;
        const name = file.name || (file.path && String(file.path).split(/[/\\]/).pop()) || "";
        if (!isJsonFileName(name)) continue;
        try {
          const result = openFileIntoWorkspace(file.path, name);
          if (!result.ok) {
            if (result.error === "max tabs") {
              truncated = true;
              break;
            }
            continue;
          }
          opened += 1;
          lastName = name;
        } catch (err) {
          setStatus(err.message || String(err), "error");
        }
      }
      bindActiveDocToEditor();
      schedulePersistSession();
      if (truncated) {
        setStatus(
          opened
            ? `已打开 ${opened} 个文件，其余因标签上限（20）未打开`
            : "标签已达上限（20）",
          "error"
        );
      } else if (opened === 1) {
        setStatus(`已打开 ${lastName}`, "ok");
      } else if (opened > 1) {
        setStatus(`已打开 ${opened} 个文件`, "ok");
      }
      return;
    }

    if (
      (code === "dotjson-text" || type === "over" || type === "regex" || type === "text") &&
      typeof payload === "string" &&
      payload.trim()
    ) {
      flushEditorToActiveDoc();
      const created = WS.newTab(ws);
      if (!created.ok) {
        setStatus("标签已达上限（20）", "error");
        return;
      }
      try {
        let text = payload;
        try {
          text = core.format(payload, els.indent.value);
        } catch (err) {
          try {
            text = core.format(core.repair(payload), els.indent.value);
          } catch (err2) {
            text = payload;
          }
        }
        setEditorText(text, { clearFile: true, immediate: true });
        schedulePersistSession();
        setStatus("已载入选中文本", "ok");
      } catch (err) {
        setEditorText(payload, { clearFile: true, immediate: true });
        schedulePersistSession();
      }
    }
  }

  if (window.utools) {
    if (typeof utools.onPluginReady === "function") {
      utools.onPluginReady(restoreSession);
    }
    if (typeof utools.onPluginEnter === "function") {
      utools.onPluginEnter(handlePluginEnter);
    }
    if (typeof utools.onPluginOut === "function") {
      utools.onPluginOut(() => {
        if (sessionWriteTimer) {
          clearTimeout(sessionWriteTimer);
          sessionWriteTimer = null;
        }
        persistSession();
      });
    }
  }

  // 开发态：无内容时给一个示例，方便浏览器直接打开自检
  if (!window.utools && !els.editor.value) {
    setEditorText('{"hello":"DotJSON","items":[1,true,null]}', { immediate: true });
  } else {
    bindActiveDocToEditor();
  }
  renderTabs();
})();
