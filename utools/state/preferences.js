/**
 * 插件偏好（无 DOM）。默认缩进仅影响新建文档。
 */
(function (global) {
  "use strict";

  const STORAGE_KEY_DEFAULT_INDENT = "dotjson.defaultIndent";
  const STORAGE_KEY_AUTO_FORMAT = "dotjson.autoFormat";
  const ALLOWED = {
    twoSpaces: true,
    fourSpaces: true,
    tab: true,
  };

  function normalizeIndentKey(raw) {
    return ALLOWED[raw] ? raw : "fourSpaces";
  }

  function normalizeAutoFormat(raw) {
    if (raw === false || raw === 0 || raw === "0" || raw === "false") return false;
    return true;
  }

  function create(partial) {
    const src = partial || {};
    return {
      defaultIndent: normalizeIndentKey(src.defaultIndent),
      autoFormat: normalizeAutoFormat(
        Object.prototype.hasOwnProperty.call(src, "autoFormat") ? src.autoFormat : true
      ),
    };
  }

  function applyToNewDoc(doc, prefs) {
    if (!doc || !prefs) return;
    const Doc = global.DotJSONDocument;
    if (!Doc || typeof Doc.setIndent !== "function") return;
    Doc.setIndent(doc, prefs.defaultIndent);
  }

  global.DotJSONPreferences = {
    STORAGE_KEY_DEFAULT_INDENT: STORAGE_KEY_DEFAULT_INDENT,
    STORAGE_KEY_AUTO_FORMAT: STORAGE_KEY_AUTO_FORMAT,
    normalizeIndentKey: normalizeIndentKey,
    normalizeAutoFormat: normalizeAutoFormat,
    create: create,
    applyToNewDoc: applyToNewDoc,
  };
})(typeof window !== "undefined" ? window : globalThis);
