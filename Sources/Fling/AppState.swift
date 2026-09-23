import AppKit
import SwiftUI

/// True when this process is `Fling --smoke-test …`: a second instance running beside the user's own, so it
/// takes no hotkeys, no event tap and no config files, and serves flingctl on its own socket.
let smokeTesting = CommandLine.arguments.contains("--smoke-test")

@MainActor @Observable
final class AppState {
    var shortcuts: [Action: Shortcut] {
        didSet {
            if !reloading { Store.save(ShortcutStorage.dictionary(shortcuts), key: "shortcuts.v2") }
            registerHotkeys()
        }
    }
    var customActions: [CustomAction] {
        didSet {
            if !reloading { Store.save(customActions, key: "customActions") }
            registerHotkeys()
        }
    }
    var layouts: [Layout] {
        didSet {
            if !reloading { Store.save(layouts, key: "layouts") }
            registerHotkeys()
        }
    }
    /// Set while values loaded from disk are being applied. Saving those again would write what this process
    /// read back over whatever the other one has written since — recording a shortcut saves twice (it takes the
    /// keys from their old action first), and a write-back landing between the two lost the new shortcut.
    @ObservationIgnored private var reloading = false
    /// Hotkeys pause while keys are being captured (the shortcut recorder). In the Settings helper the hotkeys
    /// belong to the engine, so it's told to pause instead.
    var capturingKeys = false {
        didSet {
            if SettingsHelper.isHelper {
                SettingsHelper.send(["capture-keys", capturingKeys ? "on" : "off"])
            } else {
                registerHotkeys()
            }
        }
    }

    @ObservationIgnored let stash = Stash()
    // ponytail: keyed by live AX elements and never pruned; prune on window close if they grow.
    @ObservationIgnored private var restoreFrames: [AXUIElement: CGRect] = [:]
    /// Where every window sat before the last layout ran, so Undo Layout can put them back. One snapshot,
    /// replaced each time a layout runs and dropped once it's used: a few KB, in memory only.
    @ObservationIgnored private var layoutUndo: (layout: UUID, frames: [(window: Window, frame: CGRect)], hidden: [pid_t])?
    @ObservationIgnored private var lastPlacement: [AXUIElement: Action] = [:]
    @ObservationIgnored private var last: (key: String, element: AXUIElement, frame: CGRect, count: Int)?
    @ObservationIgnored private var gestures: Gestures?
    @ObservationIgnored private var screenCount = NSScreen.screens.count
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private(set) var cloudSync: ConfigFileSync?
    @ObservationIgnored private(set) var configFile: ConfigFileSync?
    @ObservationIgnored private var windowWatcher: WindowWatcher?
    @ObservationIgnored private(set) var contextMenu: ContextMenu?
    @ObservationIgnored private(set) var keyboardGrid: KeyboardGrid?
    @ObservationIgnored private(set) var fillRest: FillRest?
    @ObservationIgnored private(set) var floating: FloatingWindows?
    @ObservationIgnored private var commandServer: CommandServer?
    /// Recent placements and failures, newest last, shown in Settings → Diagnostics.
    var diagnostics: [DiagnosticEntry] = []
    @ObservationIgnored private var lastVisibleFrames = Screen.all().map(\.visible)
    @ObservationIgnored private var lastDisplayKey = DisplayMemoryStore.key(for: Screen.all())
    @ObservationIgnored private(set) var displayMemory: DisplayMemory?

