/**
 * DotJSON 核心 JSON 能力（对照 mac DotJSONCore 的设计契约）。
 * 浏览器侧纯 JS，无第三方依赖。
 */
(function (global) {
  "use strict";

  const INDENTS = {
    twoSpaces: "  ",
    fourSpaces: "    ",
    tab: "\t",
  };

  function tryParse(text) {
    const trimmed = String(text ?? "").replace(/^\uFEFF/, "");
    if (!trimmed.trim()) {
      return { ok: false, error: "Empty input.", value: null };
    }
    try {
      return { ok: true, error: null, value: JSON.parse(trimmed), text: trimmed };
    } catch (err) {
      return {
        ok: false,
        error: err && err.message ? err.message : String(err),
        value: null,
        text: trimmed,
      };
    }
  }

  function encodeLeaf(value) {
    return JSON.stringify(value);
  }

  function prettyPrint(value, indent, level) {
    const prefix = indent.repeat(level);
    const childPrefix = indent.repeat(level + 1);

    if (value !== null && typeof value === "object" && !Array.isArray(value)) {
      const keys = Object.keys(value).sort();
      if (!keys.length) return "{}";
      const items = keys.map((key) => {
        return `${childPrefix}${encodeLeaf(key)}: ${prettyPrint(value[key], indent, level + 1)}`;
      });
      return `{\n${items.join(",\n")}\n${prefix}}`;
    }

    if (Array.isArray(value)) {
      if (!value.length) return "[]";
      const items = value.map((item) => `${childPrefix}${prettyPrint(item, indent, level + 1)}`);
      return `[\n${items.join(",\n")}\n${prefix}]`;
    }

    return encodeLeaf(value);
  }

  function format(text, indentKey) {
    const parsed = tryParse(text);
    if (!parsed.ok) {
      throw new Error(parsed.error);
    }
    const indent = INDENTS[indentKey] || INDENTS.fourSpaces;
    return prettyPrint(parsed.value, indent, 0);
  }

  function minify(text) {
    const parsed = tryParse(text);
    if (!parsed.ok) {
      throw new Error(parsed.error);
    }
    return JSON.stringify(parsed.value);
  }

  function stripMarkdownFence(input) {
    const match = input.match(/```(?:json|python|js|javascript)?\s*\n([\s\S]*?)```/i);
    if (match) return match[1];
    return input;
  }

  function extractBalancedRoot(input) {
    const text = input.trim();
    const startChar = text[0];
    if (startChar !== "{" && startChar !== "[") return null;
    const endChar = startChar === "{" ? "}" : "]";
    let depth = 0;
    let inString = false;
    let quote = null;
    let escaped = false;

    for (let i = 0; i < text.length; i += 1) {
      const ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch === "\\") {
          escaped = true;
        } else if (ch === quote) {
          inString = false;
          quote = null;
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        inString = true;
        quote = ch;
        continue;
      }
      if (ch === startChar) depth += 1;
      if (ch === endChar) {
        depth -= 1;
        if (depth === 0) return text.slice(0, i + 1);
      }
    }
    return null;
  }

  /** 保守修复：Markdown 围栏、True/False/None、尾逗号、单引号键/值（确定性子集）。 */
  function repair(input) {
    const original = String(input ?? "").replace(/^\uFEFF/, "");
    if (tryParse(original).ok) return original;

    let candidate = stripMarkdownFence(original);
    if (!tryParse(candidate).ok) {
      const balanced = extractBalancedRoot(candidate);
      if (balanced) candidate = balanced;
    }

    if (tryParse(candidate).ok) return candidate;

    let out = "";
    let i = 0;
    const src = candidate;

    while (i < src.length) {
      const ch = src[i];

      if (ch === "'") {
        i += 1;
        let decoded = "";
        while (i < src.length) {
          const c = src[i];
          if (c === "'") {
            i += 1;
            break;
          }
          if (c === "\\") {
            i += 1;
            if (i >= src.length) throw new Error("Unterminated escape in single-quoted string.");
            const esc = src[i];
            if (esc === "n") decoded += "\n";
            else if (esc === "t") decoded += "\t";
            else if (esc === "r") decoded += "\r";
            else if (esc === "\\" || esc === "'" || esc === '"') decoded += esc;
            else decoded += esc;
            i += 1;
            continue;
          }
          if (c === "\n" || c === "\r") {
            throw new Error("Single-quoted strings cannot contain raw newlines.");
          }
          decoded += c;
          i += 1;
        }
        out += JSON.stringify(decoded);
        continue;
      }

      if (ch === '"') {
        out += ch;
        i += 1;
        let escaped = false;
        while (i < src.length) {
          const c = src[i];
          out += c;
          i += 1;
          if (escaped) {
            escaped = false;
          } else if (c === "\\") {
            escaped = true;
          } else if (c === '"') {
            break;
          }
        }
        continue;
      }

      if (/[A-Za-z_]/.test(ch)) {
        let start = i;
        i += 1;
        while (i < src.length && /[A-Za-z0-9_]/.test(src[i])) i += 1;
        const ident = src.slice(start, i);
        if (ident === "True" || ident === "true") out += "true";
        else if (ident === "False" || ident === "false") out += "false";
        else if (ident === "None" || ident === "null") out += "null";
        else throw new Error(`Unsupported identifier: ${ident}`);
        continue;
      }

      if (ch === ",") {
        let j = i + 1;
        while (j < src.length && /\s/.test(src[j])) j += 1;
        if (src[j] === "}" || src[j] === "]") {
          i += 1;
          continue;
        }
      }

      out += ch;
      i += 1;
    }

    if (!tryParse(out).ok) {
      throw new Error("Input cannot be repaired without guessing.");
    }
    return out;
  }

  function valueType(value) {
    if (value === null) return "null";
    if (Array.isArray(value)) return "array";
    return typeof value;
  }

  function summarize(value) {
    const t = valueType(value);
    if (t === "string") return JSON.stringify(value);
    if (t === "number" || t === "boolean" || t === "null") return String(value);
    if (t === "array") return `Array(${value.length})`;
    if (t === "object") return `Object(${Object.keys(value).length})`;
    return String(value);
  }

  function buildTree(value, key, jsonPath, idPrefix) {
    const type = valueType(value);
    const id = idPrefix;
    const node = {
      id,
      key: key == null ? "" : String(key),
      type,
      jsonPath,
      summary: summarize(value),
      value,
      children: [],
    };

    if (type === "object") {
      const keys = Object.keys(value);
      keys.forEach((k, index) => {
        const childPath = `${jsonPath}.${k}`;
        node.children.push(buildTree(value[k], k, childPath, `${id}.${index}`));
      });
    } else if (type === "array") {
      value.forEach((item, index) => {
        const childPath = `${jsonPath}[${index}]`;
        node.children.push(buildTree(item, String(index), childPath, `${id}.${index}`));
      });
    }

    return node;
  }

  function buildRootTree(text) {
    const parsed = tryParse(text);
    if (!parsed.ok) return { ok: false, error: parsed.error, root: null };
    const root = buildTree(parsed.value, "root", "$", "0");
    return { ok: true, error: null, root };
  }

  function collectSearchMatches(node, query, out) {
    if (!query) return;
    const q = query.toLowerCase();
    const hay = `${node.key} ${node.summary} ${node.jsonPath}`.toLowerCase();
    if (hay.includes(q)) {
      out.push({ id: node.id, path: node.jsonPath, ancestors: [] });
    }
    node.children.forEach((child) => collectSearchMatches(child, query, out));
  }

  function findNodeById(node, id) {
    if (node.id === id) return node;
    for (const child of node.children) {
      const found = findNodeById(child, id);
      if (found) return found;
    }
    return null;
  }

  function ancestorIds(root, targetId) {
    const path = [];
    function walk(node, trail) {
      if (node.id === targetId) {
        path.push(...trail);
        return true;
      }
      for (const child of node.children) {
        if (walk(child, trail.concat(node.id))) return true;
      }
      return false;
    }
    walk(root, []);
    return path;
  }

  function copyValueText(node) {
    if (!node) return "";
    if (node.type === "string") return String(node.value);
    if (node.type === "object" || node.type === "array") {
      return JSON.stringify(node.value);
    }
    return String(node.value);
  }

  global.DotJSONCore = {
    INDENTS,
    tryParse,
    format,
    minify,
    repair,
    buildRootTree,
    collectSearchMatches,
    findNodeById,
    ancestorIds,
    copyValueText,
  };
})(typeof window !== "undefined" ? window : globalThis);
