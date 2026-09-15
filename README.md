# Fling

A lightweight macOS window manager that lives in the menu bar.

- **Keyboard shortcuts** for halves, corners, thirds, fourths, sixths, fill, maximize, center, nudge, size, move, displays, Spaces and window controls. Repeating a half cycles ½ → ⅔ → ⅓; nudge and size repeat while held. **Win Arrow Keys** step between halves and corners like Windows.
- **Drag to snap**: screen edges and corners (each configurable), a **Snap Panel** of tiles, and custom **snap targets**, with footprint previews and haptics. Drag a snapped window away to restore its size; drag a shared edge to resize neighbors.
- **Window Throw**: hold ⌃⌘, a mouse button, or rest 3–5 fingers on the trackpad and lift all but one; move toward one of 16 configurable positions and release.
- **Quick Throw**, and **move/resize by holding modifiers**.
- **Custom positions** (fractions or points, repeat cycles, per-display) and **Layouts** that arrange all your apps: by shortcut, URL, display connect/disconnect, wake, or as windows open.
- **Multiple windows**: 2×2 and 2×3 tiles, cascade, app halves.
- **Stash** windows at the screen edge (with color tabs, delay, ⌘-only); Stash All, Toggle and Cycle.
- **Pin Mode** keeps one app in a strip; everything else fills the rest.
- Gaps, double-click title bar to maximize, Dock-aware resizing, windows return when a display reconnects, context menu at the cursor, hideable menu bar icon, launch at login.
- **Configuration** export/import as JSON and iCloud Drive sync.
- **URL scheme**: `open -g "fling://execute-action?name=left-half"`, `fling://execute-custom?name=…`, `fling://execute-layout?name=…`

Requires macOS 14+.

## Build & run

```sh
make run    # builds build/Fling.app and opens it
make test   # unit tests (geometry, models, config)
make smoke  # moves a throwaway test window through real actions and prints PASS/FAIL
```

On first launch macOS asks for **Accessibility** access (System Settings → Privacy & Security → Accessibility). Fling needs it to move other apps' windows.

> Run `make cert` once first. It creates a self-signed "Fling Dev" signing certificate in your login keychain, so rebuilds keep the Accessibility grant. Without it, builds are ad-hoc signed and macOS forgets the grant after every rebuild.

If you also run Rectangle, quit it first. It uses the same default shortcuts.

## Shortcuts

| Action | Shortcut |
|---|---|
| Left / Right / Top / Bottom Half | ⌃⌥ ← → ↑ ↓ |
| Top Left / Top Right / Bottom Left / Bottom Right | ⌃⌥ U I J K |
| First / Center / Last Third | ⌃⌥ D F G |
| First / Last Two Thirds | ⌃⌥ E T |
| Maximize | ⌃⌥ ↩ |
| Maximize Height | ⌃⌥⇧ ↑ |
| Almost Maximize | menu only |
| Center | ⌃⌥ C |
| Larger / Smaller | ⌃⌥ = − |
| Next / Previous Display | ⌃⌥⌘ → ← |
| Restore | ⌃⌥ ⌫ |

Every action is also available in the menu bar menu. Change or clear shortcuts in **Settings → Shortcuts** (⌘, from the menu).

## Layout

| File | What |
|---|---|
| `Sources/Fling/Geometry.swift` | Actions, frame math, snap areas and throw directions (tested) |
| `Sources/Fling/Window.swift` | Accessibility API: find windows, set frames, minimize/close/full screen; screens |
| `Sources/Fling/Hotkeys.swift` | Shortcut model, defaults, saving, global hotkeys (Carbon) |
| `Sources/Fling/FlingApp.swift` | SwiftUI app, URL handling, preferences, menu |
| `Sources/Fling/AppState.swift` | Action dispatch, restore/cycling, custom positions, layouts, Pin Mode, triggers |
| `Sources/Fling/Models.swift` | Custom position, layout and URL models (tested) |
| `Sources/Fling/Stash.swift` | Edge stashing |
| `Sources/Fling/SnapPanel.swift` | Snap Panel tiles shown while dragging |
| `Sources/Fling/Trackpad.swift` | Trackpad finger-count trigger (private MultitouchSupport) |
| `Sources/Fling/WindowWatcher.swift` | New-window notifications for layouts |
| `Sources/Fling/ContextMenu.swift` | Pop-up action menu at the cursor |
| `Sources/Fling/Config.swift` | Export/import and iCloud Drive sync |
| `Sources/Fling/SmokeTest.swift`, `Tests/Smoke/` | `make smoke` live test and its test window |
| `Sources/Fling/Gestures.swift` | Event tap: drag snapping, Window Throw, Quick Throw, move/resize, footprint overlay |
| `Sources/Fling/SettingsView.swift` | Settings: General, Shortcuts (recorder), Mouse |
| `Sources/Fling/LayoutSettings.swift` | Settings: Custom positions and Layouts |
| `docs/rectangle-pro-research.md` | Feature research and roadmap notes |
