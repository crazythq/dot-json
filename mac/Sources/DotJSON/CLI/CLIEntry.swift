import Darwin
import Foundation

/// CLI 模式入口，由 DotJSONApp 的 `--cli` 分支调用。
enum CLIEntry {
    static func main() {
        let environment = CLIEnvironment(
            stdinIsTTY: { isatty(STDIN_FILENO) != 0 },
            readStdin: {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                guard let text = String(data: data, encoding: .utf8) else {
                    throw CLIError.input("stdin is not valid UTF-8.")
                }
                return text
            },
            readFile: { path in
                try String(contentsOfFile: path, encoding: .utf8)
            },
            writeFile: { content, destination, source in
                try AtomicFileWriter.write(content, to: destination, preservingModeFrom: source)
            }
        )
        let result = CLIApplication.run(
            arguments: Array(CommandLine.arguments.dropFirst()).filter { $0 != "--cli" },
            environment: environment
        )
        FileHandle.standardOutput.write(Data(result.stdout.utf8))
        FileHandle.standardError.write(Data(result.stderr.utf8))
        exit(result.exitCode)
    }
}
