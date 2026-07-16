import Testing
@testable import DotJSONCLI

/// 锁定 CLI 参数解析的稳定合同。
struct CLIParserTests {
    @Test func parsesFormatFromStdin() throws {
        let invocation = try CLIParser.parse(["format", "--indent", "2"])
        #expect(invocation == CLIInvocation(
            command: .format(inputPath: nil, indent: .twoSpaces, destination: .standardOutput),
            jsonErrors: false
        ))
    }

    @Test func parsesRepairWriteAndJSONErrors() throws {
        let invocation = try CLIParser.parse(["repair", "sample.json", "--write", "--json-errors"])
        #expect(invocation == CLIInvocation(
            command: .repair(inputPath: "sample.json", destination: .writeInput),
            jsonErrors: true
        ))
    }

    @Test func parsesValidateModes() throws {
        #expect(try CLIParser.parse(["validate", "-", "--quiet"]).command
            == .validate(inputPath: nil, mode: .quiet))
        #expect(try CLIParser.parse(["--json-errors", "validate", "a.json", "--json"]).command
            == .validate(inputPath: "a.json", mode: .json))
    }

    @Test(arguments: [
        ["unknown"],
        ["format", "a.json", "b.json"],
        ["format", "--indent", "8"],
        ["repair", "-", "--write"],
        ["repair", "a.json", "--write", "--output", "b.json"],
        ["validate", "--quiet", "--json"],
        ["validate", "a.json", "--output", "b.json"],
        ["format", "--json-errors", "--json-errors"]
    ])
    func rejectsInvalidArguments(_ arguments: [String]) {
        #expect(throws: CLIError.self) {
            try CLIParser.parse(arguments)
        }
    }
}
