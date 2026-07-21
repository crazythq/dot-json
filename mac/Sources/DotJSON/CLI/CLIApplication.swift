import DotJSONCore
import Foundation

/// 可替换的 CLI I/O 边界，测试无需操作真实标准流。
struct CLIEnvironment {
    let stdinIsTTY: () -> Bool
    let readStdin: () throws -> String
    let readFile: (_ path: String) throws -> String
    let writeFile: (
        _ content: String,
        _ destinationPath: String,
        _ sourcePathForPermissions: String?
    ) throws -> Void
}

/// 负责读取、执行、完整验证后再输出的 CLI 应用层。
enum CLIApplication {
    /// 只用于应用层流程控制，不暴露为用户错误。
    private enum ControlFlow: Error {
        case interactiveStdin
    }

    /// 执行一次调用并返回完整标准流内容与退出码。
    static func run(arguments: [String], environment: CLIEnvironment) -> CLIResult {
        if arguments.isEmpty {
            return CLIResult(stdout: CLIParser.help + "\n", stderr: "", exitCode: 2)
        }
        let wantsJSONErrors = arguments.contains("--json-errors")
        do {
            let invocation = try CLIParser.parse(arguments)
            return try execute(invocation, environment: environment)
        } catch ControlFlow.interactiveStdin {
            return CLIResult(stdout: CLIParser.help + "\n", stderr: "", exitCode: 2)
        } catch let error as CLIError {
            return render(error, json: wantsJSONErrors)
        } catch {
            return render(.input(error.localizedDescription), json: wantsJSONErrors)
        }
    }

    private static func execute(
        _ invocation: CLIInvocation,
        environment: CLIEnvironment
    ) throws -> CLIResult {
        switch invocation.command {
        case .help:
            return CLIResult(stdout: CLIParser.help + "\n", stderr: "", exitCode: 0)
        case .version:
            return CLIResult(stdout: CLIParser.version + "\n", stderr: "", exitCode: 0)
        case .format(let inputPath, let indent, let destination):
            let input = try readInput(path: inputPath, environment: environment)
            let output: String
            do { output = try JSONFormatter.format(input, indent: indent) }
            catch { throw invalidJSON(from: error, input: input) }
            return try deliver(output, inputPath: inputPath, destination: destination, environment: environment)
        case .minify(let inputPath, let destination):
            let input = try readInput(path: inputPath, environment: environment)
            let output: String
            do { output = try JSONFormatter.minify(input) }
            catch { throw invalidJSON(from: error, input: input) }
            return try deliver(output, inputPath: inputPath, destination: destination, environment: environment)
        case .repair(let inputPath, let destination):
            let input = try readInput(path: inputPath, environment: environment)
            do {
                let output = try JSONRepairer.repair(input)
                return try deliver(output, inputPath: inputPath, destination: destination, environment: environment)
            } catch let error as JSONRepairer.RepairError {
                let location = self.location(in: input, byteOffset: error.byteOffset)
                throw CLIError.unrepairableJSON(
                    message: error.localizedDescription,
                    line: location?.line,
                    column: location?.column
                )
            }
        case .validate(let inputPath, let mode):
            let input = try readInput(path: inputPath, environment: environment)
            return validate(input, mode: mode, jsonErrors: invocation.jsonErrors)
        }
    }

    private static func readInput(path: String?, environment: CLIEnvironment) throws -> String {
        if let path {
            do { return try environment.readFile(path) }
            catch { throw CLIError.input("Unable to read \(path): \(error.localizedDescription)") }
        }
        guard !environment.stdinIsTTY() else {
            throw ControlFlow.interactiveStdin
        }
        do { return try environment.readStdin() }
        catch { throw CLIError.input("Unable to read stdin: \(error.localizedDescription)") }
    }

    private static func validate(
        _ input: String,
        mode: ValidationOutputMode,
        jsonErrors: Bool
    ) -> CLIResult {
        do {
            _ = try JSONFormatter.validate(input)
            switch mode {
            case .human: return CLIResult(stdout: "Valid JSON\n", stderr: "", exitCode: 0)
            case .quiet: return CLIResult(stdout: "", stderr: "", exitCode: 0)
            case .json: return CLIResult(stdout: "{\"valid\":true}\n", stderr: "", exitCode: 0)
            }
        } catch {
            let cliError = invalidJSON(from: error, input: input)
            switch mode {
            case .quiet:
                return CLIResult(stdout: "", stderr: "", exitCode: 4)
            case .json:
                let detail = errorDictionary(for: cliError)
                return CLIResult(stdout: encodeJSONObject(["valid": false, "error": detail]), stderr: "", exitCode: 4)
            case .human:
                return render(cliError, json: jsonErrors)
            }
        }
    }

    private static func deliver(
        _ content: String,
        inputPath: String?,
        destination: OutputDestination,
        environment: CLIEnvironment
    ) throws -> CLIResult {
        switch destination {
        case .standardOutput:
            return CLIResult(stdout: content, stderr: "", exitCode: 0)
        case .writeInput:
            guard let inputPath else { throw CLIError.usage("--write requires a file input.") }
            do { try environment.writeFile(content, inputPath, inputPath) }
            catch { throw CLIError.output("Unable to write \(inputPath): \(error.localizedDescription)") }
            return CLIResult(stdout: "", stderr: "", exitCode: 0)
        case .outputFile(let outputPath):
            if let inputPath,
               URL(fileURLWithPath: inputPath).standardizedFileURL
                == URL(fileURLWithPath: outputPath).standardizedFileURL {
                throw CLIError.usage("Input and output paths are identical; use --write.")
            }
            do { try environment.writeFile(content, outputPath, nil) }
            catch { throw CLIError.output("Unable to write \(outputPath): \(error.localizedDescription)") }
            return CLIResult(stdout: "", stderr: "", exitCode: 0)
        }
    }

    private static func invalidJSON(from error: any Error, input: String) -> CLIError {
        let cocoaError = error as NSError
        let offset = cocoaError.userInfo["NSJSONSerializationErrorIndex"] as? Int
        let position = location(in: input, byteOffset: offset)
        return .invalidJSON(message: cocoaError.localizedDescription, line: position?.line, column: position?.column)
    }

    private static func location(in input: String, byteOffset: Int?) -> (line: Int, column: Int)? {
        guard let byteOffset else { return nil }
        let safeOffset = min(max(byteOffset, 0), input.utf8.count)
        var line = 1
        var column = 1
        for byte in input.utf8.prefix(safeOffset) {
            if byte == 0x0A { line += 1; column = 1 }
            else { column += 1 }
        }
        return (line, column)
    }

    private static func render(_ error: CLIError, json: Bool) -> CLIResult {
        let stderr = json
            ? encodeJSONObject(["error": errorDictionary(for: error)])
            : "Error: \(error.message)\n"
        return CLIResult(stdout: "", stderr: stderr, exitCode: error.exitCode)
    }

    private static func errorDictionary(for error: CLIError) -> [String: Any] {
        [
            "code": error.machineCode,
            "message": error.message,
            "line": error.line ?? NSNull(),
            "column": error.column ?? NSNull(),
        ]
    }

    private static func encodeJSONObject(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else {
            return "{\"error\":{\"code\":\"output_error\",\"message\":\"Unable to encode diagnostic.\",\"line\":null,\"column\":null}}\n"
        }
        return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
    }
}
