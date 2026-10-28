import Foundation
import Testing
@testable import DotJSON

struct DefaultApplicationWorkspaceErrorTests {
    @Test func recognizesCocoaUserCancelledNSError() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        #expect(DefaultApplicationWorkspaceError.isUserCancellation(error))
        #expect(DefaultApplicationWorkspaceError.from(error) == .userCancelled)
    }

    @Test func mapsOtherErrorsToSetFailed() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        #expect(!DefaultApplicationWorkspaceError.isUserCancellation(error))
        #expect(DefaultApplicationWorkspaceError.from(error) == .setFailed(underlyingDescription: "boom"))
    }
}
