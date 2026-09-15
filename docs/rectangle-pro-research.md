# Rectangle Pro: feature inventory and how to emulate it

Researched 2026-09-14. Primary source: the official guide at rectangleapp.com/pro/docs (full text from its `llms-full.txt`), plus the open-source Rectangle repo.

---

## Fling status (2026-09-14)

Fling now covers most of this inventory. ✅ built · ◐ partly · ⬜ not built.

| Area (§) | Status | Notes |
|---|---|---|
| Window Throw (2.1) | ✅ | ⌃⌘ modifiers, mouse button, trackpad (3–5 fingers → 1); 16 configurable positions (portrait separately); dead zone and long-throw distance; center on another display. ⬜ Scrolling to resize the footprint, reticle styling, "ignore windows without toolbars" |
| Move & Resize (2.1) | ✅ | Hold modifiers and move the cursor |
| Quick Throw (2.2) | ◐ | One modifier, with a fixed mapping (left/right halves, up maximize, down minimize); Rectangle Pro sets a modifier per action |
| Action catalog (2.3) | ◐ | ✅ Halves, corners, thirds, fourths, sixths, maximize/almost/height, center, upper center, fill left/right, move to edges, nudge, larger/smaller, next/previous display (proportional), next/previous Space (untested), window controls, 2×2/2×3 tiles, cascade all/app, app halves, Win Arrow Keys, hold-to-repeat. ⬜ Fill corners, top/center/bottom thirds on landscape, fifths, eighths, ninths, corner two-thirds, center three-fourths, width- or height-only size, snap-to-corner moves, separate "display ratio" actions, Last, Tidy, Reveal Desktop Edge |
| Repeat behavior (2.3) | ◐ | Halves cycle ½ → ⅔ → ⅓; custom positions cycle through repeats. ⬜ Cycling across displays, choosing sizes, reset when modifiers are released |
| Custom Size & Position (2.4) | ◐ | Anchors, fractions or points, blank keeps the current value, target display, repeats, shortcut, snap target, URL and CLI. ⬜ Center Offset anchor, create from an existing window, View Footprint, auto icons |
| Snap areas, targets, panel (2.5) | ◐ | Every edge and corner configurable (portrait separately), bottom-edge thirds, restore on unsnap, haptics, snap targets, Snap Panel. ⬜ Other edge modes (drag toward center for ⅔, sixths from corners, fourths columns), panel position, modifier-gated targets, footprint appearance settings |
| Layouts (2.6) | ✅ | Save (presets where possible), shortcut, URL, CLI, triggers (display connect/disconnect, wake, window opens), frontmost app only, all matches, bring to front, launch missing apps, hide others, title matching, repeats via custom positions. ⬜ Minimize or quit other apps, per-entry repeats |
| Stash (2.7) | ◐ | Left/right, All, All Except Front, Toggle, Cycle, Unstash All, reveal delay, ⌘-only, hide when the cursor leaves, unstash on drag or another action, color tabs, re-tucked after sleep. ⬜ Up/down (macOS limits), animation, unhide when the app becomes frontmost, "hide in corner" |
| Pin Mode (2.8) | ✅ | App, width, side, toggle, reflow |
| Menu & icon (2.9) | ◐ | Hide icon, context menu by shortcut and by modifier-click. ⬜ Icon variants, choosing which items appear |
| General (2.10) | ◐ | Gaps, move cursor with window, double-click title bar, resize neighbors, Dock adjustment, restore windows on reconnect (now display memory), iCloud sync, JSON export/import, launch at login. ⬜ Stage Manager strip, "allow any keyboard shortcut", importing Rectangle's shortcuts, auto-updates (Sparkle), per-edge screen gaps and other hidden Terminal settings |
| Automation (2.11) | ✅ | `fling://` URLs (execute-action/custom/layout, save-layout) plus `flingctl`, which Rectangle Pro doesn't have |

