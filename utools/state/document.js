/**
 * 单文档状态（无 DOM）。P0 建立接口；P1 接上真实保存/脏状态 UI。
 */
(function (global) {
  "use strict";

  function create() {
    return {
      rawText: "",
      filePath: null,
      fileName: "",
      indentKey: "fourSpaces",
      isDirty: false,
    };
  }

  function setText(doc, text, opts) {
    const options = opts || {};
    doc.rawText = text == null ? "" : String(text);
    if (options.markDirty) doc.isDirty = true;
  }

  function setFile(doc, info) {
    doc.filePath = info && info.filePath ? String(info.filePath) : null;
    doc.fileName = info && info.fileName ? String(info.fileName) : "";
  }

  function clearFile(doc) {
    doc.filePath = null;
    doc.fileName = "";
  }

  function setIndent(doc, indentKey) {
    doc.indentKey = indentKey || "fourSpaces";
  }

  function markSaved(doc) {
    doc.isDirty = false;
  }

  function markDirty(doc) {
    doc.isDirty = true;
  }

  global.DotJSONDocument = {
    create,
    setText,
    setFile,
    clearFile,
    setIndent,
    markSaved,
    markDirty,
  };
})(typeof window !== "undefined" ? window : globalThis);