    init() {
        Prefs.register()
        // Shows the system Accessibility prompt if Fling isn't trusted yet.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        // Version 1 saved every action, with nil for any without a shortcut, which would hide new defaults.
        // Keep only its real shortcuts; the next save writes version 2 (differences from the defaults).
        let legacy = (Store.load("shortcuts") as [String: Shortcut?]?)?.filter { $0.value != nil }
        shortcuts = ShortcutStorage.merged(saved: Store.load("shortcuts.v2") ?? legacy ?? [:])
        customActions = Store.load("customActions") ?? []
        layouts = Store.load("layouts") ?? []
        if legacy != nil {
            Store.save(ShortcutStorage.dictionary(shortcuts), key: "shortcuts.v2")
            UserDefaults.standard.removeObject(forKey: "shortcuts")
        }
        // The Settings helper edits the same stored configuration, but runs no engine: see SettingsHelper.
        if SettingsHelper.isHelper {
            watchSettingsChanges()
            return
        }
        registerHotkeys()
        observeTriggers()
        if !smokeTesting {
            gestures = Gestures(state: self)
            cloudSync = ConfigFileSync(state: self, url: ConfigFileSync.iCloudURL, enabledKey: Prefs.iCloudSync, pollInterval: 30)
            configFile = ConfigFileSync(state: self, url: ConfigFileSync.dotfileURL, enabledKey: Prefs.configFile, pollInterval: 2)
        }
        windowWatcher = WindowWatcher { [weak self] in self?.windowOpened($0) }
        contextMenu = ContextMenu(state: self)
        keyboardGrid = KeyboardGrid(state: self)
        fillRest = FillRest(state: self)
        floating = FloatingWindows(state: self)
        commandServer = CommandServer { [weak self] args, cwd in
            self?.runCommand(args, workingDirectory: cwd) ?? (false, "Fling is quitting.")
        }
        displayMemory = DisplayMemory(state: self)
    }

    // MARK: Configuration

    func exportConfig() -> Data? {
        Config(shortcuts: ShortcutStorage.dictionary(shortcuts), customActions: customActions,
               layouts: layouts, preferences: Prefs.snapshot()).encoded()
    }

    /// Replaces shortcuts, custom positions, layouts and settings. Returns false for unreadable data.
    @discardableResult
    func importConfig(_ data: Data) -> Bool {
        guard let config = Config.decode(data) else { return false }
        shortcuts = ShortcutStorage.merged(saved: config.shortcuts)
        customActions = config.customActions
        layouts = config.layouts
        Prefs.restore(config.preferences)
        return true
    }

    // MARK: The Settings helper and the engine

