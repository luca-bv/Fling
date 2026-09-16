<div align="center">

# Fling

**A lightweight macOS window manager that lives in the menu bar.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-native-F05138?logo=swift&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

[Features](#features) · [Install](#install) · [Shortcuts](#shortcuts) · [Command line](#command-line) · [Automation](#automation) · [Development](#development)

</div>

---

## Features

### ⌨️ Keyboard

- **Shortcuts for everything**: halves, corners, thirds, fourths, sixths, fill, maximize, center, nudge, size, move, displays, Spaces and window controls (minimize, full screen, close, hide, quit).
- **Repeat to cycle**: pressing a half again cycles ½ → ⅔ → ⅓. Nudge and size repeat while held.
- **Win Arrow Keys** step between halves and corners, like Windows.
- **Keyboard Grid**: press ⌃⌥⌘G, then two letters (`Q W E R` / `A S D F` / `Z X C V`) to span the window across those grid cells.
- **Left/right-specific shortcuts** (e.g. right ⌘ + arrows), recorded from Settings → Shortcuts.

### 🖱️ Mouse and trackpad

- **Drag to snap** onto screen edges and corners, each configurable (separately for portrait displays), with footprint previews and haptics.
- **Snap Panel**: a set of tiles to drop a window onto while dragging, plus your own custom **snap targets**.
- **Drag to restore and resize**: drag a snapped window away to get its old size back; drag a shared edge to resize the windows next to it.
- **Window Throw**: hold ⌃⌘, a mouse button, or rest 3–5 fingers on the trackpad and lift all but one. Move toward one of 16 configurable positions and release.
- **Quick Throw**: tap a modifier while moving the cursor and the window goes the way you were heading.
- **Move and resize by holding modifiers**, set up in Settings → Mouse.
- **Double-click the title bar** to maximize.

### 🧩 Filling the screen

- **Fill the Rest**: after snapping a window, pick another one (click, or press 1–9) for the space left over. It can be switched on or off per source (keyboard shortcuts, drags and throws) and is off after throws by default. After a shortcut it shows only while you keep those keys held, so it never gets in the way.
- **Multiple windows**: 2×2 and 2×3 tiles, cascade, app halves.
- **Pin Mode** keeps one app in a strip and fills the rest of the screen with everything else.
- **Stash** windows at the screen edge, with color tabs, a delay and a ⌘-only option. Stash All, Toggle and Cycle.
- **Float on Top** keeps any window above the others (⌃⌥⌘P toggles). Fling shows a live mirror of the window; click it to use the real one. Needs Screen Recording permission.

### 🗂️ Custom positions and layouts

- **Custom positions**: fractions or points, repeat cycles, per display.
- **Layouts** arrange all your apps at once. Run them by shortcut, by URL, when a display connects or disconnects, on wake, or as windows open.
- **Undo Layout**: running a layout records where every window was first, so Undo Layout puts them all back, including layouts that ran on their own after a wake or display change.
- **Per-layout behavior**: snap everything back as soon as you move a window by hand, or let the layout's own shortcut undo it.

### 🖥️ Display memory

Windows go back to where they were for each display setup when you plug in or unplug a display, rearrange displays or wake the Mac. Reopened apps' windows return to their last spot. No setup needed.

### ⚙️ Everything else

- **Gaps** between windows, **Dock-aware** resizing.
- **Context menu at the cursor** (⌃⌥⌘M).
- **Hideable menu bar icon** and **launch at login**.
- **Configuration**: export/import as JSON, iCloud Drive sync, and an optional `~/.config/fling/config.json` that Fling keeps up to date and reloads when you edit it (dotfiles-friendly).
- **Diagnostics**: Settings → Diagnostics lists recent actions and explains why a window didn't move (fixed-size window, unresponsive app, missing permission), with a copyable report.
- **Command line and URLs**: [`flingctl`](#command-line) and [`fling://` URLs](#automation) run actions, custom positions and layouts from scripts, Shortcuts and launchers.

---

## Install

> Requires **macOS 14** or later and the Swift toolchain (`xcode-select --install`).

```sh
git clone https://github.com/luca-bv/Fling.git && cd Fling && ./install.sh
```

This builds from source and puts Fling in `/Applications`, signed with the local "Fling Dev" certificate (`make cert`, created on first run) so the Accessibility grant survives updates.

**Then** allow Fling in System Settings → Privacy & Security → **Accessibility**.

| | |
|---|---|
| **Update** | Run `./install.sh` again. From a clone it builds what you have checked out; run from anywhere else, it keeps its own clone in `~/.local/share/Fling` and pulls before building. |
| **Install elsewhere** | `DEST=~/Applications ./install.sh` |

### Permissions

| Permission | Needed for | Where |
|---|---|---|
| **Accessibility** | Moving other apps' windows (everything) | Privacy & Security → Accessibility |
| **Screen Recording** | Float on Top only | Privacy & Security → Screen & System Audio Recording |

Nothing else needs extra permissions.

> [!NOTE]
> If you also run Rectangle, quit it first. It uses the same default shortcuts.

---

## Shortcuts

Four layers, all built on ⌃⌥ and clear of macOS's own shortcuts. Rectangle's keys are unchanged, so switching from Rectangle or Rectangle Pro needs no relearning.

<table>
<tr>
<td valign="top">

**⌃⌥ places the window**

| Keys | Action |
|---|---|
| ⌃⌥ ← → ↑ ↓ | Left / Right / Top / Bottom Half<br><sub>repeat: ½ → ⅔ → ⅓</sub> |
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

</td>
<td valign="top">

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

**⌃⌥⌘⇧ stashes**<br><sub>one key if Caps Lock is remapped to Hyper</sub>

| Keys | Action |
|---|---|
| ⌃⌥⌘⇧ ← → | Stash Left / Right |
| ⌃⌥⌘⇧ ↓ | Toggle Stashed Windows |

</td>
</tr>
</table>

Everything else (nudge, move to edge, Win Arrow Keys, tiles, Pin Mode…) has no default. Assign keys in **Settings → Shortcuts** (⌘, from the menu). Only your changes are saved, so improved defaults still reach you.

---

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

---

## Automation

Every action, custom position and layout can be run by URL, so anything that opens URLs can drive Fling:

```sh
open -g "fling://execute-action?name=left-half"        # action names: the menu titles, kebab-cased
open -g "fling://execute-custom?name=Wide%20Center"     # a custom position, by name
open -g "fling://execute-layout?name=Deep%20Work"       # a layout, by name
open -g "fling://save-layout?name=Deep%20Work"          # save the current windows as a layout (replaces one with that name)
```

<details>
<summary><b>Layouts per Focus mode (Shortcuts app)</b></summary>

1. Automation → New Automation → **Focus** → pick a Focus → **When Turning On**.
2. Add the **Open URLs** action with `fling://execute-layout?name=Deep%20Work`.
3. Turn off **Ask Before Running**.
4. Add another automation for **When Turning Off** with your everyday layout.

</details>

<details>
<summary><b>Other triggers</b></summary>

- **Shortcuts automations**: App (when Zoom opens → meeting layout), Time of Day, or Wi-Fi network (home vs office desk).
- **Terminal and launchers**: a shell alias or a Raycast/Alfred script command running `open -g "fling://…"`.
- **Hardware buttons**: Stream Deck or BetterTouchTool buttons that open a URL.

</details>

---

## Development

### Build and run

```sh
make run    # builds build/Fling.app and opens it
make test   # unit tests (geometry, models, config, command parsing)
make smoke  # moves a throwaway test window through real actions and prints PASS/FAIL
```

> [!TIP]
> Run `make cert` once first. It creates a self-signed "Fling Dev" signing certificate in your login keychain, so rebuilds keep the Accessibility grant. Without it, builds are ad-hoc signed and macOS forgets the grant after every rebuild.

### Releases

```sh
make dmg VERSION=0.2.0   # → build/Fling-0.2.0.dmg
```

The disk image holds a universal app (Apple Silicon and Intel) signed with the "Fling Dev" certificate, an Applications shortcut, and `Read Me First.txt` with install steps for testers.

> [!WARNING]
> **Not notarized.** On testers' Macs, Gatekeeper blocks the first launch. They allow it once in System Settings → Privacy & Security → **Open Anyway** (steps are in the read-me). Notarization needs an Apple Developer ID ($99/year).

> [!IMPORTANT]
> **Always sign releases with the same certificate.** macOS ties the Accessibility grant to it, so testers keep their permission across updates. `make dmg` refuses to build ad-hoc. Back up the certificate: in Keychain Access, export "Fling Dev" (certificate and private key) as a .p12. A new certificate means every tester re-grants Accessibility.

Bump `VERSION` for each release. The build number is the commit count.

### Project layout

<details>
<summary>Source map</summary>

| File | What |
|---|---|
| `Sources/Fling/FlingApp.swift` | SwiftUI app, preferences, menu bar menu |
| `Sources/Fling/AppState.swift` | Action dispatch, restore/cycling, custom positions, layouts, Pin Mode, triggers |
| `Sources/Fling/Geometry.swift` | Actions, frame math, snap areas and throw directions (tested) |
| `Sources/Fling/Models.swift` | Custom position, layout, display memory and URL-to-command models (tested) |
| `Sources/Fling/Window.swift` | Accessibility API: find windows, set frames, minimize/close/full screen; screens |
| `Sources/Fling/Hotkeys.swift` | Shortcut model and defaults; global hotkeys (Carbon, plus the event tap for left/right-specific ones) |
| `Sources/Fling/Gestures.swift` | Event tap: drag snapping, Window Throw, Quick Throw, move/resize, footprint overlay |
| `Sources/Fling/Trackpad.swift` | Trackpad finger-count trigger (private MultitouchSupport) |
| `Sources/Fling/SnapPanel.swift` | Snap Panel tiles shown while dragging |
| `Sources/Fling/KeyboardGrid.swift` | Lettered grid overlay for two-key placement |
| `Sources/Fling/FillRest.swift` | Fill the Rest: pick-a-window panel for the space left after snapping |
| `Sources/Fling/Stash.swift` | Edge stashing |
| `Sources/Fling/FloatingWindows.swift` | Float on Top: live ScreenCaptureKit mirrors in floating panels |
| `Sources/Fling/DisplayMemory.swift` | Window positions remembered per display setup |
| `Sources/Fling/WindowWatcher.swift` | New-window notifications for layouts and display memory |
| `Sources/Fling/ContextMenu.swift` | Pop-up action menu at the cursor |
| `Sources/Fling/Config.swift` | Export/import, iCloud Drive sync and the dotfile config |
| `Sources/Fling/SettingsView.swift` | Settings: General, Shortcuts (recorder), Mouse, Diagnostics |
| `Sources/Fling/LayoutSettings.swift` | Settings: Custom positions and Layouts |
| `Sources/Fling/CommandServer.swift`, `CommandLineInterface.swift` | flingctl's socket server and commands |
| `Sources/flingctl/main.swift` | The `flingctl` client |
| `Sources/Fling/SmokeTest.swift`, `Tests/Smoke/` | `make smoke` live test and its test window |
| `install.sh` | Build-from-source installer into `/Applications` |
| `release/Read Me First.txt` | Install steps shipped inside the disk image |
| `docs/rectangle-pro-research.md` | Rectangle Pro feature research |
| `docs/differentiation-research.md` | Competitive research and roadmap |

</details>

---

## License

MIT. See [LICENSE](LICENSE).
