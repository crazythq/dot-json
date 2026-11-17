import Testing
@testable import DotJSON

struct SemanticVersionTests {
    @Test func parseStripsVPrefix() {
        #expect(SemanticVersion.parse("v1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion.parse("1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test func parseRejectsInvalid() {
        #expect(SemanticVersion.parse("1.2") == nil)
        #expect(SemanticVersion.parse("1.2.3-beta") == nil)
        #expect(SemanticVersion.parse("abc") == nil)
        #expect(SemanticVersion.parse("") == nil)
    }

    @Test func compareOrdering() {
        let v115 = SemanticVersion.parse("1.1.5")!
        let v120 = SemanticVersion.parse("1.2.0")!
        let v116 = SemanticVersion.parse("1.1.6")!
        #expect(SemanticVersion.compare(v115, v115) == .orderedSame)
        #expect(SemanticVersion.compare(v120, v115) == .orderedDescending)
        #expect(SemanticVersion.compare(v115, v116) == .orderedAscending)
    }
}