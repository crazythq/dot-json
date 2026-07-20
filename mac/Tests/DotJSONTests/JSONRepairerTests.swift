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
}
