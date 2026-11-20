/**
 * DotJSON uTools preload — 最小本地能力桥。
 * 官方：统一命名空间、禁止把 fs 整包暴露给前端。
 */
const fs = require("fs");
const path = require("path");
const { clipboard } = require("electron");

const SESSION_FILE = "session-v1.json";

function sessionPath() {
  if (typeof utools !== "undefined" && typeof utools.getPluginLocalDataPath === "function") {
    return path.join(utools.getPluginLocalDataPath(), SESSION_FILE);
  }
  return null;
}

window.services = {
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

  readSession() {
    const file = sessionPath();
    if (!file || !fs.existsSync(file)) return null;
    return fs.readFileSync(file, "utf8");
  },

  writeSession(content) {
    const file = sessionPath();
    if (!file) return;
    fs.writeFileSync(file, String(content ?? ""), "utf8");
  },
};