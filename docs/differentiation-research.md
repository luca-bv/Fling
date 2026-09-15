# What could differentiate Fling

Researched 2026-09-14. Sources: top-voted issues and discussions in the Rectangle, Rectangle Pro Community, Loop and AeroSpace repos (pulled via the GitHub API), reviews and comparisons of the macOS window-manager field, and coverage of Apple's built-in tiling. Links are at the end.

---

## TL;DR

Fling already matches most of Rectangle Pro. Matching features won't win users, because most of these tools already do the basics well:
- Apple added halves and quarters in Sequoia and Tahoe.
- Rectangle is free, and Loop is free and open source.

The openings are the problems **nobody in the snapping/throwing category solves well.** Some quick wins also come straight out of competitors' bug trackers.

**Recommended positioning:** *"The open-source Rectangle Pro that remembers."* It would be the full keyboard, mouse and trackpad toolset, free and inspectable, plus automatic memory of where windows belong for each display setup and Space.

**Top five bets, in order:**
1. **Display- and Space-aware memory**, which puts Stay inside a window manager. This has the strongest unmet need, and Fling is already about 40% of the way there.
2. **Snap Assist for ordinary windows**, as on Windows: after you snap one window, pick what fills the rest of the screen.
3. **A keyboard grid**, as in GNOME Tactile: press a hotkey, a lettered grid appears, and typing two letters spans the window across those cells. It's the #1 request in Rectangle Pro's community tracker.
4. **An automation surface:** a CLI, a dotfile-friendly config, and Shortcuts recipes. AeroSpace's rise shows power users want this, and Rectangle Pro offers only a URL scheme.
5. **Visible reliability:** an open test suite plus a "why didn't that window move?" diagnostics panel. Competitors' trackers are full of silent failures.

> **Status (2026-09-14):** all five bets are built, plus always on top (F) and power-user triggers (G). Still open: Spaces-aware memory, AI arrangements, and distribution (notarization). Each opportunity below has a **Status** line, and §6 has the checklist.

---

## 1. The landscape

