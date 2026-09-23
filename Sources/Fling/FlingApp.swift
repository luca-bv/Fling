import SwiftUI

@main
struct FlingApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        // `Fling --settings` is only the Settings window (the delegate opens it), in its own process, so closing it
        // gives the memory back. SceneBuilder takes no conditionals, so the helper drops the menu bar icon instead.
        MenuBarExtra(isInserted: Binding(get: { showMenuBarIcon && !SettingsHelper.isHelper },
                                         set: { showMenuBarIcon = $0 })) {
            MenuContent().environment(delegate.state)
        } label: {
            Image(nsImage: Glyph.menuBar).accessibilityLabel("Fling")
        }
        // Only the helper opens this, and only macOS's own Settings window has the preferences chrome.
        Settings {
            SettingsView().environment(delegate.state)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SettingsHelper.isHelper {
            return SettingsHelper.run { [state] in SettingsView().environment(state) }
        }
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--smoke-test"), i + 1 < args.count else { return }
        Task {
            let passed = await SmokeTest.run(state, bundleID: args[i + 1])
            exit(passed ? 0 : 1)
        }
    }

    /// Quitting Fling takes its Settings window with it.
    func applicationWillTerminate(_ notification: Notification) {
        SettingsHelper.terminate()
    }

    /// Opening Fling again while it runs brings back a hidden menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: Prefs.showMenuBarIcon)
        return true
    }

    /// `fling://` URLs, e.g. `open -g "fling://execute-action?name=left-half"`.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(state.handle)
    }
}

/// UserDefaults keys. Settings views bind to them with @AppStorage; the engine reads them when events arrive.
enum Prefs {
    static let gap = "gap", cycleHalves = "cycleHalves", doubleClickTitleBar = "doubleClickTitleBar"
    static let snapAreas = "snapAreas", snapPanel = "snapPanel", snapHaptics = "snapHaptics"
    static let moveCursorWithWindow = "moveCursorWithWindow", resizeAdjacent = "resizeAdjacent", adjustForDock = "adjustForDock"
    static let showMenuBarIcon = "showMenuBarIcon", contextClickModifiers = "contextClickModifiers"
    static let stashRevealDelay = "stashRevealDelay", stashRevealWithCommand = "stashRevealWithCommand"
    static let displayMemory = "displayMemory", displayMemoryNewWindows = "displayMemoryNewWindows", fillRest = "snapAssist", fillRestHold = "fillRestHold"  // key kept from the old name (Snap Assist) so existing settings survive
    static let recordModifierSides = "recordModifierSides", floatOpacity = "floatOpacity"
    static let throwSafeArea = "throwSafeArea", throwLongDistance = "throwLongDistance"
    static let windowThrow = "windowThrow", throwModifiers = "throwModifiers", throwMouseButton = "throwMouseButton"
    static let throwTrackpadFingers = "throwTrackpadFingers"
    static let quickThrow = "quickThrow", quickThrowModifiers = "quickThrowModifiers"
    static let moveWindow = "moveWindow", moveModifiers = "moveModifiers"
    static let resizeWindow = "resizeWindow", resizeModifiers = "resizeModifiers"
    static let pinEnabled = "pinEnabled", pinBundleID = "pinBundleID", pinWidth = "pinWidth", pinRight = "pinRight"
    static let iCloudSync = "iCloudSync", configFile = "configFile", stashColorTabs = "stashColorTabs"

