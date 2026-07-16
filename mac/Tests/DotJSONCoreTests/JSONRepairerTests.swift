import Testing
@testable import DotJSONCore

/// 验证保守修复器只做必要修改，并拒绝任何有歧义的输入。
struct JSONRepairerTests {
    @Test func preservesValidJSONByteForByte() throws {
        let input = "{\n  \"enabled\": true\n}\n"
        #expect(try JSONRepairer.repair(input) == input)
    }

    @Test func repairsNestedPythonCollections() throws {
        let input = "{'enabled': True, 'items': [None, {'ok': False}]}"
        let expected = "{\"enabled\": true, \"items\": [null, {\"ok\": false}]}"
        #expect(try JSONRepairer.repair(input) == expected)
    }

    @Test func preservesTokenWordsInsideStrings() throws {
        let input = "{'message': 'True None False', 'TrueValue': True}"
        let expected = "{\"message\": \"True None False\", \"TrueValue\": true}"
        #expect(try JSONRepairer.repair(input) == expected)
    }

    @Test func convertsPythonStringEscapes() throws {
        let input = #"{'owner': 'Bob\'s', 'byte': '\x41', 'face': '\U0001F600'}"#
        let expected = #"{"owner": "Bob's", "byte": "A", "face": "😀"}"#
        #expect(try JSONRepairer.repair(input) == expected)
    }

    @Test func removesTrailingCommasWithoutFormatting() throws {
        let input = "{\n  'items': [1, 2,],\n  'ok': True,\n}\n"
        let expected = "{\n  \"items\": [1, 2],\n  \"ok\": true\n}\n"
        #expect(try JSONRepairer.repair(input) == expected)
    }

    @Test func extractsOneMarkdownFence() throws {
        let input = "Result:\n```python\n{\n  'ok': True,\n}\n```\n"
        let expected = "{\n  \"ok\": true\n}\n"
        #expect(try JSONRepairer.repair(input) == expected)
    }

    @Test func extractsUniqueCandidateFromProse() throws {
        let input = "The generated value is {'items': [1, 2,], 'ok': True}."
        let expected = "{\"items\": [1, 2], \"ok\": true}"
        #expect(try JSONRepairer.repair(input) == expected)
    }

    @Test func ignoresBracketsInsidePythonStrings() throws {
        let input = "answer: {'text': 'literal } and ]', 'ok': True}"
        let expected = "{\"text\": \"literal } and ]\", \"ok\": true}"
        #expect(try JSONRepairer.repair(input) == expected)
    }

    @Test(arguments: [
        "```json\n{}\n```\n```json\n[]\n```",
        "first {} and second []",
        "{'open': [1, 2}",
        "(1, 2)",
        "{'x': {1, 2}}",
        "{'x': b'raw'}",
        "{'x': NaN}",
        "{unquoted: True}",
        "{'x': 1 // comment}"
    ])
    func rejectsAmbiguousOrUnsupportedInput(_ input: String) {
        #expect(throws: JSONRepairer.RepairError.self) {
            try JSONRepairer.repair(input)
        }
    }
}