| App | Model | Price / license | Known for | Weak spots seen in reviews and trackers |
|---|---|---|---|---|
| **macOS Sequoia/Tahoe tiling** | Drag to edges, green-button menu | Built in | Halves and quarters, no install | Only 2–4 window layouts, no saved layouts, barely customizable shortcuts, no sixths, no size cycling, no moving between displays |
| **Rectangle** | Keyboard snapping | Free, MIT (★29.9k) | Big shortcut catalog | Stage Manager bugs, gaps and Dock edge cases; no mouse throw, layouts or stash |
| **Rectangle Pro** | Keyboard + throw + layouts | $9.99, closed | Window Throw, layouts, stash, pin | Stash lost after wake (#134), snap areas stop working (#353, #691), settings UI freezes (#856), app-specific breakage (Teams) |
| **Loop** | Radial menu, mouse-first | Free, GPL (★11.6k) | Polish, radial menu, active development | Fewer keybindings than Rectangle Pro; top requests are resizing neighbors, Snap Assist, custom sizes in the radial menu, always-on-top |
| **Moom** | Saved layouts | ~$10 | Named layouts on a keystroke | Hours of setup; ignores per-display memory |
| **Magnet** | Snapping | ~$5 | Simple | Reddit consensus: Rectangle does more for free |
| **Swish** | Trackpad gestures | ~$16 / Setapp | 30 gestures, haptics | Weak on ultrawide screens, no quarter splits, breaks on new macOS releases |
| **Raycast** | Launcher with window commands | Free / Pro | "Already have it" convenience | Basics only; users pair it with Moom for layouts |
| **AeroSpace** | i3-style tiling | Free, MIT (★23k) | Config file, CLI, virtual workspaces | Different audience (full tiling); top requests: sticky/floating on top (107, 54), left vs right modifier keys (102), ultrawide (65) |
| **yabai / Amethyst** | Automatic tiling | Free, OSS | Binary space partitioning; yabai needs SIP partly off for Spaces | Setup cost, SIP |
| **Stay** | Per-display window memory | Free since Aug 2025 | Remembers layouts per display configuration | Not a window manager; can't move apps between Spaces |
| **BetterStage** | Stages + tiling + **AI Staging** | Free tier; $19.99+; AI $4.99/mo | Plain-language arrangements | Heavy; AI needs a subscription |
| **Floaty, TopWindow, KeepTop…** | Always-on-top | Paid, single-purpose | Pinning any window, no SIP changes | A whole separate app for one feature |

A directory of 96 macOS window tools lists 54 window managers. The basic-snapping space is crowded.

---

## 2. Evidence of unmet needs

Vote counts are GitHub 👍 or upvotes. Rectangle Pro's community tracker is small, so treat its numbers as *direction*, not size. AeroSpace's counts show more demand from power users.

| Need | Evidence |
|---|---|
| **Windows should remember where they were per display setup and Space** | Rectangle Pro "Saving windows positions in different desktops" (7↑, highest in Q&A); "App Layouts for different connected displays" (#427); "Multiple Snap Areas depending on Monitor" (3↑); "display-specific custom actions" (2↑); "Using Rectangle Pro as a Stay replacement" (3↑); Mac Power Users thread asking for Stay plus moving windows between Spaces; reviewers note Moom, Rectangle and Magnet ignore this |
| **Resize neighbors / fill the gap left behind** | Loop's #1 request (#264, 10👍); Rectangle Pro #270 "Automatic resizing of other windows" (4👍); #715 (16 comments). *Fling has resizing on shared-edge drag.* |
| **Snap Assist** | Loop #215 (4👍); Rectangle Pro #648 "Tile layout suggestions similar to Apple's"; macOS only offers this inside full-screen Split View |
| **Keyboard grid (Tactile)** | Rectangle Pro #516 "Tactile-like hotkeys": top-voted open issue |
| **Always on top / sticky floating** | AeroSpace #2 (107👍) and #4 (54👍); Loop #1121; Rectangle Pro "Always On Top Mode" (3↑); a cluster of single-purpose paid apps since 2025 |
| **Left vs right modifier keys, Caps Lock / Hyper triggers** | AeroSpace #28 (102👍); Loop #712 (Caps Lock), #100 (F keys) |
| **Ultrawide and portrait-aware behavior** | AeroSpace #60 (65👍); Swish complaints; Rectangle Pro "different Window Throw settings for portrait vs landscape" (2↑) |
| **Config portability and automation** | Rectangle #190 (JSON import/export); Loop #945; Rectangle Pro ideas "custom folder/URL for config file" and "temporarily disable app layouts"; AeroSpace's popularity is built on a config file and CLI |
| **Reliability** | Rectangle Pro #353 (22 comments, snap areas broken after an update), #134 (stash lost on wake), #691, #856 (settings freezes); Rectangle #640, #1325 (Sonoma window IDs), many Stage Manager issues |
| **Stash as a real workflow** | Rectangle Pro "Stash Window Enhancements" (2↑, 9 comments), #512 stash presets, stash inside layouts bug |

---

## 3. Differentiation opportunities

Scores run from 1 to 3. **Need** is how strong the evidence is. **Unique** is how rare the feature is among snapping and throwing tools. **Fit** is how much of it Fling already has, so higher means cheaper.

### A. Display- and Space-aware memory ("Stay, built in"): Need 3 · Unique 3 · Fit 2 · **Effort M**
> **Status: done for displays; Spaces not done.** `DisplayMemory.swift` keys window positions by display setup (display IDs, arrangement and resolution), records after Fling actions, after drags and every 30 s, and restores on display changes and wake (layouts triggered by the same change still run afterwards). Reopened apps' windows return to their last spot. It's on by default, with a toggle and "Forget Remembered Positions" in Settings → General. Live-tested with `make smoke`. **Not done:** Spaces. Restoring windows to other Spaces would mean switching your view between them, so memory only covers the current Space.

- **What it is:** Fling quietly learns where every app's windows sit **for each display configuration** (the set of connected display IDs plus their arrangement) and for each Space. When a display is plugged in or unplugged, or the Mac wakes, it puts windows back for that configuration with no setup. Named layouts stay available as manual overrides.
- **Why it's different:** Stay does the memory but isn't a window manager and can't handle Spaces. Moom, Rectangle and Magnet ignore it. Rectangle Pro needs manual layouts with display triggers.
- **What Fling had before this was built:** a 15-second per-display snapshot that restored on reconnect (since replaced), layouts with display and wake triggers, and a watcher for new windows.
- **How to build it:**
  - Key snapshots by a configuration fingerprint: the sorted `CGDisplayCreateUUIDFromDisplayID` values plus their frames.
  - Snapshot when a Fling action runs or a drag ends, not only on a timer.
  - Match windows after relaunch by bundle ID and title, using `LayoutEntry.match`.
  - Reading a window's Space is possible without SIP changes through private `CGSCopySpacesForWindows`. Moving windows between Spaces uses the title-bar drag trick Fling already has.
- **Risk:** the Spaces APIs are private and change between macOS versions. Ship per-display memory first and Spaces second.

### B. Snap Assist for normal windows: Need 2 · Unique 3 · Fit 3 · **Effort M**
> **Status: done.** `SnapAssist.swift`: after a snap by keyboard, drag, throw or the keyboard grid, a panel in the largest empty strip lists up to 9 other windows (icon and title, so no Screen Recording). Click one or press 1–9 to fill the space; Esc, another key or a click elsewhere dismisses it. Respects gaps and Pin Mode. On by default. Live thumbnails weren't built.

- **What it is:** after a snap that leaves free space (left half, a third, a corner), show a panel of the other visible windows in that free area. Click one or press its number to fill the rest. Esc dismisses it.
- **Why it's different:** macOS only does this in full-screen Split View, and it's an open request in Loop. Windows users moving to Mac expect it.
- **How to build it:**
  - Free area: `fillFrame` and `tileFrames` already exist.
  - Candidate windows: `Window.visible()`.
  - Use **app icons and titles, not thumbnails**, to avoid asking for Screen Recording permission. Live thumbnails via ScreenCaptureKit can be an opt-in.
  - Reuse `SnapPanel`'s click-through panel style.

### C. Keyboard grid (Tactile-style): Need 2 · Unique 3 · Fit 3 · **Effort S**
> **Status: done, with a fixed grid.** `KeyboardGrid.swift` (⌃⌥⌘G): a 4×3 lettered grid (Q W E R / A S D F / Z X C V, by key position so any keyboard layout works). Two letters span the window, and it respects gaps and Pin Mode. Live-tested. **Not done:** custom grid sizes and row/column weights per display.

- **What it is:**
  - A hotkey shows a translucent lettered grid over the focused window's screen (Q W E R / A S D F / Z X C V).
  - Typing two letters places the window across that span, and typing one letter twice fills a single cell.
  - Row and column weights and grid size can be set per display.
- **Why it's different:** it's the #1 open request in Rectangle Pro's tracker. Rectangle and Loop don't have it, and it covers every custom size without memorizing shortcuts.
- **How to build it:** an `Overlay` or `NSPanel` grid plus a local key monitor (temporary key capture, like `ShortcutRecorder`). The frame math is the existing `grid()` helper. Add a tested pure function that maps two letters to a frame.

### D. Automation surface (CLI, config file, Shortcuts recipes): Need 2 · Unique 2 · Fit 3 · **Effort S–M**
> **Status: done.**
> - **`flingctl`**, a command-line tool talking to Fling over a Unix socket: any action (optionally `--app`), `frame X Y W H`, custom positions, `layout` and `save-layout`, listings of actions, layouts, customs, windows and displays (with `--json`), and `config export` / `config import`. It returns non-zero exit codes with the Diagnostics reason, and `make install-cli` installs it.
> - **`~/.config/fling/config.json`**, kept in sync both ways (edits reload within about 2 s).
> - **`fling://save-layout`** URL, and `fling://` URLs now share flingctl's parser.
> - **README recipes** for Focus modes, app, time and Wi-Fi automations.
>
> **Not done:** native App Intents.

- **What it is:**
  - `fling` CLI commands, e.g. `fling layout apply Work` or `fling move --app Safari --to left-half --display 2`.
  - An optional config file at `~/.config/fling/config.json` that Fling watches, so setups can live in dotfiles.
  - Documented **Shortcuts automations**: "When Focus turns on → Open URL `fling://execute-layout?name=Focus`". Focus and calendar triggers need no new code because the URL scheme already exists.
- **Why it's different:** Rectangle Pro only has a URL scheme. AeroSpace shows how much this audience values config files and a CLI.
- **How to build it:**
  - The CLI can be a small command in the same package that opens `fling://` URLs, or talks over a Unix socket when it needs replies (e.g. `fling query windows`).
  - The config file is `Config.encoded()` plus an `NSFilePresenter` watch.
- **Risk:** native App Intents (Fling actions appearing directly in Shortcuts) need Xcode's metadata step, which SwiftPM with Command Line Tools may not run. Start with URL-based recipes.

### E. Visible reliability: Need 3 · Unique 2 · Fit 3 · **Effort S**
> **Status: mostly done.** Settings → Diagnostics shows the last 100 actions with plain-language reasons (AX errors such as missing permission, unresponsive app, window that can't be moved or no longer exists; and the app keeping a different size or position) plus **Copy Report**. `make smoke` runs 43 live checks against a throwaway test window. **Not done:** CI publishing smoke results (it needs a Mac with Accessibility granted).

- **What it is:**
  - A **Diagnostics** pane: last 50 actions, each with the target window, AX result codes and why it failed (fixed-size window, AX timeout, app doesn't support Accessibility, full-screen Space).
  - A "copy report" button.
  - Publish `make smoke` results in CI on each release.
- **Why it's different:** competitors' trackers are full of "stopped working" reports with no way to tell why. Being open source *plus* explaining failures builds trust Rectangle Pro can't copy.
- **How to build it:** `Window.setFrame` already knows the AX result; record it. Re-check the frame after setting it to detect clamping.

### F. Always on top / floating windows: Need 3 · Unique 2 · Fit 1 · **Effort M–L**
> **Status: done, with limits.** `FloatingWindows.swift` (⌃⌥⌘P, plus Unfloat All): a 30 fps ScreenCaptureKit mirror in a floating panel that follows the window. It hides while that app is in front, has adjustable opacity, and needs Screen Recording. **Limits:** the first click on the mirror only brings the real window forward (not passed through), there's no click-through mode, and it's not yet tried on screen (the smoke check is skipped until Screen Recording is granted).

- **What it is:** pin any window above the rest, with optional opacity and click-through.
- **Why it's different:** it's the most-voted AeroSpace request and appears in Loop and Rectangle Pro trackers. Right now it requires a separate paid app.
- **How to build it:** macOS won't let one app raise another app's window level, so the SIP-free method is a **ScreenCaptureKit mirror**: a floating `NSPanel` shows a live capture of the window and forwards clicks. This needs Screen Recording permission. Nobody can pin true full-screen windows.
- **Recommendation:** worth doing, but after A–E. It's a mini-app of its own and needs another permission.

### G. Power-user triggers: Need 2 · Unique 2 · Fit 2 · **Effort S–M**
> **Status: mostly done.** Left/right-specific shortcuts are recorded when the Settings → Shortcuts option is on and handled by the event tap (shown as ‹⌘ / ⌘›). Portrait displays have their own snap areas and throw positions. **Not done:** Caps Lock / Hyper as a trigger (needs key remapping), and profiles per individual display or ultrawide aspect ratio.

- **Left vs right modifiers** (e.g. right ⌘ + arrows) and **Caps Lock / Hyper** as a trigger. Carbon hotkeys can't tell left from right, but Fling's event tap can read the device-specific flag bits.
- **Profiles for each display's shape:** separate snap areas, throw positions and grid per display or per aspect ratio (ultrawide or portrait).

### H. Stash as a workflow: Need 2 · Unique 2 · Fit 3 · **Effort S**
> **Status: partly done.** Stashed windows are tucked away again after sleep and display changes (live-tested), with Stash All, All Except Front, Toggle, Cycle, color tabs, reveal delay and ⌘-only reveal. **Not done:** surviving a Fling relaunch, stash as a layout entry, and stashing all windows of one app.

- Stashed windows survive sleep, relaunch and display changes (Rectangle Pro #134).
- Stash can be a layout entry action, such as "Slack stashed on the right".
- Stash all windows of one app.

### I. AI arrangements: Need 1 · Unique 1 · Fit 2 · **Effort M**
> **Status: not started** (deliberately).

BetterStage already sells plain-language arrangements as a subscription. Fling could do the same with a model the user brings, turning a prompt into a layout JSON. However, the trackers show little demand, so it's **not a lead differentiator**. Revisit once A–D exist, since AI mainly needs a good layout model underneath.

---

## 4. Where not to compete

- **Basic halves and quarters.** Apple ships them, and Rectangle is free.
- **Full automatic tiling (i3/BSP).** AeroSpace and yabai own that audience, and it's a different product. Fling's resizing of neighbors and Snap Assist give "tiling when you want it" without switching models.
- **Gesture breadth (30 gestures).** Swish owns this. Fling's throw and trackpad trigger are enough.
- **AI as the headline.** See I.

---

## 5. Positioning, price and distribution

- **Price:** free and open source. Rectangle Pro is $9.99 and closed, Loop is free but has fewer keyboard features, and Stay is now free. "Everything Rectangle Pro does, open, plus memory" is a clear pitch.
- **License:** MIT (chosen 2026-09-14). Fling's code is original, and MIT lets people fork it and use it commercially.
- **Distribution is a real hurdle:** a self-signed build is blocked by Gatekeeper on other Macs. Install without friction needs a **Developer ID certificate and notarization** ($99/year Apple Developer Program), or at least a Homebrew cask with instructions.
- The private MultitouchSupport use, plus Accessibility and event taps, rule out the Mac App Store, which is normal for this category.

---

## 6. Suggested roadmap

**Status (2026-09-14):**

1. **Quick wins:** ✅ keyboard grid (C), ✅ stash re-tucked after sleep (H), ✅ diagnostics pane (E), ✅ Shortcuts/URL recipes (D).
2. **Signature feature:** ✅ display-configuration memory (A). ⬜ Spaces awareness.
3. **Differentiated polish:** ✅ Snap Assist (B), ✅ portrait profiles and left/right modifiers (G). ⬜ Profiles per display or ultrawide, Caps Lock / Hyper.
4. **Later:** ✅ `flingctl` and the dotfile config (D), ✅ always on top via ScreenCaptureKit (F). ⬜ AI arrangements (I).
5. **Before announcing:** ⬜ notarized builds, ⬜ a demo GIF of Snap Assist and the grid, ⬜ a comparison table against Rectangle Pro, Loop and Stay, ✅ MIT license.

✅ items are covered by `make test` unit tests, `make smoke` live checks, or both. Float on Top's live check waits for Screen Recording permission. Things that need a person (drag snapping, throws, the trackpad, hovering a stash edge, clicking Snap Assist, pressing right-⌘ shortcuts, plugging in displays) haven't been tried on screen.

---

## Sources

- Rectangle issues, sorted by 👍: https://github.com/rxhanson/Rectangle/issues
- Rectangle Pro Community issues and discussions: https://github.com/rxhanson/RectanglePro-Community
- Loop issues: https://github.com/MrKai77/Loop/issues
- AeroSpace issues: https://github.com/nikitabobko/AeroSpace/issues
- Macworld, Sequoia tiling limitations: https://www.macworld.com/article/2365751/macos-sequoia-windows-tiling-dont-ditch-that-tiling-app.html
- Rectangle vs Sequoia tiling: https://sites.google.com/view/rectangle-app/rectangle-vs-macos-sequoia-tiling
- macOS Tahoe window management guide: https://macos-tahoe.com/blog/macos-tahoe-window-management-complete-guide-2025/
- Reddit consensus summary (Loop, Moom, Raycast, Magnet): https://www.brnsft.com/blog/xs9bo75mhvor8vzzrlg2a4uwv8cikl (taken from the search result excerpt; the page returned 404 when fetched directly)
- macOS WM directory (96 tools): https://macoswm.com/
- Swish reviews: https://www.producthunt.com/products/swish/reviews
- Stay FAQ and status: https://cordlessdog.com/stay/documentation/faq/
- MPU thread, Stay alternatives: https://talk.macpowerusers.com/t/alternative-to-stay-by-cordless-dog/17832
- BetterStage (AI Staging, pricing, comparison): https://betterstage.app/best-macos-window-manager
- Always-on-top landscape 2025: https://medium.com/@ayincat/the-2025-macos-always-on-top-landscape-what-actually-works-and-what-doesnt-floaty-for-macos-2a1aedda7911
- GNOME Tactile: https://extensions.gnome.org/extension/4548/tactile/
- Snap Assist alternatives: https://alternativeto.net/software/snap-assist/
