import Darwin
import Foundation

/// `dotjson` 进程入口，只负责连接真实标准流与应用层。
@main
enum DotJSONCLIEntry {
    /// 构造真实 I/O 环境、执行命令并返回稳定退出码。
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
            arguments: Array(CommandLine.arguments.dropFirst()),
            environment: environment
        )
        FileHandle.standardOutput.write(Data(result.stdout.utf8))
        FileHandle.standardError.write(Data(result.stderr.utf8))
        exit(result.exitCode)
    }
}
