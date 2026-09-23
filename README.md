<p align="center">
  <img src="assets/logo.svg" alt="Fling logo" width="120"/>
</p>

<h1 align="center">Fling</h1>

<p align="center">A lightweight macOS window manager for the menu bar. Free, native Swift, MIT licensed.</p>

## Install

```sh
git clone https://github.com/luca-bv/Fling.git && cd Fling && ./install.sh
```

Builds Fling and puts it in `/Applications`. Needs macOS 14+ and the Swift toolchain (`xcode-select --install`). To update, run `./install.sh` again.

## Getting started

1. Open Fling. Its icon appears in the menu bar.
2. Allow it in System Settings → Privacy & Security → **Accessibility**.
3. Press `⌃⌥←` to snap a window to the left half. Press it again to cycle ½ → ⅔ → ⅓.
4. Open **Settings** from the menu bar icon to change shortcuts and everything else.

If you use Rectangle, quit it first: Fling uses the same default shortcuts.

## Default shortcuts

| Keys | Action |
|---|---|
| `⌃⌥ ← → ↑ ↓` | Halves |
| `⌃⌥ U I J K` | Corners |
| `⌃⌥ D F G` / `E R T` | Thirds / two-thirds |
| `⌃⌥ 1 2 3 4` | Fourths |
| `⌃⌥ L ; '` and `, . /` | Sixths (top row, bottom row) |
| `⌃⌥ ↩` / `⌃⌥ C` | Maximize / center |
| `⌃⌥ − =` | Smaller / larger |
| `⌃⌥ ⌫` | Restore |
| `⌃⌥⌘ ← →` | Previous / next display |
| `⌃⌥⌘ [ ]` | Previous / next Space |
| `⌃⌥⌘ G` / `P` / `M` | Keyboard grid / float on top / menu at the cursor |
| `⌃⌥⌘⇧ ← → ↓` | Stash left / right / toggle stashed |

Hold `⇧` with `⌃⌥` for variants (maximize height, almost maximize, fill left/right, upper center, three-fourths). Every other action can be given a shortcut in Settings.

## Features

- **Drag to snap** to screen edges, or drop on the Snap Panel.
- **Window Throw**: hold `⌃⌘` (or a mouse button, or rest fingers on the trackpad) and flick a window toward where it should go.
- **Fill the Rest**: after snapping one window, pick another for the space left over.
- **Layouts**: save and restore every window at once, from a shortcut, a URL, or automatically on wake or a display change. Undo Layout puts things back.
- **Display Memory**: windows return to where they were when you plug in a display, wake the Mac or reopen an app.
- **Also**: custom positions, stash windows at the screen edge, Pin Mode, float on top (needs Screen Recording), gaps, and config sync through iCloud Drive or `~/.config/fling/config.json`.

## Command line and URLs

`make install-cli` adds `flingctl` to `~/.local/bin`:

```sh
flingctl left-half                     # run any action (`flingctl actions` lists them)
flingctl --app Safari maximize         # act on a specific app's window
flingctl layout "Deep Work"            # apply a saved layout
```

The same works from Shortcuts, Raycast, Alfred or anything that opens URLs:

```sh
open -g "fling://execute-action?name=left-half"
open -g "fling://execute-layout?name=Deep%20Work"
```

## Development

```sh
make cert   # once: a local signing certificate, so rebuilds keep the Accessibility permission
make run    # build and open build/Fling.app
make test   # unit tests
make smoke  # moves a test window through real actions
```

## License

MIT. See [LICENSE](LICENSE).
