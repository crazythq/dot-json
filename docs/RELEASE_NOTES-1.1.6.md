# DotJSON 1.1.6

## macOS app

- **Tree context menu** — Expand All / Collapse All for the selected node and its children; Delete Node with confirmation (root cannot be deleted). Delete failures show an alert instead of failing silently.
- **Update check** — optional automatic check against GitHub Releases on launch; Settings includes Auto Check for Updates. Failure alerts clarify rate-limit / network cases and can open the Releases page.
- **Settings window** — resizable; size is remembered across sessions.
- **Tab switching** — single-click activates immediately (no ~500ms wait for double-click rename detection). Double-click rename still works via a short local double-tap window. Empty / same-content tab switches skip redundant editor relayout; session persistence no longer blocks the click on the main thread.

## Notes

This build is **ad-hoc signed** and **not notarized**. If Gatekeeper blocks the app on first launch, **right-click** the app in Finder and choose **Open**.

Official uTools `.upxs` packages cannot be built in CI; attach them manually to the Release if needed.

---

# DotJSON 1.1.6

## macOS 应用

- **树右键菜单** — 展开所有 / 收起所有（作用于当前节点及其子节点）；删除节点需确认（根节点不可删）。删除失败会弹出提示。
- **检查更新** — 可选启动时自动对照 GitHub Releases；设置中可开关「自动检查更新」。失败提示会区分限流/网络等情况，并可打开 Releases 页面。
- **设置窗口** — 可调整大小，并记住上次尺寸。
- **标签切换** — 单击立即切换（不再为「是否双击改名」等待约 500ms）；短间隔连点仍可改名。空白/相同内容标签切换减少多余重排；会话保存不再堵在点击当下。

## 说明

本 release 为 **ad-hoc 签名**，未经 Apple 公证。若 Gatekeeper 拦截首次打开，请在 Finder 中对该 app **右键 → 打开**。

官方 uTools `.upxs` 插件包无法在 CI 中构建；如有需要，请维护者在 Release 中**手动上传**附件。
