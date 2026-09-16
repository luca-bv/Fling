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
- Gaps, double-click title bar to maximize, Dock-aware resizing, context menu at the cursor, hideable menu bar icon, launch at login.
- **Configuration** export/import as JSON, iCloud Drive sync, and an optional `~/.config/fling/config.json` that Fling keeps up to date and reloads when you edit it (dotfiles-friendly).
- **Left/right-specific shortcuts** (e.g. right ⌘ + arrows), recorded from Settings → Shortcuts.
- **Diagnostics**: Settings → Diagnostics lists recent actions and explains why a window didn't move (fixed-size window, unresponsive app, missing permission), with a copyable report.
- **Command line and URLs**: `flingctl` and `fling://` URLs run actions, custom positions and layouts from scripts, Shortcuts and launchers (see below).

Requires macOS 14+.

## Install

```sh
git clone https://github.com/luca-bv/Fling.git && cd Fling && ./install.sh
```

Builds from source and puts Fling in `/Applications`, signed with the local "Fling Dev" certificate
(`make cert`, created on first run) so the Accessibility grant survives updates. Then allow Fling in
System Settings → Privacy & Security → Accessibility.

To update, run `./install.sh` again — from a clone it builds what you have checked out; run from
anywhere else it keeps its own clone in `~/.local/share/Fling` and pulls before building.
Needs the Swift toolchain (`xcode-select --install`). `DEST=~/Applications ./install.sh` installs elsewhere.

## Build & run

```sh
make run    # builds build/Fling.app and opens it
make test   # unit tests (geometry, models, config, command parsing)
make smoke  # moves a throwaway test window through real actions and prints PASS/FAIL
```

On first launch macOS asks for **Accessibility** access (System Settings → Privacy & Security → Accessibility). Fling needs it to move other apps' windows. **Float on Top** also needs **Screen Recording** (Privacy & Security → Screen & System Audio Recording); nothing else does.

> Run `make cert` once first. It creates a self-signed "Fling Dev" signing certificate in your login keychain, so rebuilds keep the Accessibility grant. Without it, builds are ad-hoc signed and macOS forgets the grant after every rebuild.

If you also run Rectangle, quit it first. It uses the same default shortcuts.

## Releases

```sh
make dmg VERSION=0.2.0   # → build/Fling-0.2.0.dmg
```

The disk image holds a universal app (Apple Silicon and Intel) signed with the "Fling Dev" certificate, an Applications shortcut, and `Read Me First.txt` with install steps for testers.

- **Not notarized.** On testers' Macs, Gatekeeper blocks the first launch. They allow it once in System Settings → Privacy & Security → **Open Anyway** (steps are in the read-me). Notarization needs an Apple Developer ID ($99/year).
- **Always sign releases with the same certificate.** macOS ties the Accessibility grant to it, so testers keep their permission across updates. `make dmg` refuses to build ad-hoc. Back up the certificate: in Keychain Access, export "Fling Dev" (certificate and private key) as a .p12. A new certificate means every tester re-grants Accessibility.
- Bump `VERSION` for each release. The build number is the commit count.

## Shortcuts

Four layers, all built on ⌃⌥ and clear of macOS's own shortcuts. Rectangle's keys are unchanged, so switching from Rectangle or Rectangle Pro needs no relearning.

**⌃⌥ places the window**

| Keys | Action |
|---|---|
| ⌃⌥ ← → ↑ ↓ | Left / Right / Top / Bottom Half (repeat: ½ → ⅔ → ⅓) |
| ⌃⌥ U I J K | Top Left / Top Right / Bottom Left / Bottom Right |
| ⌃⌥ D F G | First / Center / Last Third |
| ⌃⌥ E R T | First / Center / Last Two Thirds |
| ⌃⌥ 1 2 3 4 | First / Second / Third / Last Fourth |
| ⌃⌥ L ; ' | Top Left / Center / Right Sixth |
| ⌃⌥ , . / | Bottom Left / Center / Right Sixth |
| ⌃⌥ ↩ | Maximize |
| ⌃⌥ C | Center |
| ⌃⌥ − = | Smaller / Larger (hold to repeat) |
| ⌃⌥ ⌫ | Restore |

