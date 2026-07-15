# DotJSON

> Open any JSON file. View it as a tree. Edit it. Save it. That's it.

A native macOS JSON viewer and editor — format, browse, and edit JSON with
a clean tree view, right from Finder. Free, open-source, no bloat.

## Structure

```
dot-json/
├── mac/              # macOS app (SwiftUI + AppKit)
│   ├── DotJSON/      # App source (Model / Views / App / Resources)
│   └── DotJSONTests/ # Unit tests
├── utools/           # uTools plugin (planned)
├── raycast/          # Raycast extension (planned)
└── docs/             # Product specs
```

No shared core library — each platform target is self-contained.
`utools` and `raycast` are JS/TS ports sharing the same design contract, not the same codebase.

## Features

| Phase | Target | Key Features |
|-------|--------|-------------|
| **MVP** | v0.1.0 | Dual-pane layout, tree view, format/minify, indent control, paste/clear/copy, save/export, Finder integration, validation, dark UI |
| **V1** | v0.2.0 | Multi-tab, copy JSON Path, search, history |
| **V2** | v0.3.0 | JSONL navigation, JSON Diff |

### Never planned

Syntax highlighting, themes toggle, Quick Look, jq/JSONPath.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **macOS** | SwiftUI + AppKit (NSOutlineView + NSTextView), macOS 14+, zero deps |
| **uTools (planned)** | HTML/CSS/JS, uTools Plugin API |
| **Raycast (planned)** | TypeScript + React, Raycast Extensions API |
| **Packaging** | Xcode Archive → DMG → Notarization → GitHub Release, Homebrew Cask (V1) |

## Development

```bash
# macOS app (requires Xcode)
cd mac
open DotJSON.xcodeproj   # TBD — Xcode project not yet created
```

## License

MIT © TK
