import DotJSONCore
import DotJSONCore
import Foundation

/// 零依赖命令行参数解析器。
enum CLIParser {
    static let version = "0.1.0"

    static let help = """
    DotJSON 0.1.0

    Usage:
      dotjson format [FILE|-] [--indent 2|4|tab] [--write | --output PATH]
      dotjson minify [FILE|-] [--write | --output PATH]
      dotjson validate [FILE|-] [--quiet | --json]
      dotjson repair [FILE|-] [--write | --output PATH]
      dotjson --help
      dotjson --version

    Global option:
      --json-errors  Write machine-readable errors to stderr.
    """

    /// 把原始参数转换为无歧义命令。
    ///
    /// - Parameter rawArguments: 不包含可执行文件名的参数数组。
    /// - Returns: 已验证的调用对象。
    /// - Throws: 未知、重复、缺值或互斥参数抛出 `CLIError.usage`。
    static func parse(_ rawArguments: [String]) throws -> CLIInvocation {
        let jsonErrorCount = rawArguments.filter { $0 == "--json-errors" }.count
        guard jsonErrorCount <= 1 else { throw usage("--json-errors may only be supplied once.") }
        let arguments = rawArguments.filter { $0 != "--json-errors" }
        guard let commandName = arguments.first else { throw usage("Missing command.") }

        if commandName == "--help" {
            guard arguments.count == 1 else { throw usage("--help does not accept arguments.") }
            return CLIInvocation(command: .help, jsonErrors: jsonErrorCount == 1)
        }
        if commandName == "--version" {
            guard arguments.count == 1 else { throw usage("--version does not accept arguments.") }
            return CLIInvocation(command: .version, jsonErrors: jsonErrorCount == 1)
        }

        let tail = Array(arguments.dropFirst())
        let command: CLICommand
        switch commandName {
        case "format": command = try parseFormat(tail)
        case "minify": command = try parseTransform(tail, operation: .minify)
        case "repair": command = try parseTransform(tail, operation: .repair)
        case "validate": command = try parseValidate(tail)
        default: throw usage("Unknown command: \(commandName).")
        }
        return CLIInvocation(command: command, jsonErrors: jsonErrorCount == 1)
    }

    /// 解析 `format` 专属缩进和通用输出参数。
    private static func parseFormat(_ arguments: [String]) throws -> CLICommand {
        var state = TransformState()
        var indent = JSONFormatter.Indent.fourSpaces
        var seenIndent = false
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            if token == "--indent" {
                guard !seenIndent else { throw usage("--indent may only be supplied once.") }
                seenIndent = true
                index += 1
                guard index < arguments.count else { throw usage("--indent requires 2, 4, or tab.") }
                switch arguments[index] {
                case "2": indent = .twoSpaces
                case "4": indent = .fourSpaces
                case "tab": indent = .tab
                default: throw usage("--indent requires 2, 4, or tab.")
                }
            } else {
                try consumeTransformToken(token, arguments: arguments, index: &index, state: &state)
            }
            index += 1
        }
        try validateTransformState(state)
        return .format(inputPath: state.inputPath, indent: indent, destination: state.destination)
    }

    private enum TransformOperation { case minify, repair }

    /// 解析 `minify` 与 `repair` 的共享文件参数。
    private static func parseTransform(
        _ arguments: [String],
        operation: TransformOperation
    ) throws -> CLICommand {
        var state = TransformState()
        var index = 0
        while index < arguments.count {
            try consumeTransformToken(
                arguments[index],
                arguments: arguments,
                index: &index,
                state: &state
            )
            index += 1
        }
        try validateTransformState(state)
        switch operation {
        case .minify: return .minify(inputPath: state.inputPath, destination: state.destination)
        case .repair: return .repair(inputPath: state.inputPath, destination: state.destination)
        }
    }

    /// `format/minify/repair` 共享的可变解析状态。
    private struct TransformState {
        var inputPath: String?
        var inputSpecified = false
        var destination = OutputDestination.standardOutput
        var destinationSpecified = false
    }

    /// 消费一个转换命令 token，并在遇到 `--output` 时同步推进索引。
    private static func consumeTransformToken(
        _ token: String,
        arguments: [String],
        index: inout Int,
        state: inout TransformState
    ) throws {
        switch token {
        case "--write":
            guard !state.destinationSpecified else { throw usage("--write conflicts with another output option.") }
            state.destination = .writeInput
            state.destinationSpecified = true
        case "--output":
            guard !state.destinationSpecified else { throw usage("--output conflicts with another output option.") }
            index += 1
            guard index < arguments.count, !arguments[index].hasPrefix("-") else {
                throw usage("--output requires a path.")
            }
            state.destination = .outputFile(arguments[index])
            state.destinationSpecified = true
        default:
            guard !token.hasPrefix("-") || token == "-" else { throw usage("Unknown option: \(token).") }
            guard !state.inputSpecified else { throw usage("Only one input may be supplied.") }
            state.inputSpecified = true
            state.inputPath = token == "-" ? nil : token
        }
    }

    /// 校验原地写回只用于真实文件输入。
    private static func validateTransformState(_ state: TransformState) throws {
        if state.destination == .writeInput, state.inputPath == nil {
            throw usage("--write requires a file input.")
        }
    }

    /// 解析 `validate` 的两种机器模式。
    private static func parseValidate(_ arguments: [String]) throws -> CLICommand {
        var inputPath: String?
        var inputSpecified = false
        var mode = ValidationOutputMode.human
        var modeSpecified = false

        for token in arguments {
            switch token {
            case "--quiet":
                guard !modeSpecified else { throw usage("--quiet conflicts with another validation mode.") }
                mode = .quiet
                modeSpecified = true
            case "--json":
                guard !modeSpecified else { throw usage("--json conflicts with another validation mode.") }
                mode = .json
                modeSpecified = true
            default:
                guard !token.hasPrefix("-") || token == "-" else { throw usage("Unknown option: \(token).") }
                guard !inputSpecified else { throw usage("Only one input may be supplied.") }
                inputSpecified = true
                inputPath = token == "-" ? nil : token
            }
        }
        return .validate(inputPath: inputPath, mode: mode)
    }

    /// 创建统一的用法错误。
    private static func usage(_ message: String) -> CLIError { .usage(message) }
}
