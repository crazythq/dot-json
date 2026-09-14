# DotJSON 1.0.0

First public release of the native macOS JSON viewer and editor.

## macOS app

- **Dual-pane layout** — text editor and collapsible tree view stay in sync.
- **Format & minify** — indent control (2 / 4 / tab), validation with error overlay.
- **Finder integration** — open `.json` as the default editor; recent files.
- **Search** — independent find in the editor (⌘F) and tree search with debounce,
  expand-on-match, and highlight.
- **Tree context menu** — copy key, value, full JSONPath, and related actions; **⌘C**
  on a selected node copies its value.
- **Python ↔ JSON** — bidirectional conversion between standard JSON and Python
  repr-style literals (toolbar); paste auto-repairs Python-style snippets where possible.
- **Multi-tab** — several documents in one window; duplicate tab from tree/context
  menu (text + parsed tree), **double-click or context menu to rename**, hover tooltips
  for paths, numbered untitled tabs, **⌘W** close confirmation when dirty.
- **Paste & focus** — paste inserts at the cursor in non-empty docs (no whole-tab
  replace); input routes to the active tab; window focuses the editor on launch.
- **Session persistence** — restores open tabs and recents across launches.
- **Dark UI** — stable dark window appearance.

## `dotjson` CLI

Shared `DotJSONCore` with the app. Pipe-friendly commands:

- `format` / `minify` — optional `--write` or `--output`
- `validate` — human, `--quiet`, or `--json` output
- `repair` — conservative fixes for AI/Python-style JSON (fences, quotes, literals,
  trailing commas); refuses ambiguous input

Structured stderr via `--json-errors`; stable exit codes for scripts and agents.

## Distribution note

Release builds from this repo are **ad-hoc signed** (`codesign -`), **not notarized**.
macOS Gatekeeper may block the app on first launch. Use **right-click → Open** (or
System Settings → Privacy & Security → Open Anyway) once, then launch normally.

## Requirements

- macOS 14.0 or later
