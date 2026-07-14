# DotJSON

> Open any JSON file on your Mac. View it as a tree. Edit it. Save it. That's it.

A native macOS JSON viewer and editor — format, browse, and edit JSON with a clean tree view, right from Finder. Free, open-source, no bloat.

## Features

- **Dual-pane layout** — text editor + collapsible tree structure
- **Format & Minify** — beautify or compress JSON in one click
- **Customizable indentation** — 2 spaces, 4 spaces (default), or tabs
- **Paste & auto-format** — paste raw JSON, it formats instantly
- **Syntax validation** — errors highlighted with line numbers
- **Save / Save As / Export** — standard macOS document behavior
- **Finder integration** — double-click `.json` files, drag & drop to open
- **Default dark UI** — clean dark theme, no distractions
- **100% offline** — your JSON never leaves your machine

## Install

Download the latest `.dmg` from [Releases](https://github.com/crazythq/dot-json/releases).

> macOS may show a security warning on first launch. Right-click the app → Open to bypass.

## Roadmap

| Phase | Timeline | Features |
|-------|----------|----------|
| **MVP** | v0.1.0 | 12 core features: dual pane, tree view, format/compress, indent control, paste, copy, clear, save/export, Finder integration, validation |
| **V1** | v0.2.0 | Multi-tab, copy JSON Path, search, history |
| **V2** | v0.3.0 | JSONL support (prev/next navigation), JSON Diff |

### Never planned

- Syntax highlighting / themes
- Dark mode toggle (hardcoded dark)
- Quick Look
- jq / JSONPath
- Raycast extension

## Tech Stack

- **SwiftUI** + **AppKit** (NSOutlineView + NSTextView)
- **JSONSerialization** (no third-party dependencies)
- macOS 14 Sonoma+
- Universal Binary (Apple Silicon + Intel)

## Development

```bash
git clone https://github.com/crazythq/dot-json.git
cd dot-json
open DotJSON.xcodeproj
```

## License

MIT © TK
