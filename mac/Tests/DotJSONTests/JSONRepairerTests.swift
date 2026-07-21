import DotJSONCore
import Testing
@testable import DotJSON

struct JSONRepairerTests {

    @Test func repairsPythonStyleObjectWithSingleQuotedKeyAndBoolean() throws {
        let input = """
        {
          'visible123': True
        }
        """

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == """
        {
          "visible123": true
        }
        """)
    }

    @Test func repairsMixedPythonReprAndLooseJSONTokens() throws {
        let input = """
        {
          visible123: True,
          "alreadyJson": true,
          'singleQuoted': False,
          nested_key: {'child': None, "ok": true,}
        }
        """

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == """
        {
          "visible123": true,
          "alreadyJson": true,
          "singleQuoted": false,
          "nested_key": {"child": null, "ok": true}
        }
        """)
    }

    @Test func doesNotGuessBareValuesAsStrings() {
        #expect(throws: JSONRepairer.RepairError.self) {
            try JSONRepairer.repair("{visible123: hello}")
        }
    }

    @Test func repairsUnquotedKeyThatMatchesJSONLiteralName() throws {
        let repaired = try JSONRepairer.repair("{true: False, null: None}")

        #expect(repaired == #"{"true": false, "null": null}"#)
    }

    // MARK: - 数组修复

    @Test func repairsPythonStyleList() throws {
        let input = "[1, 2, True, False, None]"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == "[1, 2, true, false, null]")
    }

    @Test func repairsNestedArray() throws {
        let input = "[[True, False], [None, 42]]"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == "[[true, false], [null, 42]]")
    }

    @Test func repairsArrayOfDicts() throws {
        let input = """
        [{'name': 'Alice', 'active': True}, {'name': 'Bob', 'active': False}]
        """

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == """
        [{"name": "Alice", "active": true}, {"name": "Bob", "active": false}]
        """)
    }

    // MARK: - 已合法 JSON 原样返回

    @Test func validJSONPassesThrough() throws {
        let input = #"{"name":"Alice","age":30}"#

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == input)
    }

    @Test func validArrayPassesThrough() throws {
        let input = "[1, 2, 3]"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == input)
    }

    // MARK: - 尾逗号

    @Test func stripsTrailingCommasInObject() throws {
        let input = "{'a': 1, 'b': 2,}"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == #"{"a": 1, "b": 2}"#)
    }

    @Test func stripsTrailingCommasInNestedObject() throws {
        let input = "{'outer': {'inner': True,},}"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == #"{"outer": {"inner": true}}"#)
    }

    @Test func stripsTrailingCommasInArray() throws {
        let input = "[1, 2, 3,]"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == "[1, 2, 3]")
    }

    // MARK: - 字符串转义

    @Test func repairsSingleQuotedStringWithEscapes() throws {
        let input = #"{'path': 'C:\\Users\\test\\file.txt'}"#

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == #"{"path": "C:\\Users\\test\\file.txt"}"#)
    }

    @Test func repairsStringWithNewlines() throws {
        let input = "{'message': 'line1\\nline2\\nline3'}"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired.contains("\\n"))
    }

    @Test func repairsStringWithTabEscape() throws {
        let input = "{'data': 'col1\\tcol2'}"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired.contains("\\t"))
    }

    @Test func repairsStringWithUnicodeEscape() throws {
        let input = "{'greeting': '\\u4f60\\u597d'}"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired.contains("你好"))
    }

    // MARK: - 特殊值

    @Test func repairsNestedNone() throws {
        let input = "{'a': {'b': None}}"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == #"{"a": {"b": null}}"#)
    }

    @Test func repairsKeywordsInNestedContext() throws {
        let input = "{'truthy': True, 'falsy': False, 'empty': None}"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == #"{"empty": null, "falsy": false, "truthy": true}"#)
    }

    // MARK: - 深层嵌套

    @Test func repairsDeeplyNestedObject() throws {
        let input = "{'l1': {'l2': {'l3': {'l4': {'l5': True}}}}}"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired.hasPrefix("{"))
        #expect(repaired.hasSuffix("}"))
        #expect(repaired.contains("true"))
    }

    // MARK: - 边界输入

    @Test func repairsWithLeadingWhitespace() throws {
        let input = """

        {'x': True}

        """

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired.contains("\"x\""))
    }

    @Test func repairsCompactSingleLineDict() throws {
        let input = "{'a':True,'b':False}"

        let repaired = try JSONRepairer.repair(input)

        #expect(repaired == #"{"a":true,"b":false}"#)
    }

    // MARK: - 错误路径

    @Test func nonContainerInputThrows() {
        #expect(throws: JSONRepairer.RepairError.self) {
            try JSONRepairer.repair("hello world")
        }
    }

    @Test func stringLiteralThrows() {
        #expect(throws: JSONRepairer.RepairError.self) {
            try JSONRepairer.repair("'just a string'")
        }
    }

    @Test func numberLiteralThrows() {
        #expect(throws: JSONRepairer.RepairError.self) {
            try JSONRepairer.repair("42")
        }
    }

    @Test func emptyStringThrows() {
        #expect(throws: JSONRepairer.RepairError.self) {
            try JSONRepairer.repair("")
        }
    }
}
