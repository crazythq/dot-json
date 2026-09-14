(() => {
  "use strict";

  const core = window.DotJSONCore;
  const api = window.dotjson;

  const els = {
    editor: document.getElementById("editor"),
    tree: document.getElementById("tree"),
    status: document.getElementById("status"),
    fileLabel: document.getElementById("file-label"),
    indent: document.getElementById("indent-select"),
    treeSearch: document.getElementById("tree-search"),
    searchCount: document.getElementById("search-count"),
    menu: document.getElementById("context-menu"),
    splitter: document.getElementById("splitter"),
    editorPane: document.querySelector(".pane-editor"),
  };

  const state = {
    filePath: null,
    fileName: "",
    root: null,
    expanded: new Set(["0"]),
    selectedId: null,
    contextNodeId: null,
    matches: [],
    matchIndex: -1,
    searchTimer: null,
    parseTimer: null,
  };

  function setStatus(message, kind) {
    els.status.textContent = message;
    els.status.classList.remove("is-error", "is-ok");
    if (kind === "error") els.status.classList.add("is-error");
    if (kind === "ok") els.status.classList.add("is-ok");
  }

  function copyText(text) {
    if (window.utools && typeof utools.copyText === "function") {
      utools.copyText(String(text ?? ""));
      return;
    }
    if (api && typeof api.writeClipboard === "function") {
      api.writeClipboard(text);
      return;
    }
    navigator.clipboard.writeText(String(text ?? ""));
  }

  function readClipboard() {
    if (api && typeof api.readClipboard === "function") {
      return api.readClipboard();
    }
    return "";
  }

  function setEditorText(text, opts) {
    const options = opts || {};
    els.editor.value = text == null ? "" : String(text);
    if (options.filePath) {
      state.filePath = options.filePath;
      state.fileName = options.fileName || options.filePath.split(/[/\\]/).pop();
      els.fileLabel.textContent = state.fileName;
    } else if (options.clearFile) {
      state.filePath = null;
      state.fileName = "";
      els.fileLabel.textContent = "";
    }
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
      els.tree.innerHTML = `<div class="tree-error">解析失败\n${escapeHtml(built.error)}</div>`;
      setStatus(built.error, "error");
      updateSearchCount();
      return;
    }

    state.root = built.root;
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
      setStatus("已修复并格式化", "ok");
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
      setStatus("已粘贴并格式化", "ok");
    } catch (err) {
      setEditorText(clip, { immediate: true });
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
  els.editor.addEventListener("input", () => scheduleParse(false));

  els.editor.addEventListener("keydown", (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "f") {
      // 左侧保持浏览器原生查找
      return;
    }
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
      event.preventDefault();
      document.getElementById("btn-export").click();
    }
  });

  document.getElementById("btn-format").addEventListener("click", formatEditor);
  document.getElementById("btn-minify").addEventListener("click", minifyEditor);
  document.getElementById("btn-repair").addEventListener("click", repairEditor);
  document.getElementById("btn-clear").addEventListener("click", () => {
    setEditorText("", { clearFile: true, immediate: true });
    setStatus("已清空");
  });
  document.getElementById("btn-paste").addEventListener("click", pasteAndFormat);
  document.getElementById("btn-copy").addEventListener("click", () => {
    copyText(els.editor.value);
    setStatus("已复制全文", "ok");
  });

  function openJsonViaDialog() {
    if (!window.utools || typeof utools.showOpenDialog !== "function" || !api) {
      setStatus("当前环境不支持打开文件", "error");
      return;
    }
    try {
      const paths = utools.showOpenDialog({
        title: "打开 JSON 文件",
        properties: ["openFile"],
        filters: [
          { name: "JSON", extensions: ["json"] },
          { name: "All Files", extensions: ["*"] },
        ],
      });
      if (!paths || !paths.length) return;
      const filePath = paths[0];
      const content = api.readTextFile(filePath);
      const fileName = filePath.split(/[/\\]/).pop();
      setEditorText(content, {
        filePath,
        fileName,
        immediate: true,
      });
      try {
        setEditorText(core.format(content, els.indent.value), {
          filePath,
          fileName,
          immediate: true,
        });
      } catch (err) {
        // 保持原内容
      }
      setStatus(`已打开 ${fileName}`, "ok");
    } catch (err) {
      setStatus(`打开失败: ${err.message || err}`, "error");
    }
  }

  function exportJsonViaDialog() {
    if (!window.utools || typeof utools.showSaveDialog !== "function" || !api) {
      copyText(els.editor.value);
      setStatus("已复制（无保存对话框时回退为复制）", "ok");
      return;
    }
    try {
      const saved = utools.showSaveDialog({
        title: "导出 JSON",
        defaultPath: state.fileName || "untitled.json",
        filters: [
          { name: "JSON", extensions: ["json"] },
          { name: "All Files", extensions: ["*"] },
        ],
      });
      if (!saved) return;
      api.writeTextFile(saved, els.editor.value);
      state.filePath = saved;
      state.fileName = saved.split(/[/\\]/).pop();
      els.fileLabel.textContent = state.fileName;
      setStatus(`已导出 ${state.fileName}`, "ok");
    } catch (err) {
      setStatus(`导出失败: ${err.message || err}`, "error");
    }
  }

  document.getElementById("btn-open").addEventListener("click", openJsonViaDialog);
  document.getElementById("btn-export").addEventListener("click", exportJsonViaDialog);

  els.indent.addEventListener("change", () => {
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
    }
  });

  document.addEventListener("click", (event) => {
    if (!els.menu.hidden && !els.menu.contains(event.target)) hideMenu();
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

    if (code === "dotjson-file" && type === "files" && Array.isArray(payload) && payload[0]) {
      const file = payload[0];
      try {
        const content = api.readTextFile(file.path);
        setEditorText(content, {
          filePath: file.path,
          fileName: file.name,
          immediate: true,
        });
        try {
          setEditorText(core.format(content, els.indent.value), {
            filePath: file.path,
            fileName: file.name,
            immediate: true,
          });
        } catch (err) {
          // keep raw
        }
        setStatus(`已打开 ${file.name}`, "ok");
      } catch (err) {
        setStatus(err.message || String(err), "error");
      }
      return;
    }

    if (
      (code === "dotjson-text" || type === "over" || type === "regex" || type === "text") &&
      typeof payload === "string" &&
      payload.trim()
    ) {
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
        setStatus("已载入选中文本", "ok");
      } catch (err) {
        setEditorText(payload, { clearFile: true, immediate: true });
      }
    }
  }

  if (window.utools && typeof utools.onPluginEnter === "function") {
    utools.onPluginEnter(handlePluginEnter);
  }

  // 开发态：无内容时给一个示例，方便浏览器直接打开自检
  if (!window.utools && !els.editor.value) {
    setEditorText('{"hello":"DotJSON","items":[1,true,null]}', { immediate: true });
  } else {
    refreshTree();
  }
})();
