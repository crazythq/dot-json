(function (global) {
  "use strict";

  function cloneValue(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function deleteNodeById(root, nodeId) {
    if (!root || nodeId === "0" || nodeId === root.id) {
      return { ok: false, error: "cannotDeleteRoot" };
    }
    const node = global.DotJSONCore.findNodeById(root, nodeId);
    if (!node) return { ok: false, error: "missing" };

    const segments = nodeId.split(".").slice(1);
    if (segments.length === 0) return { ok: false, error: "cannotDeleteRoot" };

    const chain = [];
    let parent = root;
    for (let i = 0; i < segments.length; i += 1) {
      const idx = Number(segments[i]);
      if (!Number.isInteger(idx) || idx < 0 || !parent.children || idx >= parent.children.length) {
        return { ok: false, error: "missing" };
      }
      const child = parent.children[idx];
      if (parent.type === "array") {
        chain.push({ type: "index", index: idx });
      } else {
        chain.push({ type: "key", key: child.key });
      }
      parent = child;
    }

    const copy = cloneValue(root.value);
    let cursor = copy;
    for (let p = 0; p < chain.length - 1; p += 1) {
      const part = chain[p];
      cursor = part.type === "key" ? cursor[part.key] : cursor[part.index];
      if (cursor === undefined) return { ok: false, error: "missing" };
    }
    const last = chain[chain.length - 1];
    if (last.type === "key") {
      if (!Object.prototype.hasOwnProperty.call(cursor, last.key)) {
        return { ok: false, error: "missing" };
      }
      delete cursor[last.key];
    } else {
      if (!Array.isArray(cursor) || last.index < 0 || last.index >= cursor.length) {
        return { ok: false, error: "missing" };
      }
      cursor.splice(last.index, 1);
    }
    return { ok: true, value: copy };
  }

  function descendantIds(root, nodeId) {
    const node = global.DotJSONCore.findNodeById(root, nodeId);
    if (!node) return [];
    const out = [];
    function walk(n) {
      out.push(n.id);
      (n.children || []).forEach(walk);
    }
    walk(node);
    return out;
  }

  global.DotJSONTreeEdit = { deleteNodeById, descendantIds };
})(typeof window !== "undefined" ? window : globalThis);
