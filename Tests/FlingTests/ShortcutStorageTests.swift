import Testing
@testable import Fling

@Test func clearedShortcutsSurviveSaveAndLoad() {
    var shortcuts = Action.defaultShortcuts
    shortcuts[.leftHalf] = nil
    let loaded = ShortcutStorage.decode(ShortcutStorage.encode(shortcuts))
    #expect(loaded[.leftHalf] == nil)
    #expect(loaded[.rightHalf] == Action.rightHalf.defaultShortcut)
    // Nothing saved yet → defaults.
    #expect(ShortcutStorage.decode(nil) == Action.defaultShortcuts)
}

@Test func shortcutDescription() {
    #expect(Action.center.defaultShortcut?.description == "⌃⌥C")
    #expect(Action.nextDisplay.defaultShortcut?.description == "⌃⌥⌘→")
}
