import AppKit

/// Applies AppKit-wide settings that must run before SwiftUI creates the first window.
final class DotJSONAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must run before any NSWindow exists; otherwise macOS may already enable automatic tabbing.
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
