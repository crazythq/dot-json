/**
 * JSON ↔ Python literal 转换（对照 mac PythonLiteralSerializer）。
 */
(function (global) {
  "use strict";
  const core = global.DotJSONCore;

  function indentStr(indentKey) {
    return (core.INDENTS && core.INDENTS[indentKey]) || "    ";
  }

  function quote(value) {
    let escaped = "";
    const s = String(value);
    for (let i = 0; i < s.length; i += 1) {
      const code = s.charCodeAt(i);
      const ch = s[i];
      if (ch === "\\") escaped += "\\\\";
      else if (ch === "'") escaped += "\\'";
      else if (ch === "\n") escaped += "\\n";
      else if (ch === "\r") escaped += "\\r";
      else if (ch === "\t") escaped += "\\t";
      else if (code <= 0x1f) escaped += "\\x" + code.toString(16).padStart(2, "0");
      else escaped += ch;
    }
    return "'" + escaped + "'";
  }

  function pythonString(value, indent, level) {
    const prefix = indent.repeat(level);
    const childPrefix = indent.repeat(level + 1);
    if (value !== null && typeof value === "object" && !Array.isArray(value)) {
      const keys = Object.keys(value);
      if (!keys.length) return "{}";
      const items = keys.map(
        (k) => childPrefix + quote(k) + ": " + pythonString(value[k], indent, level + 1)
      );
      return "{\n" + items.join(",\n") + "\n" + prefix + "}";
    }
    if (Array.isArray(value)) {
      if (!value.length) return "[]";
      const items = value.map(
        (item) => childPrefix + pythonString(item, indent, level + 1)
      );
      return "[\n" + items.join(",\n") + "\n" + prefix + "]";
    }
    if (typeof value === "string") return quote(value);
    if (typeof value === "number") return String(value);
    if (typeof value === "boolean") return value ? "True" : "False";
    if (value === null) return "None";
    throw new Error("Unsupported value");
  }

  function toPython(text, indentKey) {
    let parsed = core.tryParse(text);
    if (!parsed.ok) {
      const repaired = core.repair(text);
      parsed = core.tryParse(repaired);
      if (!parsed.ok) throw new Error(parsed.error || "Cannot parse");
    }
    return pythonString(parsed.value, indentStr(indentKey), 0);
  }

  function toJSON(text, indentKey) {
    try {
      return core.format(text, indentKey);
    } catch (_e) {
      return core.format(core.repair(text), indentKey);
    }
  }

  global.DotJSONPython = { toPython, toJSON };
})(typeof window !== "undefined" ? window : globalThis);
