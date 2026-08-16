import Testing
import Foundation
@testable import DotJSONCore

struct PythonLiteralSerializerTests {

    /// None/True/False 与单引号字符串是 Python repr 的核心差异。
    @Test func convertsNullBoolAndString() throws {
        let node = try JSONParser.parse(#"{"a": null, "b": true, "c": false, "d": "x"}"#)

        let python = PythonLiteralSerializer.serialize(node, indent: "    ")

        #expect(python.contains("None"))
        #expect(python.contains("True"))
        #expect(python.contains("False"))
        #expect(python.contains("'x'"))
    }

    /// 嵌套对象与数组按缩进输出，结构保持完整。
    @Test func serializesNestedContainersWithIndent() throws {
        let node = try JSONParser.parse(#"{"a": {"b": [1, true, null]}}"#)

        let python = PythonLiteralSerializer.serialize(node, indent: "    ")

        #expect(python == """
        {
            'a': {
                'b': [
                    1,
                    True,
                    None
                ]
            }
        }
        """)
    }

    /// 单引号、反斜杠与控制字符按 Python 字面量规则转义。
    @Test func escapesPythonLiteralCharacters() throws {
        let node = try JSONParser.parse(#"{"s": "a'b\\c\nd"}"#)

        let python = PythonLiteralSerializer.serialize(node, indent: "    ")

        #expect(python.contains(#"'a\'b\\c\nd'"#))
    }

    /// 空容器输出紧凑形式，与 Python repr 一致。
    @Test func emitsCompactEmptyContainers() throws {
        let node = try JSONParser.parse(#"{"o": {}, "a": []}"#)

        let python = PythonLiteralSerializer.serialize(node, indent: "    ")

        #expect(python.contains("'o': {}"))
        #expect(python.contains("'a': []"))
    }
}
