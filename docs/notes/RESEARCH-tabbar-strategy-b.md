# TabBar Strategy B — Technical Research

**Repo baseline:** `main` @ `5039135` (includes PR #7 merge `027cd7e`, release v1.1.1)  
**Scope:** Research only — no product behavior changes in this PR.  
**Cloud agent run:** [bc-f267b6fe-4767-5a46-bae7-e565d4c4180f](https://cursor.com/agents/bc-f267b6fe-4767-5a46-bae7-e565d4c4180f) (model: Composer 2.5 Fast)

---

## 1. Feasibility

**Verdict: Feasible (with one conditional)**

Custom in-window document tabs are already implemented and always mounted in the main editor scene. Suppressing macOS **window tabbing** (title-bar tabs, View → Show Tab Bar, merge/tile tab groups) is standard AppKit and aligns with existing `WindowConfigurator` hooks. The Diff UI is a **sheet**, not `ContentView`, so it already satisfies “no document TabBar on Diff.”

**Condition:** Set `NSWindow.allowsAutomaticWindowTabbing = false` **before** the first window is created (e.g. `applicationWillFinishLaunching`), **and** set `window.tabbingMode = .disallowed` on each main `NSWindow` when `WindowConfigurationView` binds. Relying only on `.onAppear` + iterating `NSApplication.shared.windows` is fragile and conflicts with current test/style constraints (see risks).

No code changes are required for “single tab still shows bar + +” or Diff isolation unless future work moves Diff to a separate `Window` / `WindowGroup` scene.

---

## 2. Current architecture

### 2.1 Custom document tabs (in-window)

| Concern | Location | Notes |
|--------|----------|--------|
| Tab strip UI | `TabBarView` (`mac/Sources/DotJSON/Views/TabBarView.swift`) | Horizontal scroll, close, rename, context menu, **+** (`workspace.newTab()`), max 20 tabs |
| Tab state | `WorkspaceViewModel` (`mac/Sources/DotJSON/ViewModel/WorkspaceViewModel.swift`) | `tabs: [EditorViewModel]`, `activeTabIndex`, `newTab()`, `closeTab(at:)`, `requestCloseTab`, open/replace rules |
| Layout | `ContentView` (`mac/Sources/DotJSON/Views/ContentView.swift`) | `VStack`: **`TabBarView()` always first**, then editor split or empty state |
| Per-tab editor | `EditorViewModel` + `TextEditorView` | One observable model per tab |

**Visibility today:** `TabBarView()` is **unconditional** in `ContentView` (not gated on `tabs.count`). With one tab, the bar and **+** still render. With zero tabs (`closeAllTabs()`), the bar remains (only **+** / empty strip) above the empty-state panel — matches v1.1.1 structure.

**Shared workspace:** `DotJSONApp` holds `@State private var workspace = WorkspaceViewModel()`; commands and some views use `WorkspaceViewModel.shared` (set in `init()`). A second `WindowGroup` window would show the **same** workspace, not an independent document set — another reason to disable system multi-window tabbing paths.

### 2.2 How documents open

- **File → New / Open**, **⌘N / ⌘O:** `DotJSONCommands` → `workspace.newTab()` / `openFile()` → `openDocuments(_:)` (`WorkspaceViewModel`).
- **Open Recent:** same `openDocuments`.
- **Drop / `.onOpenURL`:** `ContentView` → `openDocuments`.
- **Session restore:** `restoreSession()` in `WorkspaceViewModel.init()`; always ensures at least one tab via `newTab()` when nothing restorable.
- **Replace lone clean untitled tab:** `canReplaceUniqueCleanUntitledTab()` when opening a file (`openDocument(from:)`).

### 2.3 App scene & window wiring

| Item | Location | Current value |
|------|----------|----------------|
| Scene | `DotJSONApp.body` | Single `WindowGroup` + `.windowStyle(.titleBar)` + `.defaultSize(900×760)` |
| Window AppKit hook | `WindowConfigurator` / `WindowConfigurationView` in `DotJSONApp.swift` | Dark appearance, opaque title bar, background `#1e1e1e` — **no `tabbingMode`** |
| Commands | `DotJSONCommands` | `CommandGroup(replacing: .newItem)` — custom **New**, **Open…**, **Close Tab (⌘W)**; `CommandGroup(replacing: .saveItem)` — Save / Save As / Open Recent |
| Info.plist | `mac/Info.plist` | Document type JSON, LSMinimumSystemVersion 14.0 — **no** `NSAllowsAutomaticWindowTabbing` |
| System tabbing | — | **Not configured** → macOS defaults for `WindowGroup` (automatic window tabbing + View menu items) |

**Not present:** `DocumentGroup`, `@NSApplicationDelegateAdaptor`, `tabbingMode`, `NSAllowsAutomaticWindowTabbing`, `CommandGroup` targeting View / tab bar, drag-reorder for custom tabs.

### 2.4 Diff (must stay without document TabBar)

- Presented from `ContentView` as `.sheet(isPresented:)` wrapping `DiffView` (`workspace.isDiffPresented`, `workspace.diffViewModel`).
- `DiffView` (`mac/Sources/DotJSON/Views/DiffView.swift`) is its own `VStack` (header + diff panes) — **no** `TabBarView`.
- File-side changes can still open/update main-window tabs via `WorkspaceViewModel.openFileOnDiffSide` / `openDocument` while the sheet is up; the sheet itself never hosts the custom tab strip.

### 2.5 ⌘W / New / Open / + / context menu (v1.1.1 behavior to preserve)

| Action | Entry | Behavior (summary) |
|--------|--------|---------------------|
| ⌘W | `DotJSONCommands` → `closeActiveTab()` | Ignores duplicate ⌘W while a sheet is attached; unsaved valid JSON → confirm then `closeTab` |
| New | Menu + (implicitly not system New Window) | `newTab()` |
| Open | Panel, multi-select | `openDocuments` + tab limit 20 |
| + | `TabBarView` | `newTab()`, disabled at max tabs |
| Context menu | `TabBarItemView` | Close / others / all, rename, duplicate, compare — strings from `en.lproj/Localizable.strings` (`tab.context.*`) |

Strategy B should **not** move these to system window tabs; only disable AppKit tabbing chrome/menus.

---

## 3. Recommended approach (future implementation PR)

### 3.1 Suppress NSWindow tabbing (multi-document path)

**Primary (app-wide):**

```swift
// AppDelegate.applicationWillFinishLaunching (recommended timing)
NSWindow.allowsAutomaticWindowTabbing = false
```

Wire via `@NSApplicationDelegateAdaptor` on `DotJSONApp` (new small `AppDelegate` type in `mac/Sources/DotJSON/App/`).

**Defense in depth:**

1. **Info.plist:** `<key>NSAllowsAutomaticWindowTabbing</key><false/>` — documents intent; aligns with App Store / system expectations for non-tabbed apps.
2. **Per-window:** In `WindowConfigurationView.configureWindow(_:)` (same file as today), add:
   ```swift
   window.tabbingMode = .disallowed
   ```
   Matches existing “configure once per bound window” pattern; satisfies `DotJSONAppTests` (no resize observer, no `for window in NSApplication.shared.windows` loops).

**Optional hardening (product decision):**

- Confirm **File → New Window** is absent: `DotJSONCommands` already **replaces** `.newItem` (not merely augments), which removes the default **New Window** entry that ships with `WindowGroup`. No extra work unless a regression reintroduces it.
- If users can still spawn extra windows (e.g. reopen app, external events), consider a dedicated `Window` scene or document id policy later — **out of scope** for Strategy B unless QA finds duplicate main windows.

**Do not use** as the only fix: `.onAppear { NSApplication.shared.windows.map { … } }` — races with window creation and violates the project’s stated aversion to broad window iteration in app setup tests.

### 3.2 View → Show Tab Bar

With `allowsAutomaticWindowTabbing == false`, macOS typically **omits** tab-bar-related View menu items (Show Tab Bar, Show All Tabs) for windows that disallow tabbing. This is the preferred approach vs. manually deleting menu items.

**Fallback if an OS version still shows the item:**

- Inspect main menu in delegate (`applicationDidFinishLaunching`) and remove/disable the View submenu action whose title is `"Show Tab Bar"` (fragile across locales — **English-only product** reduces risk).
- Avoid `CommandGroup(replacing: …)` unless a documented `CommandGroupPlacement` maps to that item (no first-class SwiftUI placement for Show Tab Bar today).

**Recommendation:** Ship global + per-window tabbing off; add menu surgery only if manual QA on macOS 14+ still sees the item.

### 3.3 Keep custom TabBar always visible (including single tab)

**No structural change needed:** keep `TabBarView()` as the first child of `ContentView`’s `VStack` with **no** `if workspace.tabs.count > 1` guard.

**Tests to add in implementation PR:**

- Source or snapshot test asserting `ContentView` always contains `TabBarView()` without tab-count conditionals.
- UI test (optional): one tab → tab strip height ~32pt and **+** visible.

**Empty tabs:** After `closeAllTabs()`, bar + empty state is current behavior; confirm with product whether ⌘W on last tab should match v1.1.1 (today: last tab closes → empty tabs array).

---

## 4. Trade-offs, risks, rollback

| Risk | Mitigation |
|------|------------|
| Show Tab Bar still visible on some macOS versions | QA matrix 14.x / 15.x / 26.x; plist + delegate + `tabbingMode` triple layer |
| Second main window shares one `WorkspaceViewModel` | Disable window tabbing; keep `.newItem` replaced; document limitation |
| `DotJSONAppTests` regression (“no global window iteration”) | Only extend `configureWindow` on the bound window; set global flag in delegate |
| Future **Diff as separate window** | That scene must not embed `ContentView` / `TabBarView`; use `DiffView` only or `.commandsRemoved()` on auxiliary scenes |
| Drag-reorder tabs (out of scope) | No conflict with tabbing suppression |

**Rollback plan:** Revert AppDelegate adaptor, remove `tabbingMode` line and plist key, remove any new tests — behavior returns to current macOS default window tabbing. Custom tab UI unchanged.

---

## 5. Effort estimate (clean implementation PR)

| Work | Estimate |
|------|----------|
| AppDelegate + `allowsAutomaticWindowTabbing` | 2–3 h |
| `configureWindow` + Info.plist | 1 h |
| Unit/source tests (`DotJSONAppTests`, optional menu smoke) | 2–4 h |
| Manual QA checklist (below) | 2–3 h |

**Total: ~1–1.5 person-days** (about **3–5 story points**), excluding drag-reorder tabs.

---

## 6. Suggested verification checklist (hand QA)

**System tabbing off**

- [ ] Fresh launch: View menu has **no** “Show Tab Bar” / “Show All Tabs” (English UI).
- [ ] Drag another app window onto title bar: DotJSON does **not** enter native tabbed window group.
- [ ] Window menu: no unexpected “Merge All Windows” / tab-group actions for main window.

**Custom tab bar (main window)**

- [ ] One open document: custom tab strip visible; **+** enabled (until 20 tabs).
- [ ] Multiple tabs: switch, close, context menu (Close / Others / All, Rename, Duplicate, Compare) unchanged from v1.1.1.
- [ ] ⌘W: close tab, confirm dialog for dirty valid JSON, no duplicate dialogs when sheet open.
- [ ] File → New / Open… / Open Recent; toolbar open if any; drop on editor — tab rules and 20-tab alert unchanged.
- [ ] Close all tabs: empty state + tab strip behavior matches v1.1.1 expectation.

**Diff**

- [ ] File Compare or tab context Compare: sheet opens **without** document `TabBarView`.
- [ ] Drop file on diff pane still opens/formats tab in **main** window behind sheet; sheet still has no tab strip.

**Regression**

- [ ] Dark title bar / window background unchanged (`WindowConfigurator`).
- [ ] Session restore and lone untitled replace-on-open still work.

---

## 7. References (symbols & files)

- `NSWindow.allowsAutomaticWindowTabbing` — AppKit class property; set early to false.
- `NSWindow.tabbingMode` / `.disallowed` — per-window opt-out.
- Info.plist `NSAllowsAutomaticWindowTabbing` — Boolean false (bundle-level).
- App: `DotJSONApp`, `WindowConfigurationView.configureWindow(_:)`.
- Tabs: `TabBarView`, `WorkspaceViewModel`, `ContentView`.
- Commands: `DotJSONCommands`.
- Diff: `ContentView` sheet, `DiffView`.

**Out of scope (explicit):** custom tab drag-reorder; changing Diff presentation from sheet to window (would need separate TabBar exclusion design).
