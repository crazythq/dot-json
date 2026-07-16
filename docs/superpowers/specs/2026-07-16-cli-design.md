# DotJSON CLI 设计

## 背景

DotJSON 当前只有 macOS 图形客户端。解析、格式化和压缩能力已经存在，但与 SwiftUI/AppKit 代码位于同一个 executable target 中，终端脚本和 AI Agent 无法通过稳定接口复用。

本设计增加独立的 `dotjson` 命令。它同时照顾人类终端体验和机器调用：默认输出可直接进入管道，错误具有稳定退出码，并可切换为结构化 JSON。项目继续保持 Swift/Foundation 零第三方依赖。

## 目标

- 提供 `format`、`minify`、`validate` 和 `repair` 四个子命令。
- 支持文件输入、stdin、stdout、输出到新文件和显式原地写回。
- 让 macOS App 与 CLI 共享同一套 JSON 解析和格式化实现。
- 保守修复常见 AI 输出包装和 Python `dict` / `list` 文本表示。
- 为 Agent 提供无交互行为、结构化错误和稳定退出码。
- 保持 macOS App 的现有用户行为和 `DotJSON` 可执行文件名称不变。

## 非目标

- 不实现 jq、JSONPath、字段查询或数据变换语言。
- 不调用任何大模型或网络 API。
- 不修复需要推断业务含义的损坏数据。
- 不支持 Python tuple、set、bytes 或任意 Python 表达式。
- 不为 uTools 或 Raycast 增加 CLI 适配。
- 不在 `repair` 中隐式格式化、压缩或排序 key。

## 包结构

Swift Package 调整为三个生产 target：

```text
DotJSONCore
├── JSONNode
├── JSONParser
├── JSONFormatter
└── JSONRepairer

DotJSON (macOS App) ──> DotJSONCore
dotjson (CLI) ────────> DotJSONCore
```

`DotJSONCore` 是纯 Swift/Foundation 模块，不依赖 SwiftUI 或 AppKit。现有平台无关模型移入该模块，并为跨模块调用补齐必要的 `public` 访问级别。macOS 专属树视图辅助类型、ViewModel 和 Views 继续留在 `DotJSON` target。

`dotjson` target 只负责参数解析、输入输出、错误呈现和进程退出码。命令业务逻辑委托给 `DotJSONCore`，不复制解析或格式化实现。参数解析使用项目内的轻量实现，不引入 Swift Argument Parser。

测试继续通过 SwiftPM 管理：核心行为由 `DotJSONCore` 测试覆盖，CLI target 的参数和 I/O 合同由独立测试覆盖，现有 App 测试继续依赖 `DotJSON`。

## 命令合同

```text
dotjson format [FILE|-] [--indent 2|4|tab] [--write | --output PATH]
dotjson minify [FILE|-] [--write | --output PATH]
dotjson validate [FILE|-] [--quiet | --json]
dotjson repair [FILE|-] [--write | --output PATH]
dotjson --help
dotjson --version
```

### 通用输入规则

- 一个命令最多接受一个位置参数。
- 省略 `FILE` 或传入 `-` 时读取 stdin。
- 省略输入且 stdin 连接交互式终端时，不阻塞等待；显示帮助并以用法错误结束。
- 文件按 UTF-8 读取。无法读取或文本不是 UTF-8 时返回输入错误。

### 通用输出规则

- 未指定写入选项时，成功结果只写 stdout，不混入状态提示。
- `--output PATH` 把结果原子写入指定路径，stdout 保持为空；目标已存在时直接替换。
- `--output PATH` 解析后的路径若与输入文件相同则报用法错误，原地更新必须显式使用 `--write`。
- `--write` 只允许用于真实文件输入，不允许与 stdin、`-` 或 `--output` 同时使用。
- `--write` 必须先在内存中完成处理与验证，再通过同目录临时文件原子替换；替换后保留原文件权限，任何失败都保留原文件。
- `--output` 和 `--write` 的成功路径不向 stderr 输出提示。
- 人类可读错误默认写 stderr；全局 `--json-errors` 将错误切换为结构化 JSON。
- `--json-errors` 可以出现在子命令之前或之后，但不能重复。

