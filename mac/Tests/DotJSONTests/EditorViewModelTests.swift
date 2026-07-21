import DotJSONCore
import Testing
import Foundation
@testable import DotJSON

@MainActor
struct EditorViewModelTests {

    // MARK: - Basic State
    @Test func initialStateIsEmpty() {
        let vm = EditorViewModel()
        #expect(vm.rawText.isEmpty)
        #expect(vm.treeRoot == nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.indent == .fourSpaces)
    }
    @Test func parseValidJSON() {
        let vm = EditorViewModel()
        vm.rawText = #"{"name":"Alice","age":30}"#
        #expect(vm.treeRoot != nil)
        if let root = vm.treeRoot, case .object(let pairs) = root {
            #expect(pairs.count == 2)
        } else { Issue.record("Expected object") }
    }
    @Test func parseInvalidJSON() {
        let vm = EditorViewModel()
        vm.rawText = "{bad"
        #expect(vm.treeRoot == nil)
        #expect(vm.errorMessage != nil)
    }
    @Test func formatJSON() {
        let vm = EditorViewModel()
        vm.rawText = #"{"b":2,"a":1}"#
        vm.format()
        #expect(vm.rawText.contains("\n"))
    }

    @Test func formatRepairsPythonStyleObject() {
        let vm = EditorViewModel()
        vm.rawText = """
        {
          'visible123': True
        }
        """

        vm.format()

        #expect(vm.rawText == """
        {
            "visible123": true
        }
        """)
        #expect(vm.errorMessage == nil)
    }

    @Test func formatRejectsUnquotedKeysInsteadOfGuessing() {
        let vm = EditorViewModel()
        let input = """
        {
          visible123: True,
          "alreadyJson": true
        }
        """
        vm.rawText = input

        vm.format()

        #expect(vm.rawText == input)
        #expect(vm.errorMessage != nil)
    }
    @Test func minifyJSON() {
        let vm = EditorViewModel()
        vm.rawText = "{\n  \"a\": 1\n}"
        vm.minify()
        #expect(!vm.rawText.contains("\n"))
    }

    @Test func minifyRepairsPythonStyleObject() {
        let vm = EditorViewModel()
        vm.rawText = "{'visible123': True}"

        vm.minify()

        #expect(vm.rawText == #"{"visible123":true}"#)
        #expect(vm.errorMessage == nil)
    }
    @Test func clearResetsState() {
        let vm = EditorViewModel()
        vm.rawText = #"{"x":1}"#
        vm.clear()
        #expect(vm.rawText.isEmpty)
        #expect(vm.treeRoot == nil)
    }
    @Test func changeIndentOption() {
        let vm = EditorViewModel()
        vm.indent = .twoSpaces
        vm.rawText = #"{"a":1}"#
        vm.format()
        #expect(vm.rawText.contains("  "))
    }

    @Test func changingIndentReformatsValidDocumentImmediately() {
        let vm = EditorViewModel()
        vm.rawText = #"{"outer":{"value":1}}"#
        vm.format()

        vm.indent = .twoSpaces

        let lines = vm.rawText.components(separatedBy: .newlines)
        #expect(lines[1].hasPrefix("  \"outer\""))
        #expect(lines[2].hasPrefix("    \"value\""))
    }

    // MARK: - File
    @Test func loadFromFileURL() throws {
        let vm = EditorViewModel()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t_load.json")
        try #"{"h":"w"}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.load(from: url)
        #expect(vm.rawText.contains("h"))
        #expect(vm.fileURL == url)
    }

    @Test func loadDocumentAcceptsJSONExtensionCaseInsensitively() throws {
        let vm = EditorViewModel()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t_load_uppercase.JSON")
        try #"{"ok":true}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        try vm.loadDocument(from: url)

        #expect(vm.fileURL == url)
        #expect(vm.treeRoot != nil)
    }

    @Test func loadDocumentRejectsUnsupportedFileWithoutReplacingCurrentDocument() throws {
        let vm = EditorViewModel()
        vm.rawText = #"{"original":true}"#
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("unsupported.txt")
        try #"{"replacement":true}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: EditorViewModel.DocumentError.self) {
            try vm.loadDocument(from: url)
        }
        #expect(vm.rawText == #"{"original":true}"#)
        #expect(vm.fileURL == nil)
    }
    @Test func saveToFileURL() throws {
        let vm = EditorViewModel()
        vm.rawText = #"{"s":true}"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t_save.json")
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.save(to: url)
        #expect(try String(contentsOf: url).contains("s"))
    }

    @Test func exportFormattedWritesSelectedIndentWithoutChangingDocumentURL() throws {
        let vm = EditorViewModel()
        vm.indent = .twoSpaces
        vm.rawText = #"{"b":2,"a":1}"#
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t_export_formatted.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try vm.export(to: url, format: .formatted)

        let output = try String(contentsOf: url, encoding: .utf8)
        #expect(output.contains("\n  \"a\""))
        #expect(vm.fileURL == nil)
    }

    @Test func exportMinifiedWritesSingleLineWithoutChangingEditorText() throws {
        let vm = EditorViewModel()
        vm.rawText = "{\n    \"a\": 1\n}"
        let originalText = vm.rawText
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("t_export_minified.json")
        defer { try? FileManager.default.removeItem(at: url) }

        try vm.export(to: url, format: .minified)

        let output = try String(contentsOf: url, encoding: .utf8)
        #expect(!output.contains("\n"))
        #expect(vm.rawText == originalText)
    }
    @Test func isModifiedAfterTextChange() throws {
        let vm = EditorViewModel()
        vm.rawText = "{}"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t_mod.json")
        defer { try? FileManager.default.removeItem(at: url) }
        try vm.save(to: url)
        #expect(vm.isModified == false)
        vm.rawText = #"{"x":1}"#
        #expect(vm.isModified == true)
    }

    // MARK: - Error
    @Test func errorLineNumberForBadJSON() {
        let vm = EditorViewModel()
        vm.rawText = "{\n  \"a\": bad\n"
        #expect(vm.errorLineNumber > 0)
    }

    @Test func errorLineNumberPointsToInvalidSecondLine() {
        let vm = EditorViewModel()

        vm.rawText = "{\n  \"a\": bad\n}"

        #expect(vm.errorLineNumber == 2)
    }

    @Test func errorLineNumberCountsUnicodeCharactersBeforeFailure() {
        let vm = EditorViewModel()

        vm.rawText = "{\n  \"名称\": \"测试\",\n  \"value\": invalid\n}"

        #expect(vm.errorLineNumber == 3)
    }

    @Test func reportedFileErrorIsVisibleWithoutFakeLineNumber() {
        let vm = EditorViewModel()
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.fileReadNoSuchFile.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "测试文件不存在"]
        )

        vm.reportFileError(error)

        #expect(vm.errorMessage == "测试文件不存在")
        #expect(vm.errorLineNumber == 0)
    }
    @Test func documentTitleShowsFilename() {
        let vm = EditorViewModel()
        vm.fileURL = URL(fileURLWithPath: "/test/data.json")
        #expect(vm.documentTitle == "data.json")
    }

    // MARK: - Paste
    @Test func pasteValidJSONAutoFormats() {
        let vm = EditorViewModel()
        vm.pasteAndFormat(#"{"b":2,"a":1}"#)
        #expect(vm.rawText.contains("\n"))
    }
    @Test func pastePythonStyleObjectAutoRepairsAndFormats() {
        let vm = EditorViewModel()

        vm.pasteAndFormat("{'visible123': True, 'missing': None,}")

        #expect(vm.rawText == """
        {
            "missing": null,
            "visible123": true
        }
        """)
        #expect(vm.errorMessage == nil)
    }
    @Test func pasteInvalidJSONPreservesRaw() {
        let vm = EditorViewModel()
        vm.pasteAndFormat("not json")
        #expect(vm.rawText == "not json")
    }
    @Test func pasteEmptyStringDoesNothing() {
        let vm = EditorViewModel()
        vm.rawText = "original"
        vm.pasteAndFormat("")
        #expect(vm.rawText == "original")
    }
    @Test func autoFormatOnPasteEnabledByDefault() {
        #expect(EditorViewModel().autoFormatOnPaste == true)
    }
}