Beyond Rectangle Pro (see `differentiation-research.md`): display memory, Snap Assist, keyboard grid, Float on Top, Diagnostics, left/right-specific shortcuts, a dotfile config, and `flingctl`.

## 1. The basics

| | |
|---|---|
| Developer | Ryan Hanson (rxhanson), who also makes the free, open-source Rectangle |
| What it is | A closed-source superset of Rectangle, downloaded as a separate app. It was originally named **Hookshot**, and the bundle ID is still `com.knollsoft.Hookshot` |
| Price | One-time lifetime license, about $9.99 according to third-party reviews. 10-day free trial. 3 active Macs per license, and activations can be moved to other Macs. Sold and licensed through Paddle |
| Requirements | macOS 13.5+ on Intel or Apple Silicon. Older builds: 3.79 for macOS 12–13.4, 3.59 for 10.15, 2.7.2 for 10.13.6 |
| Permissions | Accessibility (it moves windows through the AX API) |
| Support | Bugs and discussions live on GitHub at `rxhanson/RectanglePro-Community` |

---

## 2. Complete feature inventory

### 2.1 Cursor Movement
Moves or resizes the window **under the cursor**. That window doesn't need to be frontmost.

- **Window Throw** (default trigger: ⌃⌘ held)
  1. Hold the trigger while hovering over a window, and a reticle appears.
  2. The screen is split into pie sectors around the reticle. The sector the cursor is in picks one of **16 configurable sizes/positions**, and a footprint preview shows the result.
  3. Release the trigger to snap the window into place.
  - **Other display:** move the cursor to the center of another display to center the window on that display.
  - **Triggers:** modifier keys, a **mouse button** (by button number; 3 = middle), or a **trackpad gesture**. For the gesture, rest 3, 4 or 5 fingers, lift all but one, then move the remaining finger. It doesn't conflict with system gestures.
  - **Options:** scrolling resizes the footprint, ignore windows without toolbars, reticle size/color/ring image, *Safe Area* (dead zone radius), and *Min Dist to Appear* (so a middle-click still works as a normal click).
- **Long Throw:** moving the cursor farther out selects a second ring of actions. Setting: *Min Dist to Trigger*.
- **Move & Resize:** hold the modifiers and move the cursor to move or resize the window underneath. No clicking needed.

### 2.2 Quick Throw (the original Hookshot feature)
Move the cursor up, down, left or right across a window, then **tap and release a modifier** to apply the action mapped to that direction. No footprint is shown. Each action gets its own modifier. The author's own setup: Fill Left, Fill Right, Minimize and Maximize on ⌃, and Hide App on ⌃⌥⌘.
Quick Throw has everything in the action catalog below, plus **Control** actions (Full Screen, Close, Minimize, Quit App, Hide App) and all Stash actions.