    static let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// Settings with their defaults; these are what export and sync carry (not the sync switches themselves).
    private static let defaults: [String: Any] = {
        func raw(_ flags: NSEvent.ModifierFlags) -> Int { Int(flags.rawValue) }
        return [
            gap: 0, cycleHalves: true, doubleClickTitleBar: false, snapAreas: true, snapPanel: false, snapHaptics: true,
            moveCursorWithWindow: false, resizeAdjacent: false, adjustForDock: false,
            showMenuBarIcon: true, contextClickModifiers: 0,
            stashRevealDelay: "0", stashRevealWithCommand: false, displayMemory: true, displayMemoryNewWindows: true, fillRest: true, fillRestHold: true, recordModifierSides: false, floatOpacity: 1.0,
            throwSafeArea: 15, throwLongDistance: 150,
            windowThrow: true, throwModifiers: raw([.control, .command]), throwMouseButton: 0, throwTrackpadFingers: 0,
            quickThrow: false, quickThrowModifiers: raw([.control]),
            moveWindow: false, moveModifiers: raw([.control, .shift]),
            resizeWindow: false, resizeModifiers: raw([.control, .option, .shift]),
            pinEnabled: false, pinBundleID: "", pinWidth: "1/4", pinRight: true, stashColorTabs: false,
        ]
        .merging(Dictionary(uniqueKeysWithValues: FillRest.Source.allCases.map {
            ($0.prefKey, $0 != .thrown) // a throw ends with a flick; stopping to pick a window there breaks it
        })) { a, _ in a }
        .merging(Dictionary(uniqueKeysWithValues: [false, true].flatMap { portrait in
            SnapArea.allCases.map { ($0.prefKey(portrait: portrait), $0.defaultSetting) }
        })) { a, _ in a }
        .merging(Dictionary(uniqueKeysWithValues: [false, true].flatMap { portrait in
            (0..<8).flatMap { sector in
                [(ThrowSectors.prefKey(sector: sector, long: false, portrait: portrait), ThrowSectors.short[sector].rawValue),
                 (ThrowSectors.prefKey(sector: sector, long: true, portrait: portrait), ThrowSectors.long[sector].rawValue)]
            }
        })) { a, _ in a }
    }()

    static func register() {
        UserDefaults.standard.register(defaults: defaults.merging([iCloudSync: false, configFile: false]) { a, _ in a })
    }

    static func snapshot() -> [String: Config.Preference] {
        let store = UserDefaults.standard
        return defaults.reduce(into: [:]) { result, entry in
            switch entry.value {
            case is Bool: result[entry.key] = .bool(store.bool(forKey: entry.key))
            case is Int: result[entry.key] = .int(store.integer(forKey: entry.key))
            default: result[entry.key] = .string(store.string(forKey: entry.key) ?? "")
            }
        }
    }

    static func restore(_ preferences: [String: Config.Preference]) {
        let store = UserDefaults.standard
        for (key, value) in preferences {
            guard let fallback = defaults[key] else { continue }
            // Values equal to the default stay unset, so later default changes still apply.
            switch value {
            case .bool(let v): (fallback as? Bool) == v ? store.removeObject(forKey: key) : store.set(v, forKey: key)
            case .int(let v): (fallback as? Int) == v ? store.removeObject(forKey: key) : store.set(v, forKey: key)
            case .string(let v): (fallback as? String) == v ? store.removeObject(forKey: key) : store.set(v, forKey: key)
            }
        }
    }

    static func modifiers(_ key: String) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(UserDefaults.standard.integer(forKey: key)))
    }
}

private struct MenuContent: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ForEach(Action.Category.allCases, id: \.self) { category in
            Menu {
                ForEach(Action.allCases.filter { $0.category == category && $0 != .showMenu }, id: \.self) { action in
                    Button { state.perform(action) } label: { ActionLabel(action: action) }
                        .keyboardShortcut(state.shortcuts[action].flatMap(keyboardShortcut))
                }
            } label: {
                Label { Text(category.rawValue) } icon: { Glyph.image(for: category).map(Image.init(nsImage:)) }
                    .labelStyle(.titleAndIcon)
            }
        }
        if !state.customActions.isEmpty {
            Menu("Custom") {
                ForEach(state.customActions) { custom in
                    Button(custom.name) { state.perform(custom: custom.id) }
                        .keyboardShortcut(custom.shortcut.flatMap(keyboardShortcut))
                }
            }
        }
        Menu("Layouts") {
            ForEach(state.layouts) { layout in
                Button(layout.name) { state.apply(layout: layout.id) }
                    .keyboardShortcut(layout.shortcut.flatMap(keyboardShortcut))
            }
            if !state.layouts.isEmpty { Divider() }
            Button("Save Current Layout") { state.saveCurrentLayout() }
        }
        Divider()
        Button("Settings…") { SettingsHelper.open() }
        .keyboardShortcut(",")
        Button("Quit Fling") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func keyboardShortcut(_ s: Shortcut) -> KeyboardShortcut? {
        guard s.chars.count == 1, let char = s.chars.first else { return nil }
        var mods: EventModifiers = []
        if s.flags.contains(.command) { mods.insert(.command) }
        if s.flags.contains(.option) { mods.insert(.option) }
        if s.flags.contains(.control) { mods.insert(.control) }
        if s.flags.contains(.shift) { mods.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(char), modifiers: mods)
    }
}
