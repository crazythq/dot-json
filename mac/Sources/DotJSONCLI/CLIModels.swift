import DotJSONCore
import Foundation

/// 命令处理结果的写入位置。
enum OutputDestination: Equatable {
    case standardOutput
    case outputFile(String)
    case writeInput
}

/// `validate` 的输出模式。
enum ValidationOutputMode: Equatable {
    case human
    case quiet
    case json
}

/// 已完成语法校验的 CLI 命令。
enum CLICommand: Equatable {
    case format(inputPath: String?, indent: JSONFormatter.Indent, destination: OutputDestination)
    case minify(inputPath: String?, destination: OutputDestination)
    case validate(inputPath: String?, mode: ValidationOutputMode)
    case repair(inputPath: String?, destination: OutputDestination)
    case help
    case version
}

/// 一次完整的命令行调用。
struct CLIInvocation: Equatable {
    let command: CLICommand
    let jsonErrors: Bool
}

/// CLI 稳定错误合同。
enum CLIError: Error, Equatable {
    case usage(String)
    case input(String)
    case invalidJSON(message: String, line: Int?, column: Int?)
    case unrepairableJSON(message: String, line: Int?, column: Int?)
    case output(String)

    /// 进程退出码。
    var exitCode: Int32 {
        switch self {
        case .usage: return 2
        case .input: return 3
        case .invalidJSON, .unrepairableJSON: return 4
        case .output: return 5
        }
    }

    /// 供 Agent 稳定解析的错误代码。
    var machineCode: String {
        switch self {
        case .usage: return "usage_error"
        case .input: return "input_error"
        case .invalidJSON: return "invalid_json"
        case .unrepairableJSON: return "unrepairable_json"
        case .output: return "output_error"
        }
    }

    /// 面向终端用户的错误文案。
    var message: String {
        switch self {
        case .usage(let message), .input(let message), .output(let message): return message
        case .invalidJSON(let message, _, _), .unrepairableJSON(let message, _, _): return message
        }
    }

    /// 原输入中的 1-based 行号。
    var line: Int? {
        switch self {
        case .invalidJSON(_, let line, _), .unrepairableJSON(_, let line, _): return line
        default: return nil
        }
    }

    /// 原输入中的 1-based 列号。
    var column: Int? {
        switch self {
        case .invalidJSON(_, _, let column), .unrepairableJSON(_, _, let column): return column
        default: return nil
        }
    }
}

/// CLI 向进程标准流提交的完整结果。
struct CLIResult: Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}
