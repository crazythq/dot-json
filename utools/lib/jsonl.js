/**
 * JSONL 预解析（对照 mac JSONLPreparser）。
 * 按物理行切分；跳过纯空白行；非空白行为候选记录。
 */
(function (global) {
  "use strict";

  function utf8ByteLength(text) {
    if (typeof TextEncoder !== "undefined") {
      return new TextEncoder().encode(String(text)).length;
    }
    if (typeof Buffer !== "undefined") {
      return Buffer.byteLength(String(text), "utf8");
    }
    return String(text).length;
  }

  function tryParse(line) {
    try {
      return { ok: true, value: JSON.parse(line) };
    } catch (_err) {
      return { ok: false, value: null };
    }
  }

  function parse(rawContent) {
    const normalized = String(rawContent == null ? "" : rawContent).replace(/\r\n/g, "\n");
    const rawLines = normalized.split("\n");
    const lines = [];
    let offset = 0;

    for (let i = 0; i < rawLines.length; i += 1) {
      const line = rawLines[i];
      if (line.trim() === "") {
        offset += utf8ByteLength(line) + 1;
        continue;
      }
      const parsed = tryParse(line);
      lines.push({
        index: i,
        rawText: line,
        byteOffset: offset,
        isValid: parsed.ok,
      });
      offset += utf8ByteLength(line) + 1;
    }

    function parseLine(at) {
      if (at < 0 || at >= lines.length) return null;
      const info = lines[at];
      if (!info.isValid) return null;
      const again = tryParse(info.rawText);
      return again.ok ? again.value : null;
    }

    return {
      lines: lines,
      count: lines.length,
      parseLine: parseLine,
    };
  }

  global.DotJSONL = {
    parse: parse,
  };
})(typeof window !== "undefined" ? window : globalThis);
