# DotJSON 1.1.5

## macOS app

- **Toolbar** — removed the main-window indent picker. All eight actions (Format, Minify, Convert, Clear, Paste, Copy, Import, Export), including Convert and Export menus, use the same wide layout: **icon centered above the label** (not side-by-side). On narrow windows, every action collapses to icon-only first; if space is still tight, items move into the system toolbar overflow menu (icons preserved).
- **Indent** — the current tab’s indent cannot be changed from the toolbar for now. **Settings → Default Indent** still applies to newly created documents; existing tabs keep their stored indent.