**⌃⌥⇧ is a variant of the same key**

| Keys | Action |
|---|---|
| ⌃⌥⇧ ↑ | Maximize Height |
| ⌃⌥⇧ ↩ | Almost Maximize |
| ⌃⌥⇧ ← → | Fill Left / Right |
| ⌃⌥⇧ C | Upper Center |
| ⌃⌥⇧ 1 4 | First / Last Three Fourths |

**⌃⌥⌘ moves between screens and opens tools**

| Keys | Action |
|---|---|
| ⌃⌥⌘ ← → | Previous / Next Display |
| ⌃⌥⌘ [ ] | Previous / Next Space |
| ⌃⌥⌘ G | Keyboard Grid |
| ⌃⌥⌘ P | Float on Top |
| ⌃⌥⌘ M | Fling menu at the cursor |

**⌃⌥⌘⇧ stashes** (one key if Caps Lock is remapped to Hyper)

| Keys | Action |
|---|---|
| ⌃⌥⌘⇧ ← → | Stash Left / Right |
| ⌃⌥⌘⇧ ↓ | Toggle Stashed Windows |

Everything else (nudge, move to edge, Win Arrow Keys, tiles, Pin Mode…) has no default. Assign keys in **Settings → Shortcuts** (⌘, from the menu); only your changes are saved, so improved defaults still reach you.

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
| `Sources/Fling/Hotkeys.swift` | Shortcut model and defaults; global hotkeys (Carbon, plus the event tap for left/right-specific ones) |
| `Sources/Fling/FlingApp.swift` | SwiftUI app, preferences, menu bar menu |
| `Sources/Fling/AppState.swift` | Action dispatch, restore/cycling, custom positions, layouts, Pin Mode, triggers |
| `Sources/Fling/Models.swift` | Custom position, layout, display memory and URL-to-command models (tested) |
| `Sources/Fling/Stash.swift` | Edge stashing |
| `Sources/Fling/SnapPanel.swift` | Snap Panel tiles shown while dragging |
| `Sources/Fling/KeyboardGrid.swift` | Lettered grid overlay for two-key placement |
| `Sources/Fling/SnapAssist.swift` | Pick-a-window panel for the space left after snapping |
| `Sources/Fling/DisplayMemory.swift` | Window positions remembered per display setup |
| `Sources/Fling/Trackpad.swift` | Trackpad finger-count trigger (private MultitouchSupport) |
| `Sources/Fling/WindowWatcher.swift` | New-window notifications for layouts and display memory |
| `Sources/Fling/ContextMenu.swift` | Pop-up action menu at the cursor |
| `Sources/Fling/FloatingWindows.swift` | Float on Top: live ScreenCaptureKit mirrors in floating panels |
| `Sources/Fling/CommandServer.swift`, `CommandLineInterface.swift` | flingctl's socket server and commands |
| `Sources/flingctl/main.swift` | The `flingctl` client |
| `Sources/Fling/Config.swift` | Export/import, iCloud Drive sync and the dotfile config |
| `Sources/Fling/SmokeTest.swift`, `Tests/Smoke/` | `make smoke` live test and its test window |
| `Sources/Fling/Gestures.swift` | Event tap: drag snapping, Window Throw, Quick Throw, move/resize, footprint overlay |
| `Sources/Fling/SettingsView.swift` | Settings: General, Shortcuts (recorder), Mouse, Diagnostics |
| `Sources/Fling/LayoutSettings.swift` | Settings: Custom positions and Layouts |
| `install.sh` | Build-from-source installer into `/Applications` |
| `release/Read Me First.txt` | Install steps shipped inside the disk image |
| `docs/rectangle-pro-research.md` | Rectangle Pro feature research |
| `docs/differentiation-research.md` | Competitive research and roadmap |

## License

MIT. See [LICENSE](LICENSE).
