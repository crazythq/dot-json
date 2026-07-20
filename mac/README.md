# DotJSON macOS

DotJSON 的原生 macOS 14+ 客户端，使用 SwiftUI、AppKit 和 Swift Package Manager，零第三方依赖。

同一 Swift Package 还提供零依赖的 `dotjson` CLI；GUI 与 CLI 共同依赖
`DotJSONCore`，解析、格式化和压缩行为保持一致。

## MVP 功能

- 双面板文本编辑与 JSON 树浏览
- 格式化、压缩、2/4 空格或 Tab 实时缩进
- 标准粘贴自动格式化、复制和清空
- 打开、保存、另存为，以及格式化/压缩导出
- Finder/Dock 文件打开、窗口拖放和 `.json` 文件关联
- 精确错误行号、红色行号标记和悬停错误说明
- 树右键菜单：Copy Key / Copy Value（字符串自动去引号）/ Copy JSON Path
- 树双击展开/收起节点
- 左侧 ⌘F 原生查找栏（NSTextView usesFindBar）
- 右侧 ⌘F 内嵌搜索框（焦点感知，仅树面板聚焦时拦截）
- 搜索 200ms 防抖，Enter 切换下一个命中
- 搜索高亮 + 自动展开命中祖先链，不改变用户已有展开/收起状态

多标签、持久历史属于 V1；JSONL 导航和 JSON Diff 属于 V2，不在当前 MVP 范围。

## 开发与测试

```bash
cd mac
swift test
swift build --product DotJSON
swift build --product dotjson
```

## CLI

```bash
swift build --product dotjson
BIN_DIR="$(swift build --show-bin-path)"
"$BIN_DIR/dotjson" --help
```

CLI 支持 `format`、`minify`、`validate` 和保守型 `repair`：

```bash
cat model-output.txt | "$BIN_DIR/dotjson" repair
"$BIN_DIR/dotjson" format data.json --indent 2
"$BIN_DIR/dotjson" validate data.json --quiet
"$BIN_DIR/dotjson" repair data.json --write
```

省略 `FILE` 或传入 `-` 时读取 stdin。默认结果只写 stdout；只有显式传入
`--write` 才会原地修改文件。Agent 可加入 `--json-errors` 获取结构化错误。

## 构建本地 App

```bash
cd mac
./build-app.sh
open "$(swift build --show-bin-path)/DotJSON.app"
```

脚本会生成并 ad-hoc 签名 `DotJSON.app`。本地验证时，可在应用中打开 `.json` 文件，或把文件拖入窗口；构建产物不会进入 Git。
