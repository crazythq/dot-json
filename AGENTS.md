# AGENTS.md

## Cursor Cloud specific instructions

### Platform reality: this is a macOS-only codebase

DotJSON is a native **macOS 14+** product. The Swift package in `mac/`
(`mac/Package.swift`, `platforms: [.macOS(.v14)]`) has three parts, and none of
them build, test, or run on the Linux VM that Cursor Cloud Agents use:

- **GUI** (`Sources/DotJSON/App`, `Views`, `ViewModel`): SwiftUI + AppKit. These
  frameworks do not exist on Linux (`no such module 'SwiftUI'` / `'AppKit'`).
- **CLI entry** (`Sources/DotJSON/CLI/CLIEntry.swift`, and the orphaned
  `Sources/DotJSONCLI/`): uses `import Darwin`, which is macOS-only.
- **Shared core** (`Sources/DotJSONCore`): pure Foundation *except* that
  `JSONParser.swift` calls `CFGetTypeID`/`CFBooleanGetTypeID`. On macOS these
  come implicitly via `import Foundation`; on Linux they require an explicit
  `import CoreFoundation`, which is not present. So even the "portable" core
  fails to compile on Linux with `cannot find 'CFGetTypeID' in scope`.

Consequence for cloud agents: you can install the Swift toolchain (see below)
and drive SwiftPM, but `swift build`, `swift test`, and running the app all fail
on Linux. **Do the actual build/test/run on macOS with Xcode / the Swift
toolchain.** Do not "fix" the Linux compile errors as part of environment setup
unless a task explicitly asks for cross-platform support.

### Toolchain on the VM

The open-source **Swift 6.1.3** toolchain is installed at `/usr/share/swift`,
with `swift`/`swiftc` symlinked into `/usr/local/bin` (already on `PATH`). It
matches `swift-tools-version: 6.0` in the manifest. `swift package resolve`
succeeds (the project has zero third-party dependencies).

### Build / test / run (macOS)

All standard commands are documented in `README.md` and `mac/README.md`; run
them from `mac/`:

- `swift test` — full unit-test suite.
- `swift build --product DotJSON` — build the app + CLI executable.
- `./build-app.sh` — assemble and ad-hoc-sign `DotJSON.app`.
- CLI is invoked through the app binary in `--cli` mode (e.g.
  `DotJSON --cli format data.json`). Note: `README.md` mentions
  `swift build --product dotjson`, but `mac/Package.swift` does not declare a
  `dotjson` product/target (the `Sources/DotJSONCLI/` folder is not wired into
  any target), so that command does not work as written.
