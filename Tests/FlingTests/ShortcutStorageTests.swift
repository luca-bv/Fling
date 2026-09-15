import AppKit
import Testing
@testable import Fling

@Test func clearedShortcutsSurviveSaveAndLoad() {
    var shortcuts = Action.defaultShortcuts
    shortcuts[.leftHalf] = nil
    let config = Config(shortcuts: ShortcutStorage.dictionary(shortcuts), customActions: [], layouts: [], preferences: [:])
    let loaded = ShortcutStorage.merged(saved: Config.decode(config.encoded())?.shortcuts ?? [:])
    #expect(loaded[.leftHalf] == nil)
    #expect(loaded[.rightHalf] == Action.rightHalf.defaultShortcut)
    // Nothing saved yet → defaults.
    #expect(ShortcutStorage.merged(saved: [:]) == Action.defaultShortcuts)
}

@Test func shortcutDescription() {
    #expect(Action.center.defaultShortcut?.description == "⌃⌥C")
    #expect(Action.nextDisplay.defaultShortcut?.description == "⌃⌥⌘→")
}

@Test func sideSpecificShortcuts() {
    let rightCommandLeft = Shortcut(123, "\u{F702}", [.command], sides: ModifierSides.rightCommand)
    let command: UInt = 1 << 20
    #expect(rightCommandLeft.matches(keyCode: 123, flags: command | ModifierSides.rightCommand))
    #expect(!rightCommandLeft.matches(keyCode: 123, flags: command | ModifierSides.leftCommand))
    #expect(!rightCommandLeft.matches(keyCode: 124, flags: command | ModifierSides.rightCommand))
    #expect(rightCommandLeft.description == "⌘›←")
    // Either-side shortcuts match both, and differ from the side-specific one.
    let anyCommandLeft = Shortcut(123, "\u{F702}", [.command])
    #expect(anyCommandLeft.matches(keyCode: 123, flags: command | ModifierSides.leftCommand))
    #expect(!anyCommandLeft.sameKeys(as: rightCommandLeft))
}

@Test func shortcutsSavedBeforeSidesStillLoad() {
    let old = jsonData(#"{"customActions": [], "layouts": [], "preferences": {},"#
        + #" "shortcuts": {"leftHalf": {"key": 123, "modifiers": 786432, "chars": ""}, "rightHalf": null}}"#)
    let loaded = ShortcutStorage.merged(saved: Config.decode(old)?.shortcuts ?? [:])
    #expect(loaded[.leftHalf]?.sides == nil && loaded[.leftHalf]?.key == 123)
    #expect(loaded[.rightHalf] == nil)
}

@Test func defaultShortcutsAreConflictFree() {
    let defaults = Action.defaultShortcuts.values.map { ($0.key, $0.modifiers) }
    let combos = Set(defaults.map { "\($0.0)-\($0.1)" })
    #expect(combos.count == defaults.count) // no two actions share keys

    func combo(_ key: Int, _ flags: NSEvent.ModifierFlags) -> String { "\(key)-\(flags.rawValue)" }
    // Reserved by macOS (Apple's shortcut list, Mission Control, input sources, screenshots).
    let reserved = [
        combo(49, [.control, .option]), combo(49, [.control, .command]), combo(49, [.command]), combo(49, [.option, .command]),
        combo(3, [.control, .command]), combo(12, [.control, .command]), combo(53, [.option, .command]),
        combo(28, [.control, .option, .command]), combo(43, [.control, .option, .command]), combo(47, [.control, .option, .command]),
        combo(123, [.control]), combo(124, [.control]), combo(125, [.control]), combo(126, [.control]),
        combo(2, [.option, .command]), combo(4, [.option, .command]), combo(46, [.option, .command]), combo(13, [.option, .command]),
        combo(20, [.shift, .command]), combo(21, [.shift, .command]), combo(23, [.shift, .command]),
    ]
    #expect(combos.isDisjoint(with: reserved))
    // Every default lives under ⌃⌥, so Fling's keys stay in one predictable layer.
    #expect(Action.defaultShortcuts.values.allSatisfy { $0.flags.isSuperset(of: [.control, .option]) })
}

@Test func onlyChangedShortcutsAreSaved() {
    #expect(ShortcutStorage.dictionary(Action.defaultShortcuts).isEmpty)
    var shortcuts = Action.defaultShortcuts
    shortcuts[.leftHalf] = nil
    shortcuts[.nudgeLeft] = Shortcut(123, "", [.control, .option, .shift, .command])
    let saved = ShortcutStorage.dictionary(shortcuts)
    #expect(saved.count == 2 && saved.keys.contains("leftHalf") && saved["leftHalf"]! == nil)
    #expect(ShortcutStorage.merged(saved: saved) == shortcuts)
    // Re-recording a default's keys (with a different menu character) isn't a change.
    shortcuts = Action.defaultShortcuts
    shortcuts[.stashLeft] = Shortcut(123, "\u{1C}", [.control, .option, .shift, .command])
    #expect(ShortcutStorage.dictionary(shortcuts).isEmpty)
}
