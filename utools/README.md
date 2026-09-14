# DotJSON — uTools 插件

对照 macOS 版 DotJSON 核心能力实现的 uTools 插件：双面板编辑 + JSON 树浏览、格式化/压缩、修复、搜索与右键复制。

## 目录结构

```
utools/
├── plugin.json      # uTools 插件配置（入口 / 指令 / 高度）
├── preload.js       # Node/Electron 桥接（读写文件、剪贴板）
├── index.html       # 插件 UI 入口
├── index.css        # 深色主题样式（对齐 Mac 应用配色）
├── index.js         # 交互与树渲染
├── logo.png         # 插件图标（256×256，由 icon.png 生成）
├── icon.png         # 1024 源图标
├── lib/
│   └── json-core.js # 格式化 / 压缩 / 修复 / 树模型（对照 DotJSONCore）
└── README.md
```

## 在 uTools 中加载（开发模式）

1. 安装 [uTools](https://www.u-tools.cn/) 与「uTools 开发者工具」插件。
2. 打开「uTools 开发者工具」→ **新建项目** / **选择插件**。
3. 插件目录选本仓库的 `utools/`（需包含 `plugin.json`）。
4. 保存后，主搜索框输入 `json` 或 `dotjson` 即可打开。

也可：在开发者工具中直接「选择本地插件目录」指向本 `utools/` 文件夹。

## 功能清单

| 功能 | 说明 | 对应 Mac 应用 |
|------|------|----------------|
| 双面板 | 左文本编辑 / 右树浏览，可拖拽分栏 | ContentView 双栏 |
| 格式化 / 压缩 | 工具栏按钮；缩进 2 / 4 / Tab | FM-01 ~ FM-03 |
| 修复 | Markdown 围栏、True/False/None、尾逗号、单引号等保守修复 | JSONRepairer |
| 粘贴自动格式化 | 粘贴后尝试 format，失败则 repair 再 format | ED-05 |
| 清空 / 复制全文 | 工具栏 | TB-03 |
| 打开 / 导出文件 | 系统对话框；也可匹配 `.json` 文件进入 | FL-01 / FL-04 |
| 树浏览 + 类型着色 | string / number / bool·null / 容器 | TR-01 ~ TR-02 |
| 双击展开收起 | 容器节点 | TR-03 |
| 树搜索 | 防抖 200ms，↑↓ / Enter 切换命中并展开祖先 | SE-03 ~ SE-08 |
| 右键菜单 | Copy Key / Value / JSON Path | CM-01 ~ CM-03 |
| 指令 | `json` / `dotjson`；选中文本 over；`.json` 文件匹配 | — |

未移植（刻意简化）：多标签、最近文件、行号标尺、JSONL、Diff。

## 本地自检（可选）

在浏览器直接打开 `index.html` 可看 UI（无 `utools` / preload 时使用示例 JSON，文件对话框不可用）。  
完整能力需在 uTools 开发者模式加载。

```bash
# 快速校验 JSON 核心逻辑
node -e "
  global.window = global;
  require('./lib/json-core.js');
  const c = DotJSONCore;
  console.log(c.format('{\"b\":1,\"a\":2}', 'twoSpaces'));
  console.log(c.minify(c.repair(\"{'x': True,}\")));
"
```
