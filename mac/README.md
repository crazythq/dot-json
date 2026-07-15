# DotJSON macOS

DotJSON 的原生 macOS 14+ 客户端，使用 SwiftUI、AppKit 和 Swift Package Manager，零第三方依赖。

## MVP 功能

- 双面板文本编辑与 JSON 树浏览
- 格式化、压缩、2/4 空格或 Tab 实时缩进
- 标准粘贴自动格式化、复制和清空
- 打开、保存、另存为，以及格式化/压缩导出
- Finder/Dock 文件打开、窗口拖放和 `.json` 文件关联
- 精确错误行号、红色行号标记和悬停错误说明

多标签、持久历史与搜索增强属于 V1；JSONL 导航和 JSON Diff 属于 V2，不在当前 MVP 范围。

## 开发与测试

```bash
cd mac
swift test
swift build
```

## 构建本地 App

```bash
cd mac
./build-app.sh
open "$(swift build --show-bin-path)/DotJSON.app"
```

脚本会生成并 ad-hoc 签名 `DotJSON.app`。本地验证时，可在应用中打开 `.json` 文件，或把文件拖入窗口；构建产物不会进入 Git。
