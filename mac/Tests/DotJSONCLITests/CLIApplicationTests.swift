import Foundation
import Testing
@testable import DotJSONCLI

private enum MemoryIOError: Error {
    case missingFile
    case forcedWriteFailure
}

private final class MemoryIOBox {
    var stdin: String
    var stdinIsTTY: Bool
    var files: [String: String]
    var failWrites = false

    init(stdin: String = "", stdinIsTTY: Bool = false, files: [String: String] = [:]) {
        self.stdin = stdin
        self.stdinIsTTY = stdinIsTTY
        self.files = files
    }

    var environment: CLIEnvironment {
        CLIEnvironment(
            stdinIsTTY: { self.stdinIsTTY },
            readStdin: { self.stdin },
            readFile: { path in
                guard let content = self.files[path] else { throw MemoryIOError.missingFile }
                return content
            },
            writeFile: { content, destination, _ in
                guard !self.failWrites else { throw MemoryIOError.forcedWriteFailure }
                self.files[destination] = content
            }
        )
    }
}

/// 从 Agent 管道视角验证 stdout、stderr 与退出码。
struct CLIApplicationTests {
    @Test func emptyInvocationShowsHelpWithUsageExitCode() {
        let box = MemoryIOBox(stdinIsTTY: true)
        let result = CLIApplication.run(arguments: [], environment: box.environment)
        #expect(result.exitCode == 2)
        #expect(result.stdout.contains("Usage:"))
        #expect(result.stderr.isEmpty)
    }

    @Test func formatsStdinToStdout() {
        let box = MemoryIOBox(stdin: #"{"b":2,"a":1}"#)
        let result = CLIApplication.run(
            arguments: ["format", "--indent", "2"],
            environment: box.environment
        )
        #expect(result == CLIResult(
            stdout: "{\n  \"a\": 1,\n  \"b\": 2\n}",
            stderr: "",
            exitCode: 0
        ))
    }

    @Test func repairsWithoutFormatting() {
        let box = MemoryIOBox(stdin: "{'ok': True, 'value': None}")
        let result = CLIApplication.run(arguments: ["repair"], environment: box.environment)
        #expect(result.stdout == "{\"ok\": true, \"value\": null}")
        #expect(result.exitCode == 0)
    }

    @Test func validatesQuietly() {
        let box = MemoryIOBox(stdin: "{bad")
        let result = CLIApplication.run(arguments: ["validate", "--quiet"], environment: box.environment)
        #expect(result == CLIResult(stdout: "", stderr: "", exitCode: 4))
    }

    @Test func validateHonorsGlobalJSONErrors() throws {
        let box = MemoryIOBox(stdin: "{bad")
        let result = CLIApplication.run(
            arguments: ["validate", "--json-errors"],
            environment: box.environment
        )
        #expect(result.stdout.isEmpty)
        #expect(result.exitCode == 4)
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(result.stderr.utf8)) as? [String: Any]
        )
        let error = try #require(root["error"] as? [String: Any])
        #expect(error["code"] as? String == "invalid_json")
    }

    @Test func returnsStructuredRepairError() throws {
        let box = MemoryIOBox(stdin: "first {} second []")
        let result = CLIApplication.run(
            arguments: ["repair", "--json-errors"],
            environment: box.environment
        )
        #expect(result.stdout.isEmpty)
        #expect(result.exitCode == 4)
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(result.stderr.utf8)) as? [String: Any]
        )
        let error = try #require(root["error"] as? [String: Any])
        #expect(error["code"] as? String == "unrepairable_json")
        #expect(error.keys.contains("line"))
        #expect(error.keys.contains("column"))
    }

    @Test func writesExplicitOutputWithoutStdout() {
        let box = MemoryIOBox(files: ["input.json": #"{"b":2,"a":1}"#])
        let result = CLIApplication.run(
            arguments: ["minify", "input.json", "--output", "output.json"],
            environment: box.environment
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.isEmpty)
        #expect(box.files["output.json"] == #"{"a":1,"b":2}"#)
    }

    @Test func writeFailureReturnsFiveWithoutChangingInput() {
        let box = MemoryIOBox(files: ["input.json": "{'ok': True}"])
        box.failWrites = true
        let result = CLIApplication.run(
            arguments: ["repair", "input.json", "--write"],
            environment: box.environment
        )
        #expect(result.exitCode == 5)
        #expect(result.stdout.isEmpty)
        #expect(box.files["input.json"] == "{'ok': True}")
    }

    @Test func formatWriteFailureIsOutputErrorNotJSONError() {
        let box = MemoryIOBox(files: ["input.json": #"{"ok":true}"#])
        box.failWrites = true
        let result = CLIApplication.run(
            arguments: ["format", "input.json", "--write"],
            environment: box.environment
        )
        #expect(result.exitCode == 5)
        #expect(result.stdout.isEmpty)
    }

    @Test func interactiveImplicitStdinShowsHelp() {
        let box = MemoryIOBox(stdinIsTTY: true)
        let result = CLIApplication.run(arguments: ["format"], environment: box.environment)
        #expect(result.exitCode == 2)
        #expect(result.stdout.contains("Usage:"))
    }
}
