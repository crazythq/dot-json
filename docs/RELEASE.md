# 发布 macOS 版本

## 流程

1. 在 `mac/Info.plist` 中更新 `CFBundleShortVersionString`（以及按需更新 `CFBundleVersion`）。
2. 提交并合并到 `main`。
3. 创建并推送标签：`git tag vX.Y.Z && git push origin vX.Y.Z`（标签需以 `v` 开头，例如 `v1.0.1`）。
4. GitHub Actions [Release](../.github/workflows/release.yml) 会在 `macos-14` 上运行 `swift test`、以 release 配置执行 `mac/build-app.sh -c release`，并上传 `DotJSON-X.Y.Z-macos-adhoc.zip` 到对应 GitHub Release。

## 产物说明

- ZIP 内为 **ad-hoc 签名**的 `DotJSON.app`，**未公证**。用户首次打开若被 Gatekeeper 拦截，需在 Finder 中右键选择「打开」。
- CI **不会**进行 notarization，也无需相关 secrets。

## uTools 插件（可选）

官方 uTools `.upxs` 无法在 Actions 中自动构建。若该版本需要分发插件，请在 GitHub Release 页面**手动添加** `.upxs` 附件。
