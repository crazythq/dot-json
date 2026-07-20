import Testing
import Foundation
@testable import DotJSON

struct JSONLPreparserTests {

    @Test func parseSimpleJSONL() {
        let content = """
        {"id":1,"name":"Alice"}
        {"id":2,"name":"Bob"}
        {"id":3,"name":"Charlie"}
        """
        let preparser = JSONLPreparser(rawContent: content)
        #expect(preparser.count == 3)
        #expect(preparser.lines.filter { !$0.isValid }.isEmpty)
    }

    @Test func parseInvalidLines() {
        let content = """
        {"id":1}
        not json
        {"id":2}
        """
        let preparser = JSONLPreparser(rawContent: content)
        #expect(preparser.count == 3)
        #expect(preparser.lines[0].isValid == true)
        #expect(preparser.lines[1].isValid == false)
        #expect(preparser.lines[2].isValid == true)
    }

    @Test func parseLineByIndex() {
        let content = """
        {"x":100}
        {"y":200}
        """
        let preparser = JSONLPreparser(rawContent: content)
        let node = preparser.parseLine(at: 0)
        guard case .object(let pairs) = node else {
            Issue.record("Expected object")
            return
        }
        #expect(pairs.count == 1)
        #expect(pairs[0].key == "x")
    }

    @Test func emptyContent() {
        let preparser = JSONLPreparser(rawContent: "")
        #expect(preparser.count == 0)
    }

    @Test func skipTrailingEmptyLine() {
        let content = """
        {"a":1}

        """
        let preparser = JSONLPreparser(rawContent: content)
        #expect(preparser.count == 1)
    }

    @Test func skipTrailingEmptyLineWithSpaces() {
        let content = """
        {"a":1}

        """
        let preparser = JSONLPreparser(rawContent: content)
        #expect(preparser.count == 1)
        #expect(preparser.lines[0].isValid)
    }

    @Test func whitespaceOnlyContent() {
        let preparser = JSONLPreparser(rawContent: "   \n  ")
        #expect(preparser.count == 0)
    }

    @Test func linesWithChineseAndEmoji() {
        let content = """
        {"名称":"测试","emoji":"😀🎉"}
        {"值":100}
        """
        let preparser = JSONLPreparser(rawContent: content)
        #expect(preparser.count == 2)
        #expect(preparser.lines.filter { !$0.isValid }.isEmpty)
    }

    @Test func veryLongLineIsStillParsed() {
        let value = String(repeating: "x", count: 10_000)
        let line = "{\"key\":\"\(value)\"}"
        let preparser = JSONLPreparser(rawContent: line)
        #expect(preparser.count == 1)
        #expect(preparser.lines[0].isValid)
    }

    @Test func lineWithUnicodeEscapeIsValid() {
        let line = "{\"emoji\":\"\\ud83d\\ude00\"}"
        let preparser = JSONLPreparser(rawContent: line)
        #expect(preparser.count == 1)
    }

    @Test func outOfRangeIndexReturnsNil() {
        let preparser = JSONLPreparser(rawContent: #"{"x":1}"#)
        let result99 = preparser.parseLine(at: 99)
        #expect(result99 == nil)
    }

    @Test func unixStyleNewlines() {
        let content = "{\"a\":1}\n{\"b\":2}\n{\"c\":3}"
        let preparser = JSONLPreparser(rawContent: content)
        #expect(preparser.count == 3)
    }
}
