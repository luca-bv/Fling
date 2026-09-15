# Fling

A lightweight macOS window manager that lives in the menu bar.

- **Keyboard shortcuts** for halves, corners, thirds, fourths, sixths, fill, maximize, center, nudge, size, move, displays, Spaces and window controls. Repeating a half cycles ½ → ⅔ → ⅓; nudge and size repeat while held. **Win Arrow Keys** step between halves and corners like Windows.
- **Drag to snap**: screen edges and corners (each configurable, separately for portrait displays), a **Snap Panel** of tiles, and custom **snap targets**, with footprint previews and haptics. Drag a snapped window away to restore its size; drag a shared edge to resize neighbors.
- **Display memory**: windows go back to where they were for each display setup when you plug in or unplug a display, rearrange displays or wake the Mac, and reopened apps' windows return to their last spot. No setup needed.
- **Snap Assist**: after snapping a window, pick another window (click or press 1–9) to fill the rest of the screen.
- **Float on Top**: keep any window above the others (⌃⌥⌘P toggles). Fling shows a live mirror of the window; click it to use the real one. Needs Screen Recording permission.
- **Keyboard grid**: press ⌃⌥⌘G, then two letters (Q W E R / A S D F / Z X C V) to span the window across those grid cells.
- **Window Throw**: hold ⌃⌘, a mouse button, or rest 3–5 fingers on the trackpad and lift all but one; move toward one of 16 configurable positions and release.
- **Quick Throw**, and **move/resize by holding modifiers**.
- **Custom positions** (fractions or points, repeat cycles, per-display) and **Layouts** that arrange all your apps: by shortcut, URL, display connect/disconnect, wake, or as windows open.
- **Multiple windows**: 2×2 and 2×3 tiles, cascade, app halves.
- **Stash** windows at the screen edge (with color tabs, delay, ⌘-only); Stash All, Toggle and Cycle.
- **Pin Mode** keeps one app in a strip; everything else fills the rest.
- Gaps, double-click title bar to maximize, Dock-aware resizing, windows return when a display reconnects, context menu at the cursor, hideable menu bar icon, launch at login.
- **Configuration** export/import as JSON, iCloud Drive sync, and an optional `~/.config/fling/config.json` that Fling keeps up to date and reloads when you edit it (dotfiles-friendly).
- **Left/right-specific shortcuts** (e.g. right ⌘ + arrows), recorded from Settings → Shortcuts.
- **Diagnostics**: Settings → Diagnostics lists recent actions and explains why a window didn't move (fixed-size window, unresponsive app, missing permission), with a copyable report.
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
| Keyboard Grid | ⌃⌥⌘ G |
| Float on Top | ⌃⌥⌘ P |
| Restore | ⌃⌥ ⌫ |

Every action is also available in the menu bar menu. Change or clear shortcuts in **Settings → Shortcuts** (⌘, from the menu).

## Command line

`make install-cli` links `flingctl` into `~/.local/bin` (set `PREFIX` for another location). It talks to the running Fling (opening it if needed), prints results, and exits non-zero with the reason when something fails.

```sh
flingctl left-half                          # any action; `flingctl actions` lists them
flingctl --app Safari top-left-sixth        # target an app's front window by name or bundle ID
flingctl frame 0 25 1200 800                # exact frame, top-left of the main display
flingctl layout "Deep Work"                 # apply a layout; `flingctl save-layout "Deep Work"` saves one
flingctl windows --json                     # also: displays, layouts, customs, actions
flingctl config export > fling.json         # and: flingctl config import fling.json
```

## Automation

Every action, custom position and layout can be run by URL, so anything that opens URLs can drive Fling:

```sh
open -g "fling://execute-action?name=left-half"        # action names: the menu titles, kebab-cased
open -g "fling://execute-custom?name=Wide%20Center"     # a custom position, by name
open -g "fling://execute-layout?name=Deep%20Work"       # a layout, by name
open -g "fling://save-layout?name=Deep%20Work"          # save the current windows as a layout (replaces one with that name)
```

**Layouts per Focus mode (Shortcuts app):** Automation → New Automation → Focus → pick a Focus → "When Turning On" → add the **Open URLs** action with `fling://execute-layout?name=Deep%20Work`, and turn off "Ask Before Running". Add another for "When Turning Off" with your everyday layout.

**Other triggers the same way:** Shortcuts' App automation (when Zoom opens → meeting layout), Time of Day, or Wi-Fi network (home vs office desk); a terminal alias or Raycast/Alfred script command running `open -g "fling://…"`; Stream Deck or BetterTouchTool buttons that open a URL.

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
| `Sources/Fling/KeyboardGrid.swift` | Lettered grid overlay for two-key placement |
| `Sources/Fling/SnapAssist.swift` | Pick-a-window panel for the space left after snapping |
| `Sources/Fling/DisplayMemory.swift` | Window positions remembered per display setup |
| `Sources/Fling/Trackpad.swift` | Trackpad finger-count trigger (private MultitouchSupport) |
| `Sources/Fling/WindowWatcher.swift` | New-window notifications for layouts |
| `Sources/Fling/ContextMenu.swift` | Pop-up action menu at the cursor |
| `Sources/Fling/FloatingWindows.swift` | Float on Top: live ScreenCaptureKit mirrors in floating panels |
| `Sources/Fling/CommandServer.swift`, `CommandLineInterface.swift` | flingctl's socket server and commands |
| `Sources/flingctl/main.swift` | The `flingctl` client |
| `Sources/Fling/Config.swift` | Export/import, iCloud Drive sync and the dotfile config |
| `Sources/Fling/SmokeTest.swift`, `Tests/Smoke/` | `make smoke` live test and its test window |
| `Sources/Fling/Gestures.swift` | Event tap: drag snapping, Window Throw, Quick Throw, move/resize, footprint overlay |
| `Sources/Fling/SettingsView.swift` | Settings: General, Shortcuts (recorder), Mouse |
| `Sources/Fling/LayoutSettings.swift` | Settings: Custom positions and Layouts |
| `docs/rectangle-pro-research.md` | Rectangle Pro feature research |
| `docs/differentiation-research.md` | Competitive research and roadmap |