### 2.3 Keyboard shortcut action catalog
| Category | Actions |
|---|---|
| Stateful | **Win Arrow Keys**: modifiers + arrows run a state machine similar to Windows (for example, Right gives the right half, then Up gives the top-right quarter) |
| Fill | Fill Left/Right, Fill Top-Left/Top-Right/Bottom-Left/Bottom-Right. Fills the empty space and cycles through fillable areas; falls back to half width |
| Maximize | Maximize, Almost Maximize (90% by default), Maximize Height |
| Halves | Left, Right, Center, Top, Bottom |
| Corners | Top-Left, Top-Right, Bottom-Left, Bottom-Right |
| Thirds | First/Center/Last Third, First/Center/Last Two-Thirds. **Orientation-aware**, so they switch to rows on portrait displays |
| Additional thirds | Top/Center/Bottom Third, Top/Bottom Two-Thirds |
| Corner two-thirds | TL/TR/BL/BR Two-Thirds |
| Fourths | First–Last Fourth, First/Center/Last Three-Fourths |
| Fifths | First–Last Fifth |
| Sixths | 3×2 grid cells, plus First/Last Sixth |
| Eighths | 4×2 grid cells |
| Ninths | 3×3 grid cells |
| Display | Next/Prev Display, Next/Prev Display **Ratio** (keeps the window's proportional frame on the new display), **Next/Prev Space** |
| Snap | Snap Left/Right/Up/Down and to the four corners (moves the window to the edge without resizing) |
| Nudge | Nudge Left/Right/Up/Down. **Hold the key to repeat** |
| Size | Larger/Smaller, plus width-only and height-only versions. Hold to repeat. Default step is 30 px, minimum size 25% |
| Other | Center, Upper Center, Restore (the frame from before the snap), Last (previous action) |
| Multiple windows | Reveal Desktop Edge, 2×2 Tiles, 2×3 Tiles, Cascade All, Cascade App, App Next/Prev Display, App Left/Right Half, Tidy |
| Hidden (set with `defaults`) | Center Prominently, a custom "specified" centered size, double/halve width or height, tile/cascade all or active app |

**Repeat behavior** (General tab): do nothing, cycle through displays, cycle sizes on halves (⅔ ½ ⅓ ¼ ¾, each can be turned off), move to the adjacent display, or adjacent-then-cycle. Optional **reset the cycle when modifiers are released**. Thirds, fourths and the other grids cycle through their cells when repeated.

**Next/Prev Space implementation (documented):** it synthesizes a mouse-down on the window's title bar and then sends the macOS "switch Space" shortcut (⌃← or ⌃→). If you've remapped that shortcut, Rectangle Pro has to be configured to send your version.

### 2.4 Custom Size & Position
- Each entry has a name, shortcut, **position** (Center, the edges, the corners, Custom Origin X/Y, or Center Offset), **size**, and **destination display** (Unchanged, Next, Prev, by name/ID, or by ordinal).
- Numbers can be fractions or decimals. A value ≤ 1 means a percentage of the screen, a value > 1 means pixels, and blank keeps the current value.
- **Repetitions:** chain more frames that run when the shortcut is pressed again.
- "View Footprint" preview, and an auto-generated icon.
- Entries can be used from a shortcut, the Window Throw, an edge snap area, a snap target, the Snap Panel, or the menu.
- You can create an entry from the frame of an existing window.

### 2.5 Snap Areas, Snap Targets, Snap Panel
- **Edge/corner drag-to-snap** with a footprint preview. Options: restore the original size when unsnapped, animate the footprint, **trackpad haptic feedback** when a snap area appears.
- Any action can be assigned to each edge or corner, including custom entries, Stash, Full Screen, Close, Minimize, Quit and Hide. Portrait displays get their own configuration.
- Edge modes depend on position: bottom-edge thirds (drag toward the center for ⅔), halves, sixths from the corners, fourths columns. Left and right edges default to halves, with top/bottom halves near the corners.
- **Snap Targets:** custom entries or per-app layout entries become drop zones anywhere on screen. They can be set to show only while certain modifiers are held (or not held). Targets created on the Applications tab only apply to that app.
- **Snap Panel:** a small palette appears next to the cursor (above, below, left or right) or at any screen edge or corner while you drag. Drop the window on a tile to run that action.
- Hidden settings: snap edge margins, `ignoredSnapAreas` bitfield, `snapModifiers` (only snap while modifiers are held), footprint alpha/border/color/fade/animation, sixths snap areas, and blocking fast drags into Mission Control.

### 2.6 Layouts (workspaces)
- **Save:** use "Save Current Layout…" from the menu or a shortcut, for one display or all of them. Rectangle Pro records the **last preset applied** to each window (such as "Left Half") where possible, otherwise the absolute frame.
- **Triggers:** a shortcut, the Window Throw, the menu, or the URL API. **Automatic triggers:** display connected or disconnected (a specific display), waking from sleep, or **a window opening**.
- **Scope:** *Frontmost app only* (one shortcut does different things depending on the app or title), or *All windows beyond first match*. The default matches each entry to one window.
- **Behavior:** bring windows to the front, **launch closed or minimized apps**, and **hide/minimize/quit apps that aren't in the layout**.
- **Each entry:** app (or Global), a preset or custom frame, destination display, snap target on/off, and a **window title matcher** (Any, Loosely Matches [fuzzy, the default], Contains, Regex).
- Repetitions run the next set of frames when the layout is triggered again.
- General setting: **automatically restore a display's layout when it's reconnected.**

### 2.7 Stash (the idea comes from the app *Tuck*)
- Actions: Stash Left/Right/Up/Down, Unstash, Stash All, Stash All Except One (the front window), Cycle Stashed, Toggle Stashed, Unstash All.
- A stashed window slides out when the cursor hits that screen edge.
- **Show:** immediately or after a 0.1–1.0 s delay, optionally only while ⌘ is held.
- **Hide:** after a delay, when the cursor leaves the window, or only while ⌘ is held.
- **Unhide** when the app becomes frontmost. **Unstash** when the window is dragged away from the edge or another action is run on it.
- Optional animation. "**Hide in the corner if left visible**" works around macOS limits: macOS won't let a window go fully off-screen, stashing up only works in some apps, and the Dock and bottom edge leave a sliver visible.
- **Color tabs:** each stashed window gets a small randomly colored tab on the edge, so several windows can share one edge and be revealed one at a time.

### 2.8 Pin Mode (called Todo Mode in Rectangle)
- One chosen app stays pinned to a side of the primary screen at a set width (pixels or %).
- Every other action places windows only in the space that's left.
- Shortcuts: **Toggle pin** and **Reflow pin**, which puts the pinned window back and moves overlapping windows out of its area.

### 2.9 Menu & Icon
- Hide the menu bar icon (relaunch the app to get to Settings) and choose an icon variant.
- Open the action menu **as a context menu** with a shortcut (acts on the frontmost window) or with **left-click + modifiers** (acts on the window under the cursor).
- Every action or category can be shown or hidden in the menu or placed in a submenu. Custom entries and layouts can be added.

### 2.10 General
- Launch at login. Restart on wake (a workaround for trackpad gestures that stop working). Auto-update (Sparkle).
- Configurable **gaps between windows**, optionally applied to screen edges as well. Hidden settings: per-edge screen gaps, a notch gap, and main-screen-only gaps.
- Move the cursor with the window when it goes to another display.
- **Double-click the title bar** to maximize or restore. This replaces the macOS behavior with a true maximize and supports an ignore list of apps.
- **Resize adjacent windows after dragging a window edge** (tiling-style shared edges).
- **Adjust windows when the Dock's size or position changes.**
- Stage Manager awareness: a reserved strip for the recent-apps area.
- "Allow any keyboard shortcut" removes the safeguards against overriding system shortcuts.
- **iCloud config sync**, JSON import and export, import shortcuts from Rectangle, restore defaults.

### 2.11 Automation
- URL scheme: `rectangle-pro://execute-action?name=<action>` (about 100 action names, including stash and pin), `execute-layout?name=`, and `execute-custom?name=`. Use `open -g` so the app doesn't come to the front.
- The `defaults write com.knollsoft.Hookshot …` hidden settings are inherited from Rectangle (see §2.3 and §2.5).
- The docs don't mention AppleScript or Shortcuts support.

### 2.12 Undocumented or unclear
**Tidy** and **Reveal Desktop Edge** appear in the action tables but aren't described. My guesses: Tidy rearranges windows so they don't overlap, and Reveal Desktop Edge slides windows aside so part of the desktop shows. You'd have to try the trial to confirm.

---

## 3. Emulation: the macOS building blocks

Nearly everything above uses the same small set of APIs. None of them require a sandbox, but all require Accessibility permission. Global event taps can also require Input Monitoring.

| Need | API |
|---|---|
| Read or set a window's frame, minimize, full screen, close, raise | `AXUIElement` + `kAXPosition/Size/Minimized/FullScreen/CloseButton` attributes, `AXRaise`. Rectangle's `AccessibilityElement.swift` shows how |
| Find the window under the cursor | `AXUIElementCopyElementAtPosition` on the system-wide element, then walk up to `kAXWindowRole` |
| All on-screen window bounds (for fill, tidy, adjacent resize) | `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` |
| Global mouse, keyboard, scroll and modifier events, and swallowing them | `CGEvent.tapCreate` (a session event tap) |
| Raw trackpad touches (the 3/4/5-finger → 1-finger gesture) | Private `MultitouchSupport.framework` (`MTDeviceCreateList`, `MTRegisterContactFrameCallback`). This is the same approach **MiddleClick** uses. It can break after sleep, which is why Pro has "restart on wake" |
| Reticle, footprint, Snap Panel, color tabs | Borderless transparent `NSPanel` with `ignoresMouseEvents`, a level above normal windows, and `.canJoinAllSpaces` |
| Haptics | `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, …)` |
| Display connect or disconnect | `CGDisplayRegisterReconfigurationCallback` or `NSApplication.didChangeScreenParametersNotification` |
| Wake | `NSWorkspace.didWakeNotification` |
| Window created or title changed | `AXObserver` per app (`kAXWindowCreatedNotification`, `kAXTitleChangedNotification`) plus `NSWorkspace.didLaunchApplicationNotification` |
| Launch, hide or quit apps | `NSWorkspace.openApplication`, `NSRunningApplication.hide()/terminate()` |
| Dock or visible-area changes | Compare `NSScreen.visibleFrame` when the screen-parameters notification fires (poll if needed) |
| Stage Manager on? | `defaults read com.apple.WindowManager GloballyEnabled` |
| Context menu at the cursor | `NSMenu.popUp(positioning:at:in: nil)` |
| URL scheme | `CFBundleURLTypes` + an `kAEGetURL` Apple Event handler |
| iCloud sync | Simple option: write the JSON config to `~/Library/Mobile Documents/com~apple~CloudDocs/…`, which needs no entitlement. The official option, `NSUbiquitousKeyValueStore`, requires a paid developer account entitlement |
| Moving windows between Spaces | **No public API.** Options: Pro's trick (synthetic title-bar mouse-down + ⌃←/→), yabai's scripting addition (requires partly disabling SIP), or private SkyLight/CGS calls, which macOS 14.5+ has increasingly blocked |

---

## 4. How to build each feature, with difficulty

| Feature | Approach | Difficulty |
|---|---|---|
| Shortcut action catalog, gaps, repeat cycling, Restore, Last | Already implemented in **Rectangle (MIT)**. Fork it | Trivial |
| Hidden grid actions (eighths, ninths, doubling) | Already in Rectangle | Trivial |
| Custom Size & Position + repetitions | Data model `{origin, size, display, [repeats]}` where values ≤ 1 are fractions. Rectangle's "specified" action is the seed | Easy |
| Win Arrow Keys | Small state table keyed on the last action and the arrow pressed | Easy |
| Nudge/Size hold-to-repeat | Handle key-repeat events in the hotkey handler (Rectangle's MASShortcut ignores repeats, so use a CGEventTap or a timer) | Easy |
| Fill Left/Right | Take the screen's visible frame, subtract other windows' bounds from `CGWindowList`, and pick the largest free rectangle on that side | Medium |
| Next/Prev Display Ratio | Map the window frame proportionally from one `visibleFrame` to the other | Easy |
| Move & Resize (modifier + move, no click) | Event tap on `mouseMoved` while modifiers are held, then set the AX position or size by the cursor delta. **Easy Move+Resize** (open source) does this with a click-drag | Easy |
| **Window Throw** | Event tap starts on the trigger → show the reticle panel at the cursor → on each move compute `atan2(dy, dx)` → pick a sector (16 or 8+8) → use distance for Long Throw → move the footprint panel → apply the frame on release. **Loop (GPLv3)** already has a radial menu for this | Medium |
| Mouse-button trigger | Same event tap on `otherMouseDown/Up`. Don't show anything or swallow the event until *Min Dist* is reached, so plain clicks still work | Easy |
| Trackpad gesture trigger | MultitouchSupport callback. State machine: ≥ N touches → drops to 1 → track that touch's movement → start the throw. The MiddleClick codebase already reads touch frames | Medium–hard, private API |
| Scroll-to-resize footprint | Catch and swallow `scrollWheel` in the tap while the throw is active | Easy |
| **Quick Throw** | Keep a ring buffer of cursor positions (about 150 ms). When a modifier goes down and up with no other key or click in between, use the dominant direction of recent movement, map it to an action, and apply it to the window under the cursor | Easy–medium |
| Edge snap areas, footprint, haptics | In Rectangle already, except haptics (one line) | Trivial |
| Snap Targets | During a window drag (Rectangle already detects this), hit-test the cursor against target rectangles and draw faint target panels | Medium |
| Snap Panel | While dragging, show a small panel of tiles near the cursor and run a tile's action on drop | Medium |
| Double-click title bar | Tap `leftMouseDown` with `clickCount == 2`, hit-test with AX, and check the point is in the top ~28 px of the window (or on an `AXToolbar`). Consider turning off the system's `AppleActionOnDoubleClick` | Easy |
| Resize adjacent windows | Record the frame on mouse-down. On mouse-up, find windows whose edge matched the moved edge (± a few px) and move their edges to match | Medium |
| Adjust for the Dock | When `visibleFrame` changes, re-fit windows that were flush with the old edge | Easy–medium |
| **Layouts** | Store entries as `{bundleID, titleMatcher, preset or frame, display}`. On apply, list windows per app through AX, match (exact → contains → regex → Levenshtein for "loose"), then set frames. Save by reading every window and looking up the last preset Rectangle recorded (`AppDelegate.windowHistory`) | Medium |
| Layout auto-triggers | Display reconfiguration callback (match on `CGDisplayCreateUUIDFromDisplayID`), wake notification, and AXObserver window-created events | Medium |
| Launch missing / hide others / quit others | NSWorkspace / NSRunningApplication | Easy |
| **Stash** | Move the window so only a few px remain on-screen. macOS stops windows from going above the menu bar and past some edges, so for those cases use the **corner-hiding trick** (AeroSpace hides windows almost entirely in the bottom-right corner). A thin tracking panel on each edge detects the cursor → run the delay → animate back with frame steps at 60 Hz → hide again when the cursor leaves the window rect | Medium–hard (edge cases, multiple displays) |
| Stash color tabs | One small colored `NSPanel` per stashed window on that edge, with hover tracking | Easy once Stash works |
| Pin Mode | Rectangle's **Todo Mode** already does this. Add a Reflow action that moves overlapping windows out of the pinned area | Easy |
| Next/Prev Space | Copy Pro's trick: post a `leftMouseDown` at the title bar, post ⌃→, wait about 300 ms, post `leftMouseUp`. It's fragile but needs no SIP changes | Medium |
| Context menu at cursor | `NSMenu.popUp` on a shortcut, or on a tapped click with modifiers | Easy |
| Menu customization | A visibility flag per menu item | Easy |
| URL API | Rectangle already has `rectangle://execute-action`. Add `execute-layout` and `execute-custom` | Trivial |
| iCloud sync | Export JSON to iCloud Drive and watch it with `NSFilePresenter` or `DispatchSource` | Easy |
| Stage Manager strip | In Rectangle already (`stageSize`) | Trivial |

---

## 5. Existing tools to borrow from or reuse

| Tool | License | Covers |
|---|---|---|
| **Rectangle** (github.com/rxhanson/Rectangle) | MIT, Swift | Pro's actual codebase ancestor: all shortcuts, snap areas, gaps, Todo/pin, URL scheme, JSON config, hidden settings. **This is the best base** |
| **Loop** (github.com/MrKai77/Loop) | GPLv3, Swift | Radial menu ≈ Window Throw, mouse/trackpad trigger, stash, cycles, URL and AppleScript support. Borrowing code makes your project GPL too |
| **Easy Move+Resize** | Open source | Modifier-drag move and resize |
| **Hammerspoon** | MIT, Lua | Fastest way to prototype almost everything: `hs.window`, `hs.eventtap` (throw, quick throw), `hs.canvas` (reticle and footprint), `hs.screen.watcher` + `hs.caffeinate.watcher` (layout triggers), `hs.window.filter` (window opened, title matching), `hs.urlevent`. No trackpad touch access |
| **AeroSpace** | MIT | Corner-hiding technique for stash and virtual workspaces without SIP changes |
| **yabai** | MIT | Space manipulation (requires partly disabling SIP) and window borders |
| **MiddleClick** (you already have a folder for it) | Open source (check license) | Reads raw MultitouchSupport touches, which is the basis for the trackpad Window Throw gesture |
| Paid options: Swish, BetterTouchTool, Moom, Tuck | — | Gestures, layouts on display change, edge stashing. Good for reference UX |

---

## 6. Suggested paths

1. **Zero code, about 80% coverage:** free Rectangle + Loop (throw, stash) + Easy Move+Resize. Missing: Layouts, Quick Throw, Snap Panel/Targets, trackpad gesture.
2. **Hammerspoon config, about 90%:** start with Rectangle for shortcuts and snap, then add a few hundred lines of Lua for Quick Throw, Window Throw (canvas reticle), Layouts with auto-triggers, Stash with the corner trick, and title-bar double-click. Missing: the trackpad gesture, a polished UI, and sync (put the config in iCloud Drive).
3. **Fork Rectangle, full parity:** it's MIT, the same codebase Pro started from, and the preference keys already match. Suggested order by value per effort: Quick Throw → Window Throw → Custom Size & Position repeats → Layouts → Stash → Snap Targets/Panel → trackpad gesture (MultitouchSupport code from MiddleClick) → Spaces trick. If you want to sell it, don't use Loop's GPL code and don't reuse the Rectangle or Hookshot names or artwork.

## 7. Gotchas
- AX calls are synchronous and can be slow with Electron or Java apps. Pro's "Enhanced UI" handling exists because `AXEnhancedUserInterface` (turned on by VoiceOver-style tools) makes frame changes animate slowly. Temporarily turn it off per app while moving windows.
- Some windows set min/max sizes or are fixed-size, so check the frame after setting it (hidden setting: `moveFixedSizeToEdge`).
- Event taps are disabled after a timeout if your callback is slow. Watch for `tapDisabledByTimeout` and turn the tap back on.
- MultitouchSupport devices go stale after sleep or a Bluetooth reconnect, so re-create them on wake.
- macOS clamps window positions, so windows can't go fully off-screen, which is why stash leaves slivers.
- No public Spaces API, and private SkyLight calls keep getting blocked in newer macOS versions.

## Sources
- Rectangle Pro Guide (full): https://rectangleapp.com/pro/docs/llms-full.txt
- Rectangle Pro homepage: https://rectangleapp.com/pro
- Rectangle Pro versions: https://rectangleapp.com/pro/versions
- Rectangle repo and TerminalCommands.md: https://github.com/rxhanson/Rectangle
- RectanglePro-Community: https://github.com/rxhanson/RectanglePro-Community
- Loop: https://github.com/MrKai77/Loop
- Price reference: https://www.mactools.pro/blog/rectangle-pro-is-it-worth-it
- Swish: https://highlyopinionated.co/swish/