    /// In the helper: every setting lands in UserDefaults, so one watcher covers them all. The engine can't see
    /// another process's writes (it gets the new values when it reads them, but no notification), so it's told.
    private func watchSettingsChanges() {
        var pending: Task<Void, Never>?
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    pending?.cancel()
                    pending = Task {
                        try? await Task.sleep(for: .milliseconds(300)) // one reload for a burst of edits
                        if !Task.isCancelled { SettingsHelper.send(["reload"]) }
                    }
                }
            })
    }

    /// In the engine: picks up what the helper wrote and applies the parts that need to run here.
    func reloadConfiguration() {
        reloading = true
        shortcuts = ShortcutStorage.merged(saved: Store.load("shortcuts.v2") ?? [:])
        customActions = Store.load("customActions") ?? []
        layouts = Store.load("layouts") ?? []
        reloading = false
        cloudSync?.enabledChanged()
        configFile?.enabledChanged()
        if UserDefaults.standard.bool(forKey: Prefs.pinEnabled) { reflowPin() }
        // @AppStorage ignores another process's writes; writing the same value here is a local change it does see,
        // so the menu bar icon appears or disappears right away.
        let showsIcon = UserDefaults.standard.bool(forKey: Prefs.showMenuBarIcon)
        UserDefaults.standard.set(showsIcon, forKey: Prefs.showMenuBarIcon)
    }

    /// In the helper: re-reads what the engine changed (it saved a layout, or the config file sync brought something in).
    func reloadFromStore() {
        reloading = true
        defer { reloading = false }
        let saved: [String: Shortcut] = Store.load("shortcuts.v2") ?? [:]
        let merged = ShortcutStorage.merged(saved: saved)
        if merged != shortcuts { shortcuts = merged }
        let customs: [CustomAction] = Store.load("customActions") ?? []
        if customs != customActions { customActions = customs }
        let savedLayouts: [Layout] = Store.load("layouts") ?? []
        if savedLayouts != layouts { layouts = savedLayouts }
    }

    /// Drops every remembered window position. The helper asks the engine, which holds them.
    func forgetRememberedPositions() {
        if SettingsHelper.isHelper {
            SettingsHelper.send(["forget-positions"])
        } else {
            displayMemory?.forgetAll()
        }
    }

    /// In the helper: the engine's recent placements, for the Diagnostics tab.
    func refreshDiagnostics() async {
        guard let json = await SettingsHelper.reply(to: ["diagnostics", "--json"]),
              let entries = try? JSONDecoder().decode([DiagnosticEntry].self, from: Data(json.utf8)) else { return }
        diagnostics = entries
    }

    func clearDiagnostics() {
        diagnostics.removeAll()
        if SettingsHelper.isHelper { SettingsHelper.send(["clear-diagnostics"]) }
    }

    // MARK: Shortcuts & URLs

    func binding(for action: Action) -> Binding<Shortcut?> {
        Binding(get: { self.shortcuts[action] },
                set: { self.releaseKeys(of: $0); self.shortcuts[action] = $0 })
    }

    func binding(forCustom id: UUID) -> Binding<Shortcut?> {
        Binding(get: { self.customActions.first { $0.id == id }?.shortcut },
                set: { new in
                    self.releaseKeys(of: new)
                    if let i = self.customActions.firstIndex(where: { $0.id == id }) { self.customActions[i].shortcut = new }
                })
    }

    func binding(forLayout id: UUID) -> Binding<Shortcut?> {
        Binding(get: { self.layouts.first { $0.id == id }?.shortcut },
                set: { new in
                    self.releaseKeys(of: new)
                    if let i = self.layouts.firstIndex(where: { $0.id == id }) { self.layouts[i].shortcut = new }
                })
    }

    /// A key combination belongs to one command, so assigning it takes it from any other.
    private func releaseKeys(of shortcut: Shortcut?) {
        guard let shortcut else { return }
        if shortcuts.values.contains(where: { $0.sameKeys(as: shortcut) }) {
            shortcuts = shortcuts.filter { !$0.value.sameKeys(as: shortcut) }
        }
        for i in customActions.indices where customActions[i].shortcut?.sameKeys(as: shortcut) == true {
            customActions[i].shortcut = nil
        }
        for i in layouts.indices where layouts[i].shortcut?.sameKeys(as: shortcut) == true {
            layouts[i].shortcut = nil
        }
    }

    func handle(_ url: URL) {
        guard let arguments = commandArguments(for: url) else { return NSLog("Fling: unrecognized URL \(url)") }
        let result = runCommand(arguments, workingDirectory: NSHomeDirectory())
        if !result.ok { NSLog("Fling: \(url): \(result.output)") }
    }

    private func registerHotkeys() {
        guard !smokeTesting else { return } // the user's own Fling keeps the shortcuts during a smoke test
        guard !SettingsHelper.isHelper else { return } // the engine holds the hotkeys; watchSettingsChanges tells it to reload
        Hotkeys.unregisterAll()
        guard !capturingKeys else { return }
        for (action, shortcut) in shortcuts {
            let repeats = [.nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown, .larger, .smaller].contains(action)
            Hotkeys.register(shortcut, repeats: repeats) { [weak self] in self?.perform(action) }
        }
        for custom in customActions {
            guard let shortcut = custom.shortcut else { continue }
            Hotkeys.register(shortcut) { [weak self] in self?.perform(custom: custom.id) }
        }
        for layout in layouts {
            guard let shortcut = layout.shortcut else { continue }
            Hotkeys.register(shortcut) { [weak self] in self?.applyOrUndo(layout: layout.id) }
        }
    }

    // MARK: Actions

    /// Runs an action on a window (the focused one by default), optionally on a specific screen.
    func perform(_ action: Action, on given: Window? = nil, screen: Int? = nil) {
        switch action {
        case .unstashAll: return stash.unstashAll()
        case .unfloatAll: return floating?.unfloatAll() ?? ()
        case .stashAll: return stash.stashAll(exceptFocused: false)
        case .stashAllExceptFront: return stash.stashAll(exceptFocused: true)
        case .toggleStashed: return stash.toggleAll()
        case .cycleStashed: return stash.cycle()
        case .showMenu: return contextMenu?.show(for: Window.focused(), at: CGEvent(source: nil)?.location ?? .zero) ?? ()
        case .togglePin: return togglePin()
        case .reflowPin: return reflowPin()
        case .tile2x2, .tile2x3, .cascadeAll, .cascadeApp, .appLeftHalf, .appRightHalf: return arrange(action)
        case .undoLayout: return undoLayout()
        default: break
        }
        guard let window = given ?? Window.focused() else {
            log(action.title, problem: "No focused window to act on")
            return NSSound.beep()
        }
        switch action {
        case .keyboardGrid:
            return keyboardGrid?.show(for: window) ?? ()
        case .floatOnTop:
            return floating?.toggle(window) ?? ()
        case .winArrowLeft, .winArrowRight, .winArrowUp, .winArrowDown:
            guard let frame = window.frame else {
                log(action.title, window: window, problem: Self.unreadableFrame)
                return NSSound.beep()
            }
            let current = Action.allCases.filter { $0.category == .halves || $0.category == .corners || $0 == .maximize }
                .first { target(for: $0, window: window, frame: frame)?.isClose(to: frame) == true }
            return perform(winArrowAction(action, from: current) ?? .restore, on: window, screen: screen)
        case .stashLeft: return stash.stash(window, to: .left)
        case .stashRight: return stash.stash(window, to: .right)
        case .nextSpace, .previousSpace:
            stash.forget(window)
            Task { await window.moveToAdjacentSpace(right: action == .nextSpace) }
            return
        default: break
        }
        if window.performControl(action) { return }
        guard let frame = window.frame else {
            log(action.title, window: window, problem: Self.unreadableFrame)
            return NSSound.beep()
        }

        // Repeating a half action on a window that hasn't moved since cycles its size.
        let cycles = action.category == .halves && UserDefaults.standard.bool(forKey: Prefs.cycleHalves)
        let count = cycles ? repeatCount(action.rawValue, window, frame) : 0
        guard let target = target(for: action, window: window, frame: frame, screen: screen, repeatCount: count) else {
            // No beep: double-clicking a title bar or Win Arrow Down restores windows Fling never moved.
            return log(action.title, window: window,
                       problem: action == .restore ? "Nothing to restore: Fling hasn't moved this window" : "No display found")
        }

        if action == .restore { restoreFrames[window.element] = nil }
        place(window, from: frame, to: target, key: action.rawValue, count: count, rememberRestore: action != .restore)
        lastPlacement[window.element] = action.placesWindow ? action : nil
        if [.halves, .corners, .thirds, .fourths, .sixths, .fill].contains(action.category) {
            fillRest?.offer(after: window, placedAt: target)
        }

        // Keyboard and menu commands that send a window to another display bring the cursor along.
        let visibles = Screen.all().map(\.visible)
        if given == nil, UserDefaults.standard.bool(forKey: Prefs.moveCursorWithWindow),
           screenIndex(for: frame, in: visibles) != screenIndex(for: target, in: visibles) {
            CGWarpMouseCursorPosition(CGPoint(x: target.midX, y: target.midY))
        }
    }

    func perform(custom id: UUID, on given: Window? = nil) {
        guard let custom = customActions.first(where: { $0.id == id }) else { return NSSound.beep() }
        guard let window = given ?? Window.focused() else {
            log(custom.name, problem: "No focused window to act on")
            return NSSound.beep()
        }
        guard let frame = window.frame else {
            log(custom.name, window: window, problem: Self.unreadableFrame)
            return NSSound.beep()
        }
        // Repeating the shortcut steps through the entry's extra frames.
        let count = repeatCount(id.uuidString, window, frame)
        guard let target = customFrame(custom, window: window, frame: frame, repeatCount: count) else {
            return log(custom.name, window: window, problem: "No display found")
        }
        place(window, from: frame, to: target, key: id.uuidString, count: count)
        lastPlacement[window.element] = nil
    }

    /// Custom positions marked as snap targets, placed for this window.
    func snapTargets(for window: Window, frame: CGRect) -> [(id: UUID, frame: CGRect)] {
        customActions.filter(\.snapTarget).compactMap { custom in
            customFrame(custom, window: window, frame: frame, repeatCount: 0).map { (custom.id, $0) }
        }
    }

    private func customFrame(_ custom: CustomAction, window: Window, frame: CGRect, repeatCount: Int) -> CGRect? {
        let screens = Screen.all()
        guard !custom.frames.isEmpty, !screens.isEmpty else { return nil }
        let current = screenIndex(for: frame, in: screens.map(\.visible))
        let area = usableArea(screens, custom.display.resolve(current: current, count: screens.count), for: window)
        return custom.frames[repeatCount % custom.frames.count].frame(for: frame, in: area)
    }

    /// Where an action would put the window, without moving it (also used for footprint previews).
    func target(for action: Action, window: Window, frame: CGRect, screen: Int? = nil, repeatCount: Int = 0) -> CGRect? {
        let screens = Screen.all()
        guard !screens.isEmpty else { return nil }
        let current = screenIndex(for: frame, in: screens.map(\.visible))
        switch action {
        case .restore:
            return restoreFrames[window.element]
        case .nextDisplay, .previousDisplay:
            let next = (current + (action == .nextDisplay ? 1 : -1) + screens.count) % screens.count
            return map(frame, from: usableArea(screens, current, for: window), to: usableArea(screens, next, for: window))
        case .fillLeft, .fillRight:
            let gap = CGFloat(UserDefaults.standard.integer(forKey: Prefs.gap))
            let area = usableArea(screens, screen ?? current, for: window)
            let others = Window.visible().filter { $0.element != window.element }.compactMap(\.frame)
            return fillFrame(left: action == .fillLeft, others: others, in: area.insetBy(dx: gap / 2, dy: gap / 2))
                .insetBy(dx: gap / 2, dy: gap / 2)
        default:
            let gap = CGFloat(UserDefaults.standard.integer(forKey: Prefs.gap))
            let area = usableArea(screens, screen ?? current, for: window)
            return action.frame(for: frame, in: area, gap: gap, repeatCount: repeatCount)
        }
    }

    /// Tiling, cascading and app-wide halves, on the focused window's screen.
    private func arrange(_ action: Action) {
        let screens = Screen.all()
        guard !screens.isEmpty else { return }
        let visibles = screens.map(\.visible)
        let index = Window.focused()?.frame.map { screenIndex(for: $0, in: visibles) } ?? 0
        let area = usableArea(screens, index, for: nil)
        let gap = CGFloat(UserDefaults.standard.integer(forKey: Prefs.gap))
        let pinned = UserDefaults.standard.bool(forKey: Prefs.pinEnabled) ? UserDefaults.standard.string(forKey: Prefs.pinBundleID) : nil
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let appOnly = [.cascadeApp, .appLeftHalf, .appRightHalf].contains(action)

        let windows = Window.visible().filter { window in
            guard let frame = window.frame, screenIndex(for: frame, in: visibles) == index else { return false }
            return (!appOnly || window.pid == frontmost) && (pinned == nil || window.bundleID != pinned)
        }
        let placements: [(Window, CGRect)]
        switch action {
        case .tile2x2:
            placements = Array(zip(windows, tileFrames(count: windows.count, columns: 2, rows: 2, in: area, gap: gap)))
        case .tile2x3:
            placements = Array(zip(windows, tileFrames(count: windows.count, columns: 3, rows: 2, in: area, gap: gap)))
        case .cascadeAll, .cascadeApp:
            // Back-most window goes top-left, so the front window stays on top at the end of the cascade.
            let backToFront = Array(windows.reversed())
            placements = Array(zip(backToFront, cascadeFrames(sizes: backToFront.map { $0.frame?.size ?? .zero }, in: area)))
        default:
            let half: Action = action == .appLeftHalf ? .leftHalf : .rightHalf
            placements = windows.map { ($0, half.frame(for: .zero, in: area, gap: gap)) }
        }
        for (window, frame) in placements {
            place(window, from: window.frame ?? frame, to: frame, key: action.rawValue, count: 0)
        }
    }

    /// Dragging a snapped window away gives it back its size from before it was snapped.
    func unsnapped(_ window: Window) {
        guard let saved = restoreFrames.removeValue(forKey: window.element) else { return }
        window.setSize(saved.size)
    }

    private func repeatCount(_ key: String, _ window: Window, _ frame: CGRect) -> Int {
        guard let last, last.key == key, last.element == window.element, last.frame.isClose(to: frame) else { return 0 }
        return last.count + 1
    }

    private func place(_ window: Window, from frame: CGRect, to target: CGRect, key: String, count: Int, rememberRestore: Bool = true) {
        // Restore returns to the frame from before the first Fling action.
        if rememberRestore, restoreFrames[window.element] == nil { restoreFrames[window.element] = frame }
        stash.forget(window)
        let result = window.setFrame(target)
        last = (key, window.element, target, count)

        let actual = window.frame
        let problem: String? = if result != .success {
            describe(result)
        } else if let actual, !actual.isClose(to: target) {
            "The app kept the window at \(Int(actual.width))×\(Int(actual.height)) at (\(Int(actual.minX)), \(Int(actual.minY))) "
                + "instead of \(Int(target.width))×\(Int(target.height)) (a minimum or maximum window size, or a screen edge)"
        } else {
            nil
        }
        log(Action(rawValue: key)?.title ?? titleCase(key), window: window, requested: target, actual: actual, problem: problem)
        displayMemory?.windowsChanged()
    }

    /// Places a window at an exact frame, remembering the old one for Restore.
    func place(_ window: Window, at target: CGRect, key: String) {
        guard let frame = window.frame else {
            return log(Action(rawValue: key)?.title ?? titleCase(key), window: window, problem: Self.unreadableFrame)
        }
        place(window, from: frame, to: target, key: key, count: 0)
        lastPlacement[window.element] = nil
    }

    /// Fill the Rest's space to fill beside a placed window, on that window's screen.
    func freeArea(beside frame: CGRect, window: Window) -> CGRect? {
        let gap = CGFloat(UserDefaults.standard.integer(forKey: Prefs.gap))
        return usableArea(for: window, frame: frame).flatMap { fillRestArea(placed: frame, in: $0, gap: gap) }
    }

    /// The usable area of the screen a window is on (Pin Mode's strip excluded).
    func usableArea(for window: Window, frame: CGRect) -> CGRect? {
        let screens = Screen.all()
        guard !screens.isEmpty else { return nil }
        return usableArea(screens, screenIndex(for: frame, in: screens.map(\.visible)), for: window)
    }

    func log(_ command: String, window: Window? = nil, requested: CGRect? = nil, actual: CGRect? = nil, problem: String?) {
        let app = window.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName } ?? "—"
        diagnostics.append(DiagnosticEntry(command: command, app: app, window: window?.title ?? "",
                                           requested: requested, actual: actual, problem: problem))
        if diagnostics.count > 100 { diagnostics.removeFirst(diagnostics.count - 100) }
    }

    private static let unreadableFrame = "Couldn't read the window's frame; the app may not support Accessibility"

    private func describe(_ error: AXError) -> String {
        switch error {
        case .apiDisabled: "Accessibility permission is missing"
        case .cannotComplete: "The app didn't respond (it may be busy or hung)"
        case .attributeUnsupported, .actionUnsupported: "This window can't be moved or resized"
        case .notImplemented: "The app doesn't support Accessibility"
        case .invalidUIElement: "The window no longer exists"
        default: "Accessibility error \(error.rawValue)"
        }
    }

    // MARK: Pin Mode

    /// The screen's usable frame: Pin Mode's strip is reserved for the pinned app on the primary display.
    private func usableArea(_ screens: [Screen], _ index: Int, for window: Window?) -> CGRect {
        let screen = screens[index]
        guard let pin = pinArea(screen), window?.bundleID != UserDefaults.standard.string(forKey: Prefs.pinBundleID) else {
            return screen.visible
        }
        return pin.rest
    }

    private func pinArea(_ screen: Screen) -> (pinned: CGRect, rest: CGRect)? {
        let defaults = UserDefaults.standard
        guard screen.isPrimary, defaults.bool(forKey: Prefs.pinEnabled),
              !(defaults.string(forKey: Prefs.pinBundleID) ?? "").isEmpty else { return nil }
        return pinSplit(screen.visible, width: defaults.string(forKey: Prefs.pinWidth) ?? "1/4",
                        right: defaults.bool(forKey: Prefs.pinRight))
    }

    private func togglePin() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Prefs.pinEnabled), (defaults.string(forKey: Prefs.pinBundleID) ?? "").isEmpty {
            guard let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
            defaults.set(frontmost, forKey: Prefs.pinBundleID)
        }
        defaults.set(!defaults.bool(forKey: Prefs.pinEnabled), forKey: Prefs.pinEnabled)
        reflowPin()
    }

    /// Puts the pinned app into its strip and slides other windows out of it.
    func reflowPin() {
        guard !SettingsHelper.isHelper else { return SettingsHelper.send(["reflow-pin"]) }
        guard let screen = Screen.all().first(where: \.isPrimary), let area = pinArea(screen),
              let pinnedID = UserDefaults.standard.string(forKey: Prefs.pinBundleID) else { return }
        for app in regularApps() {
            for window in Window.all(of: app.processIdentifier) {
                guard let frame = window.frame else { continue }
                if app.bundleIdentifier == pinnedID {
                    window.setFrame(area.pinned)
                } else if frame.intersects(area.pinned) {
                    window.setFrame(clamp(frame, into: area.rest))
                }
            }
        }
    }

    // MARK: Layouts

    /// Saves every visible window as a layout; an existing layout with the same name is replaced (keeping its settings).
    func saveCurrentLayout(name: String? = nil) {
        // Only the engine can see the windows; it saves the layout, then the helper re-reads it.
        if SettingsHelper.isHelper {
            Task {
                _ = await SettingsHelper.reply(to: ["save-layout"] + (name.map { [$0] } ?? []))
                reloadFromStore()
            }
            return
        }
        let screens = Screen.all()
        guard !screens.isEmpty else { return }
        var entries: [LayoutEntry] = []
        for app in regularApps() {
            guard let bundleID = app.bundleIdentifier else { continue }
            for window in Window.all(of: app.processIdentifier) {
                guard let frame = window.frame else { continue }
                let index = screenIndex(for: frame, in: screens.map(\.visible))
                var entry = LayoutEntry(bundleID: bundleID, appName: app.localizedName ?? bundleID, title: window.title)
                entry.display = .index(index)
                // Prefer the Fling action that placed the window, so the layout adapts to other screen sizes.
                if let action = lastPlacement[window.element],
                   target(for: action, window: window, frame: frame, screen: index)?.isClose(to: frame) == true {
                    entry.action = action
                } else {
                    entry.frame = .absolute(frame, in: screens[index].visible)
                }
                entries.append(entry)
            }
        }
        if let name, let index = layouts.firstIndex(where: { $0.name == name }) {
            layouts[index].entries = entries
        } else {
            layouts.append(Layout(name: name ?? "Layout \(layouts.count + 1)", entries: entries))
        }
    }

    /// The layout's shortcut: apply it, or put things back when it's already in effect and set to toggle.
    func applyOrUndo(layout id: UUID) {
        if layoutUndo?.layout == id, layouts.first(where: { $0.id == id })?.shortcutToggles == true {
            undoLayout()
        } else {
            apply(layout: id)
        }
    }

    /// Puts every window back where it was before the last layout ran, and unhides whatever that layout hid.
    func undoLayout() {
        guard let undo = layoutUndo else {
            log(Action.undoLayout.title, problem: "No layout has run since Fling started, so there's nothing to undo")
            return NSSound.beep()
        }
        layoutUndo = nil
        for (window, frame) in undo.frames where window.frame != nil { // windows closed since then just drop out
            place(window, at: frame, key: Action.undoLayout.rawValue)
        }
        undo.hidden.compactMap { NSRunningApplication(processIdentifier: $0) }.forEach { $0.unhide() }
    }

    func apply(layout id: UUID, launchMissing: Bool = true) {
        let screens = Screen.all()
        guard let layout = layouts.first(where: { $0.id == id }), !screens.isEmpty else { return }
        guard !SettingsHelper.isHelper else { return SettingsHelper.send(["layout", layout.name]) }
        // Snapshot before anything moves, on the first pass only: the re-apply after launching apps must not
        // overwrite it with the half-arranged state. Triggered layouts (wake, display changes) come through here too.
        if launchMissing {
            layoutUndo = (id, Window.visible().compactMap { w in w.frame.map { (w, $0) } }, [])
        }
        var launched = false
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let bundleIDs = Set(layout.entries.map(\.bundleID)).filter { !layout.frontmostAppOnly || $0 == frontmost }

        for bundleID in bundleIDs {
            let entries = layout.entries.filter { $0.bundleID == bundleID }
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
                if launchMissing, layout.launchApps, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    launched = true
                }
                continue
            }
            if app.isHidden { app.unhide() }
            let windows = Window.all(of: app.processIdentifier)
            let pairs = LayoutEntry.match(entries, titles: windows.map(\.title))
            for (e, w) in pairs {
                place(windows[w], with: entries[e], screens: screens)
            }
            if layout.allMatches {
                for (w, window) in windows.enumerated() where !pairs.contains(where: { $0.window == w }) {
                    if let entry = entries.first(where: { $0.titleMatch == .any || $0.matches(title: window.title) }) {
                        place(window, with: entry, screens: screens)
                    }
                }
            }
            if layout.bringToFront {
                windows.forEach { $0.raise() }
            }
        }

        if layout.hideOtherApps {
            for app in regularApps() where !bundleIDs.contains(app.bundleIdentifier ?? "") {
                if app.hide() { layoutUndo?.hidden.append(app.processIdentifier) }
            }
        }
        if launched {
            // Newly launched apps need a moment to open their windows.
            Task {
                try? await Task.sleep(for: .seconds(3))
                apply(layout: id, launchMissing: false)
            }
        }
    }

    private func place(_ window: Window, with entry: LayoutEntry, screens: [Screen]) {
        guard let frame = window.frame else { return }
        let current = screenIndex(for: frame, in: screens.map(\.visible))
        let display = entry.display.resolve(current: current, count: screens.count)
        let destination = entry.action.flatMap { target(for: $0, window: window, frame: frame, screen: display) }
            ?? entry.frame.frame(for: frame, in: usableArea(screens, display, for: window))
        place(window, from: frame, to: destination, key: "layout", count: 0)
        lastPlacement[window.element] = entry.action
    }

    /// A window was moved or resized by hand: a layout set to snap back puts everything the way it was.
    func windowMovedByHand() {
        guard let undo = layoutUndo, layouts.first(where: { $0.id == undo.layout })?.snapBack == true else { return }
        undoLayout()
    }

    /// A new window goes where an "apply when a window opens" layout says, or else back to its remembered spot.
    private func windowOpened(_ window: Window) {
        let screens = Screen.all()
        guard let bundleID = window.bundleID, !screens.isEmpty else { return }
        for layout in layouts where layout.triggers.contains(.windowOpened) {
            let candidates = layout.entries.filter { $0.bundleID == bundleID }
            if let entry = candidates.first(where: { $0.titleMatch != .loose && $0.matches(title: window.title) })
                ?? candidates.first(where: { $0.titleMatch == .loose || $0.titleMatch == .any }) {
                return place(window, with: entry, screens: screens)
            }
        }
        _ = displayMemory?.windowOpened(window)
    }

    private func observeTriggers() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.displayMemory?.restore(after: 1.5)
                    self?.runLayouts(for: .wake)
                    self?.restashSoon()
                }
            })
    }

    private func screensChanged() {
        let count = NSScreen.screens.count
        let screens = Screen.all()
        let visible = screens.map(\.visible)
        let displayKey = DisplayMemoryStore.key(for: screens)
        defer {
            screenCount = count
            lastVisibleFrames = visible
            lastDisplayKey = displayKey
        }
        if displayKey != lastDisplayKey { displayMemory?.restore(after: 1.5) }
        restashSoon()
        if count > screenCount { runLayouts(for: .displayConnected) }
        if count < screenCount { runLayouts(for: .displayDisconnected) }
        if count == screenCount, visible != lastVisibleFrames, UserDefaults.standard.bool(forKey: Prefs.adjustForDock) {
            followUsableArea(from: lastVisibleFrames, to: visible)
        }
    }

    /// The Dock was shown, hidden or moved: windows flush against a changed edge follow it.
    private func followUsableArea(from old: [CGRect], to new: [CGRect]) {
        let gap = CGFloat(UserDefaults.standard.integer(forKey: Prefs.gap)) / 2
        for window in Window.visible() {
            guard let frame = window.frame else { continue }
            let i = screenIndex(for: frame, in: old)
            guard old[i] != new[i],
                  let target = adjusted(frame, from: old[i].insetBy(dx: gap, dy: gap), to: new[i].insetBy(dx: gap, dy: gap),
                                        tolerance: gap + 2) else { continue }
            window.setFrame(target)
        }
    }

    private func runLayouts(for trigger: Layout.Trigger) {
        let ids = layouts.filter { $0.triggers.contains(trigger) }.map(\.id)
        guard !ids.isEmpty else { return }
        Task {
            try? await Task.sleep(for: .seconds(2.5)) // after the arrangement settles and remembered positions return
            ids.forEach { apply(layout: $0) }
        }
    }

    /// macOS pulls off-screen windows back into view after sleep and display changes; tuck stashed ones away again.
    private func restashSoon() {
        Task {
            try? await Task.sleep(for: .seconds(2))
            stash.reapply()
        }
    }

    private func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != getpid()
        }
    }
}

/// Codable so the Settings helper can read the engine's entries over the flingctl socket.
struct DiagnosticEntry: Identifiable, Codable {
    let id = UUID()
    let date = Date()
    let command: String
    let app: String
    let window: String
    var requested: CGRect?
    var actual: CGRect?
    /// nil when the action worked.
    let problem: String?
}
