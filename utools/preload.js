/**
 * DotJSON uTools preload — Node / Electron 渲染进程能力桥接。
 * 仅使用 preload 可用的 API（fs、clipboard）；文件对话框用 utools.showOpen/SaveDialog。
 */
const fs = require("fs");
const { clipboard } = require("electron");

window.dotjson = {
  readTextFile(filePath) {
    return fs.readFileSync(filePath, "utf8");
  },

  writeTextFile(filePath, content) {
    fs.writeFileSync(filePath, content, "utf8");
  },

  readClipboard() {
    return clipboard.readText() || "";
  },

  writeClipboard(text) {
    clipboard.writeText(String(text ?? ""));
    return true;
  },
};
