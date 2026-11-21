/**
 * 用户选定路径校验（preload 与契约测试共用）。
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory(require("path"));
  } else {
    root.DotJSONSafePath = factory(root.path || null);
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function (pathMod) {
  "use strict";

  function assertSafeUserPath(filePath, pathApi) {
    const path = pathApi || pathMod;
    if (!path || typeof path.isAbsolute !== "function") {
      throw new Error("path module unavailable");
    }
    if (typeof filePath !== "string" || !filePath) {
      throw new Error("invalid path");
    }
    if (filePath.includes("\0")) {
      throw new Error("invalid path");
    }
    if (!path.isAbsolute(filePath)) {
      throw new Error("path must be absolute");
    }
    if (/(^|[\\/])\.\.([\\/]|$)/.test(filePath)) {
      throw new Error("invalid path");
    }
    return path.normalize(filePath);
  }

  return { assertSafeUserPath };
});