### `format`

- 解析输入并输出可读 JSON。
- `--indent` 接受 `2`、`4` 或 `tab`，默认值为 `4`。
- 沿用 `JSONFormatter` 的确定性 key 排序行为。
- JSON 无效时不产生 stdout 内容。

### `minify`

- 解析输入并输出单行 JSON。
- 沿用 `JSONFormatter` 的确定性 key 排序行为。
- JSON 无效时不产生 stdout 内容。

### `validate`

- 默认成功输出 `Valid JSON\n`，失败信息写 stderr。
- `--quiet` 在成功或失败时都不输出业务内容，仅保留退出码；参数错误和 I/O 错误仍写 stderr。
- `--json` 成功输出 `{"valid":true}`，JSON 无效时输出 `{"valid":false,"error":{...}}`。
- `--quiet` 与 `--json` 互斥。
- `validate` 不接受 `--write` 或 `--output`。

### `repair`

- 只修改生成合法 JSON 所必需的字符，不执行格式化、压缩或 key 排序。
- 已经合法的标准 JSON 必须原样输出，包括原有缩进、换行和结尾换行。
- 需要进一步排版时由调用方显式组合命令，例如：

  ```bash
  cat model-output.txt | dotjson repair | dotjson format --indent 2
  ```

## `repair` 规则

### 总体原则

`JSONRepairer` 使用字符串感知的词法扫描和状态机，不能通过全局字符串替换实现。每一步都必须保持确定性；发现多个合理解释时立即失败。修复后的完整文本必须再次交给标准 JSON 解析器验证，验证成功后才可输出或写回。

修复失败时不输出部分结果。

### 修复流水线

1. 先按原文执行标准 JSON 验证；验证成功则原样返回。
2. 必要时移除 UTF-8 BOM。
3. 识别唯一候选 JSON 内容：
   - 一个 Markdown 围栏中的对象或数组，围栏可无语言标签，或使用 `json`、`python` 标签；
   - 模型说明文字中唯一、括号完整的顶层对象或数组。
4. 对候选内容执行词法修复：
   - Python 单引号字符串转换为合法 JSON 双引号字符串；
   - 独立 token `True` 转为 `true`；
   - 独立 token `False` 转为 `false`；
   - 独立 token `None` 转为 `null`；
   - 删除对象或数组最后一项后的尾逗号。
5. 使用标准 JSON 解析器验证完整结果。验证失败时返回不可修复错误。

候选扫描必须理解双引号和单引号字符串及其转义，字符串内的括号不参与层级计数。若输入包含多个围栏、多个完整顶层候选，或候选之外还有另一个可解析结构，则视为歧义并拒绝修复。

### Python 字符串子集

单引号字符串支持 Python `repr` 常见且可无歧义转换的转义：`\\`、`\'`、`\"`、`\n`、`\r`、`\t`、`\b`、`\f`、`\xNN`、`\uNNNN` 和 `\UNNNNNNNN`。转换后必须使用合法 JSON 转义；超出 Unicode 范围、孤立代理项、不完整或未知转义均拒绝修复。

`True`、`False` 和 `None` 只有在字符串之外且构成完整 token 时才转换。例如字符串 `'True story'` 的内容保持不变，标识符 `TrueValue` 不会被部分替换。

### 明确拒绝的输入

- 未加引号的对象 key；
- JavaScript 或 Python 注释；
- tuple、set、bytes；
- `NaN`、`Infinity`；
- 缺失括号、截断数组或截断对象；
- 多个 JSON 对象自动合并；
- 无法确定含义的引号、转义或重复候选；
- 顶层 Python 标量。Python 修复入口仅接受 `dict` 或 `list` 对应的对象或数组。

## 错误合同

### 退出码

| 退出码 | 含义 |
| --- | --- |
| `0` | 成功 |
| `2` | 参数或用法错误 |
| `3` | 输入读取失败 |
| `4` | JSON 无效或无法保守修复 |
| `5` | 输出写入失败 |

