# DotJSON

> Open any JSON file. View it as a tree. Edit it. Save it. That's it.

A native macOS JSON viewer and editor — format, browse, and edit JSON with
a clean tree view, right from Finder. Free, open-source, no bloat.

## Structure

```
dot-json/
├── mac/              # macOS app + dotjson CLI + shared Swift core
│   ├── DotJSON/      # App source (Model / Views / App / Resources)
│   └── DotJSONTests/ # Unit tests
├── utools/           # uTools plugin (planned)
├── raycast/          # Raycast extension (planned)
└── docs/             # Product specs
```

The macOS app and `dotjson` CLI share `DotJSONCore`, so parsing and formatting
behave identically. `utools` and `raycast` remain self-contained JS/TS ports
sharing the same design contract, not the same codebase.

## Features

| Phase | Target | Key Features |
|-------|--------|-------------|
| **MVP** | v0.1.0 | Dual-pane layout, tree view, format/minify, indent control, paste/clear/copy, save/export, Finder integration, validation, dark UI |
| **V1** | v0.2.0 | Multi-tab, copy JSON Path, search, history |
| **V2** | v0.3.0 | JSONL navigation, JSON Diff |

The bundled `dotjson` CLI provides `format`, `minify`, `validate`, and
conservative `repair` commands. It is pipe-friendly for scripts and AI Agents,
with structured errors and stable exit codes.

### Never planned

Syntax highlighting, themes toggle, Quick Look, jq/JSONPath.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **macOS** | SwiftUI + AppKit app, Foundation CLI, shared Swift core, macOS 14+, zero deps |
| **uTools (planned)** | HTML/CSS/JS, uTools Plugin API |
| **Raycast (planned)** | TypeScript + React, Raycast Extensions API |
| **Packaging** | Xcode Archive → DMG → Notarization → GitHub Release, Homebrew Cask (V1) |

## Development

```bash
cd mac
swift test
swift build --product DotJSON
swift build --product dotjson
```

## CLI

Build with SwiftPM, then find the binary in SwiftPM's active output directory:

```bash
cd mac
swift build --product dotjson
BIN_DIR="$(swift build --show-bin-path)"
"$BIN_DIR/dotjson" --help
```

Use files or Unix pipelines:

```bash
dotjson format data.json --indent 2
cat model-output.txt | dotjson repair | dotjson format
dotjson validate response.json --quiet
dotjson repair response.json --write
dotjson minify data.json --output data.min.json
```

`repair` fixes deterministic AI/Python output issues such as Markdown fences,
single-quoted Python dictionaries, `True`/`False`/`None`, and trailing commas.
It preserves the original layout and refuses ambiguous input.

For Agent workflows, add `--json-errors` for structured stderr. Exit codes are
stable: `0` success, `2` usage, `3` input I/O, `4` invalid or unrepairable JSON,
and `5` output I/O.

## License

MIT © TK
