# Research: Main Window Tab Bar Drag Reorder

**Status:** Research only (no product changes)  
**Base:** `main` @ `369219a` (TabBar Strategy B, PR #10)  
**Scope:** `TabBarView` in the main editor window — not Diff UI, not keyboard reorder, not pin/unpin, not Strategy B / system window tabbing.

---

## 1. Feasibility

**Verdict: Conditional — feasible**

Implementing drag-to-reorder on the existing in-window tab bar is realistic on **macOS 14+** (see `mac/Package.swift` `platforms: [.macOS(.v14)]`) without changing Strategy B (`DotJSONAppDelegate`, `Info.plist` `NSAllowsAutomaticWindowTabbing`, `WindowConfigurator` / `window.tabbingMode = .disallowed`).

**Conditions / spike items before committing to a single UI stack:**

| Condition | Why |
|-----------|-----|
| Validate **horizontal `ScrollView` vs drag** on macOS 14–15 | SwiftUI’s scroll view may consume horizontal mouse drags; reorder may require `scrollDisabled` during drag or an AppKit scroll host. |
| Confirm **click vs drag** does not fire `activateTab` | Today activation is a plain `Button` in `TabBarItemView`; drag must not trigger `workspace.activateTab(at:)`. |
| Keep **bar height 32** and item **height 28** | Lift/preview must not expand layout; use overlay / offset, not larger frames. |

If a short spike shows SwiftUI gesture + `ScrollView` is unreliable, fall back to an **AppKit tab strip** (`NSView` + mouse tracking) while keeping `WorkspaceViewModel` as the single source of tab order (see §3).

---

## 2. Current architecture

### 2.1 View layer

| Symbol | File | Role |
|--------|------|------|
| `TabBarView` | `mac/Sources/DotJSON/Views/TabBarView.swift` | Root bar: `ScrollView(.horizontal)` → `HStack` of tabs + “+” `Button`. Fixed `.frame(height: 32)`, background `#1a1a1a`. |
| `TabBarItemView` | same file (private) | Per-tab UI: title `Button` → `workspace.activateTab(at: index)`, close `Button`, hover, rename `TextField`, `contextMenu`, double-tap rename via `simultaneousGesture(TapGesture(count: 2))`. |
| `ContentView` | `mac/Sources/DotJSON/Views/ContentView.swift` | Embeds `TabBarView()` above editor `HSplitView`; editor binds to `workspace.activeDocument`. |

**Identity in the list:** `ForEach(Array(workspace.tabs.enumerated()), id: \.element.id)` — stable **`EditorViewModel.id`** (`UUID`), but child views still receive **`index: Int`** for actions.

**No drag/reorder today:** Only tap (activate), double-tap (rename), context menu, close, and horizontal scroll when tabs overflow.

### 2.2 ViewModel / tab model

| Symbol | File | Role |
|--------|------|------|
| `WorkspaceViewModel` | `mac/Sources/DotJSON/ViewModel/WorkspaceViewModel.swift` | `@Observable`; `tabs: [EditorViewModel]`, `activeTabIndex: Int` (-1 when empty). |
| `EditorViewModel` | `mac/Sources/DotJSON/ViewModel/EditorViewModel.swift` | `Identifiable`, `let id = UUID()`; document state, `documentTitle`, `fileURL`, etc. |
| `activateTab(at:)` | `WorkspaceViewModel` | Sets `activeTabIndex`, calls `persistSession()`. |
| `closeTab(at:)` | `WorkspaceViewModel` | Removes tab; adjusts `activeTabIndex` when index shifts (does **not** use tab id). |
| `SessionSnapshot` | `WorkspaceViewModel` (private) | Persists `fileURLs: [String]` (**order = tab order**), `activeIndex: Int`, `recentFiles`. Restore rebuilds `tabs` in saved order and clamps `activeTabIndex`. |

**Active tab resolution:** `activeDocument` is `tabs[activeTabIndex]` when in range. There is **no** `activeTabId` property; Diff already keys sides by **`UUID`** (`DiffSideBinding.Source.tab(UUID)`, `ApplyTarget.tab(UUID)` in `mac/Sources/DotJSON/Model/DiffSideBinding.swift`).

### 2.3 Related systems (unchanged by this feature)

- **Strategy B:** `mac/Sources/DotJSON/App/AppDelegate.swift` (`NSWindow.allowsAutomaticWindowTabbing = false`), `DotJSONApp.swift` (`WindowConfigurator`, `tabbingMode = .disallowed`), `mac/Info.plist` — regression covered by `DotJSONAppTests.appDisablesAutomaticWindowTabbingWithoutGlobalWindowIteration`.
- **Diff tab bar:** `DiffView` has its own UI; out of scope.
- **File drag elsewhere:** `FileDropPasteboard`, `TextEditorView` / `DiffSideTextEditor` dragging — unrelated to tab reorder.

### 2.4 Tests today

- `WorkspaceViewModelTests`: tab CRUD, duplicate, close, session-ish behavior; **no** `TabBarView` or reorder tests.
- `ContentViewTests`: minimal import smoke.
- No UI tests for tab bar gestures.

---

## 3. Recommended approach

### 3.1 Model API (required regardless of UI technology)

Add a single reorder entry point on `WorkspaceViewModel`, e.g.:

```swift
/// Reorder tabs; active selection follows the same EditorViewModel instance (tab id), not index.
func moveTab(from sourceIndex: Int, to insertionIndex: Int)
```

**Behavior:**

1. Bounds-check indices; no-op if source == destination or invalid.
2. Capture `activeId = tabs[activeTabIndex].id` when `activeTabIndex` is valid.
3. Remove/move element in `tabs` (standard array move; insertion index convention: “insert before index N”).
4. Set `activeTabIndex = tabs.firstIndex(where: { $0.id == activeId }) ?? …` (fallback only if active tab was removed — should not happen in reorder).
5. Call `persistSession()` so tab order survives relaunch.

**Why not only adjust `activeTabIndex` with index math:** Reordering while the user keeps a **non-dragged** tab active is the common case; id-based lookup matches the product requirement (“active tab tracked by **tab id**”). Index-only math is error-prone when combining with future features.

**Session persistence:** Order is already encoded in `fileURLs` array order; no schema change. Untitled tabs persist as `""` path entries — reorder still meaningful for session restore.

**Diff / open file:** Bindings and `openTab(from:)` use `fileURL` / `tab.id`; reorder does not invalidate them.

### 3.2 UI strategy (recommended: SwiftUI-first with AppKit escape hatch)

#### Option A — SwiftUI gesture orchestration (recommended first)

**State (on `TabBarView` or small helper type):**

- `draggingTabId: UUID?`
- `dragStartOrder: [UUID]` — for cancel / snap-back
- `insertionIndex: Int?` — drop target between tabs (0…count)
- `dragTranslation` / ghost offset — visual lift only
- `hasExceededReorderThreshold: Bool`

**Per `TabBarItemView` (keyed by tab id, not ephemeral index during drag):**

1. **Reorder threshold (~6–10 pt):** Use `DragGesture(minimumDistance: 8)` (or combine with a small movement gate) before setting `draggingTabId` and snapshotting order. Below threshold → treat as click path only.
2. **Do not activate on press/lift:** Replace or supplement the title `Button` with a click handler that runs **only if** `!hasExceededReorderThreshold` at mouse up (or use `onTapGesture` on a non-button label). Avoid `Button` firing after a drag ends.
3. **Visual lift:** `.scaleEffect` / `.shadow` / slight `.offset(y: -2)` on the dragged item; optional reduced opacity on siblings. Do **not** change `activeTabIndex` when drag starts.
4. **Insertion indicator:** 2 px vertical line (e.g. `#007acc` or neutral `#858585`) in the bar overlay, positioned at the leading edge of the tab slot for `insertionIndex` (GeometryReader / preference keys to collect tab frames).
5. **Live reorder preview (optional):** Either mutate `tabs` only on drop, or use a transient “display order” array during drag — **commit on drop** is simpler and avoids fighting `@Observable` updates with gesture state.

**Coexistence with horizontal `ScrollView`:**

- While `draggingTabId != nil`, apply `.scrollDisabled(true)` on the `ScrollView` (available on macOS 13+; deployment is 14).
- **Edge auto-scroll:** When drag location (global or bar-local) is within ~24 pt of the visible scroll clip rect’s left/right edges, nudge scroll offset on a repeating `Timer` / `DisplayLink` (~30 Hz). Implementation options:
  - **Preferred spike:** `ScrollViewReader` + `scrollTo` on tab ids (coarse).
  - **Smoother:** Thin `NSViewRepresentable` wrapper around `NSScrollView` exposing `clipView.bounds` and `scroll(to:)` for pixel-accurate auto-scroll (pattern already used elsewhere: `TextEditorView`, `TreeView`, `NativeTreeSearchField`).

**Cancel when dragging outside the bar:**

- Attach a drag-updating gesture at `TabBarView` level (height 32). If `location.y` ∉ bar bounds (or outside an expanded hit rect), set `insertionIndex = nil` and mark `cancelled`.
- On end: if cancelled or no valid insertion → restore `tabs` order from `dragStartOrder` (map ids back to `EditorViewModel` references); do not call `moveTab`. Animate snap-back.

**“+” button:** Not draggable; insertion index should not move tabs past the plus control unless product wants that — suggest clamping reorder to indices `0..<tabs.count` only.

**Double-tap rename:** Keep `TapGesture(count: 2)` but ensure drag threshold suppresses false double-taps during reorder attempts (only fire rename when not dragging).

#### Option B — AppKit tab strip (`NSViewRepresentable`)

Use if Option A fails QA on scroll/gesture conflict:

- Custom `NSView` lays out tab rects, tracks mouse down/drag/up, draws insertion line, auto-scrolls via `NSScrollView`.
- SwiftUI hosts only chrome (background 32 pt); items mirror current colors/fonts (`11 pt`, active `#252526`, etc.).
- Still call `WorkspaceViewModel.moveTab` on drop; **no** change to Strategy B.

#### Option C — `Transferable` / `NSDragging` between tabs

**Not recommended** for in-window-only reorder:

- Geared toward cross-view/cross-app drops; harder to integrate with existing `Button`/menu hit targets.
- Does not simplify insertion indicator, threshold, or “cancel outside bar” compared to a local drag gesture.
- Risk of conflicting with `FileDropPasteboard` semantics if drag types overlap (mitigate with private UTType — still unnecessary complexity).

### 3.3 Index vs id in `TabBarItemView`

Refactor call sites to pass **`tabId: UUID`** (and look up index when needed via `workspace.tabs.firstIndex(where: { $0.id == tabId })`) for close/rename/diff context menu, so mid-drag index churn does not close the wrong tab.

### 3.4 Persistence and edge cases

| Scenario | Expected behavior |
|----------|-------------------|
| Reorder with tab A active, drag tab B | After drop, `activeTabIndex` still points to A’s id. |
| Reorder while Diff open | Diff bindings use tab UUIDs; labels may stale until Diff refresh — acceptable unless Diff UI shows tab order (verify `DiffView` only shows side labels). |
| Single tab | Drag threshold may never show insertion; no-op reorder. |
| Max tabs (20) | Unaffected. |
| Rename in progress | Disable drag on that item while `isEditingTitle`. |

---

## 4. Trade-offs, risks, rollback

| Topic | Trade-off / risk | Mitigation |
|-------|------------------|------------|
| SwiftUI `ScrollView` | Horizontal scroll competes with drag | `scrollDisabled` during drag; AppKit scroll host if needed |
| `Button` activation | Accidental tab switch after drag | Threshold + suppress click when drag ended |
| `@Observable` + frequent array moves | Flicker if reordering every drag tick | Commit order on drop only; optional lightweight ghost |
| Session restore | Old builds without reorder API | New code only adds `moveTab`; old sessions remain valid |
| Accessibility | No keyboard reorder (explicitly out of scope) | Document gap; no VO reorder announcement unless added later |
| Test coverage | Gestures hard in unit tests | Unit-test `moveTab` thoroughly; manual QA checklist (§6) |

**Rollback:** Feature is isolated to `TabBarView` (+ optional small helper / `WorkspaceViewModel.moveTab`). Removing `moveTab` and reverting tab bar gestures restores prior behavior. No migration for `SessionSnapshot`.

---

## 5. Effort estimate

| Workstream | Estimate |
|------------|----------|
| `WorkspaceViewModel.moveTab` + unit tests (`WorkspaceViewModelTests`) | **0.5–1 day** |
| SwiftUI drag UX (threshold, indicator, cancel, no activate-on-drag) | **1.5–2 days** |
| Scroll auto-scroll + overflow edge cases | **0.5–1 day** |
| Polish (animation, context menu/double-click interaction, regression pass Strategy B) | **0.5–1 day** |
| AppKit fallback (only if spike fails) | **+2–3 days** |

**Total:** **~3–5 person-days** (SwiftUI path); **~6–8** if AppKit strip is required.

Story points (if using Fibonacci): **5** (likely), **8** if AppKit fallback is planned upfront.

---

## 6. Suggested hand QA checklist (future implementation PR)

Use English UI (`Localizable.strings` keys unchanged unless new strings are added).

### Basic reorder

- [ ] With 3+ tabs, drag middle tab left/right; on drop, order matches visual insertion line.
- [ ] After reorder, the **same document** stays active (content/editor focus unchanged when active tab was not the dragged tab).
- [ ] Drag active tab to new position; it remains active after drop.

### Threshold & click

- [ ] Short click without crossing threshold still activates tab (title color `#ffffff` / active background `#252526`).
- [ ] Small jitter click on tab does not reorder.
- [ ] Drag does **not** switch active tab when starting drag on an inactive tab.

### Insertion feedback

- [ ] Insertion line visible while dragging between tabs; hidden when invalid.
- [ ] Bar height stays **32 pt**; no layout jump in `ContentView` editor area.

### Scroll & overflow

- [ ] With many tabs (10–20), drag near left/right edge auto-scrolls.
- [ ] After auto-scroll, drop still applies correct insertion index.

### Cancel

- [ ] Drag vertically out of tab bar (into editor/toolbar) and release → order unchanged, snap-back animation acceptable.
- [ ] Esc or cancel gesture (if implemented) restores original order.

### Existing tab features

- [ ] Double-click rename still works when not dragging.
- [ ] Context menu: Close Current Tab, Close Other Tabs, Close All Tabs, Rename, Duplicate, Compare With This Tab — still correct tab targets after reorder.
- [ ] Close (`xmark`) on correct tab after reorder.
- [ ] “+” / **New Tab** still works; tab limit alert `"Tab limit reached (20)"` unchanged.

### Integration

- [ ] Quit and relaunch: tab order and active tab restored via `SessionSnapshot`.
- [ ] Open JSON from Finder: existing tab focus by `fileURL` unchanged.
- [ ] Diff sheet open: compare/apply still targets correct tabs by id.
- [ ] macOS window tabbing still suppressed (no merged window tabs); `DotJSONAppTests` still pass.

### Regression

- [ ] `swift test` in `mac/` all green.
- [ ] File drop on editor still opens documents; no conflation with tab drag.

---

## 7. Files likely touched in implementation (reference)

| File | Change |
|------|--------|
| `mac/Sources/DotJSON/Views/TabBarView.swift` | Gestures, insertion UI, drag state |
| `mac/Sources/DotJSON/ViewModel/WorkspaceViewModel.swift` | `moveTab(from:to:)` |
| `mac/Tests/DotJSONTests/WorkspaceViewModelTests.swift` | Reorder + active-id tests |
| Optional new file | `TabBarScrollHost.swift` or similar if AppKit scroll helper is extracted |

**Explicitly out of scope:** `AppDelegate.swift`, `DotJSONApp.swift`, `Info.plist`, `DiffView.swift`, `DotJSONCommands.swift` (unless adding a future menu item — not in current goal).

---

## 8. References (symbols)

- Tab bar UI: `TabBarView`, `TabBarItemView` — `mac/Sources/DotJSON/Views/TabBarView.swift`
- Tab state: `WorkspaceViewModel.tabs`, `activeTabIndex`, `activateTab(at:)`, `persistSession()`, `SessionSnapshot` — `mac/Sources/DotJSON/ViewModel/WorkspaceViewModel.swift`
- Tab identity: `EditorViewModel.id` — `mac/Sources/DotJSON/ViewModel/EditorViewModel.swift`
- Composition: `ContentView` — `mac/Sources/DotJSON/Views/ContentView.swift`
- Strategy B: `DotJSONAppDelegate`, `WindowConfigurator`, `DotJSONAppTests` — `mac/Sources/DotJSON/App/`