### 结构化错误

启用 `--json-errors` 后，stderr 每次只输出一个 JSON 对象：

```json
{
  "error": {
    "code": "unrepairable_json",
    "message": "Multiple JSON candidates found.",
    "line": 3,
    "column": 1
  }
}
```

`error.code` 是稳定的机器合同，只使用 `usage_error`、`input_error`、`invalid_json`、`unrepairable_json` 和 `output_error` 五种值。`message` 面向人类，可在不破坏合同的前提下改进。无法定位到输入文本时，`line` 和 `column` 为 `null`；存在位置时均从 1 开始，并映射到原始输入而非抽取后的候选片段。

所有错误路径必须保持 stdout 为空；唯一例外是 `validate --json`，JSON 无效属于该命令的业务结果，因此在 stdout 输出 `valid:false`，同时返回退出码 `4`，stderr 为空。参数和 I/O 错误仍遵循通用 stderr 合同。

## 数据流

```text
arguments
   │
   ▼
CLI parser ──> input source ──> command operation ──> complete validation
                                                      │
                         ┌────────────────────────────┴─────────────────────┐
                         ▼                                                  ▼
                stdout / output file                              stderr / exit code
```

CLI 层先完整解析参数，再读取输入。命令操作产生完整字符串或结构化失败，不直接写流。只有操作成功后，输出层才选择 stdout、新文件或原子写回。这个边界保证失败时不会泄漏半截 JSON，也使参数解析、业务处理和文件系统行为可以独立测试。

## 测试策略

### 核心单元测试

- 合法 JSON 原样通过，包含缩进、空白、结尾换行和字符串中的 Python token。
- Python `dict` / `list` 的嵌套组合、空容器、单引号、`True`、`False`、`None`。
- Python 字符串中的引号、反斜线、控制字符、Unicode 与 `\xNN` 转换。
- 对象和数组尾逗号，包括嵌套结构。
- 单个 Markdown 围栏、唯一模型回复候选和候选原始排版保留。
- 多围栏、多候选、截断结构、未知转义及所有明确拒绝类型。
- 修复结果必须能被标准 JSON 解析器接受。

### CLI 合同测试

- 每个命令的文件输入、stdin 输入和 `-` 输入。
- stdout、stderr 与五种稳定退出码。
- `--write` 的成功、失败保护和参数互斥。
- `--output` 的成功与写入失败。
- `validate --quiet`、`validate --json` 和 `--json-errors`。
- 缺少子命令、未知命令、未知选项、重复选项和多余位置参数。
- 无管道的交互式空调用显示帮助而不阻塞。

### 回归验证

- 运行完整 `swift test`，现有 macOS App 测试必须继续通过。
- 分别执行 `swift build --product DotJSON` 和 `swift build --product dotjson`。
- 使用构建出的真实 `dotjson` 二进制执行至少一条 stdin 管道和一次原子 `--write` 冒烟验证。
- 执行 `build-app.sh`，确认 App bundle 中仍包含正确的 `DotJSON` GUI 可执行文件。

## 文档与交付

- 根 README 增加 CLI 功能、构建方式以及人类终端示例。
- `mac/README.md` 增加 SwiftPM 产品构建与本地运行方式。
- 文档提供 Agent 组合示例、`--json-errors` 结构和退出码表。
- CLI 初始版本与 App 当前版本保持一致，为 `0.1.0`；后续发布时二者同步更新。

## 验收标准

- `dotjson` 四个子命令均可通过文件和 stdin 工作。
- CLI 默认输出可直接进入下一个 Unix 管道，不含额外提示文字。
- `repair` 可把确认范围内的 Python `dict` / `list` 文本和常见单块 AI 包装修复为标准 JSON。
- `repair` 不改变合法 JSON 的排版，也不会对歧义输入进行猜测。
- 所有失败路径符合 stdout、stderr 和退出码合同。
- `--write` 失败时输入文件保持不变。
- App 与 CLI 共享核心实现，项目无新增第三方依赖。
- 完整测试、两个 SwiftPM 产品构建和 App bundle 构建全部通过。
