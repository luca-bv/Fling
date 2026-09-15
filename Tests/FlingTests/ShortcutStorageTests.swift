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
