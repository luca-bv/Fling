import AppKit
import Carbon.HIToolbox

/// Device-dependent modifier bits in event flags: which physical side of a modifier is held.
enum ModifierSides {
    static let leftControl: UInt = 0x1, leftShift: UInt = 0x2, rightShift: UInt = 0x4, leftCommand: UInt = 0x8
    static let rightCommand: UInt = 0x10, leftOption: UInt = 0x20, rightOption: UInt = 0x40, rightControl: UInt = 0x2000
    static let all: UInt = 0x207F
    static let symbols: [(bit: UInt, symbol: String)] = [
        (leftControl, "‹⌃"), (rightControl, "⌃›"), (leftOption, "‹⌥"), (rightOption, "⌥›"),
        (leftShift, "‹⇧"), (rightShift, "⇧›"), (leftCommand, "‹⌘"), (rightCommand, "⌘›"),
    ]
}

struct Shortcut: Codable, Hashable, CustomStringConvertible {
    let key: Int         // Carbon virtual key code
    let modifiers: UInt  // NSEvent.ModifierFlags raw value
    let chars: String    // unmodified character, used as the menu key equivalent
    /// Required modifier sides (ModifierSides bits), or nil for either side. Side-specific shortcuts can't be
    /// Carbon hotkeys, so Fling's event tap handles them.
    let sides: UInt?

    init(_ key: Int, _ chars: String, _ modifiers: NSEvent.ModifierFlags, sides: UInt? = nil) {
        self.key = key
        self.chars = chars
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift]).rawValue
        self.sides = sides.map { $0 & ModifierSides.all }
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    func sameKeys(as other: Shortcut) -> Bool { key == other.key && modifiers == other.modifiers && sides == other.sides }

    /// Whether a key press (key code plus raw event flags) is this shortcut.
    func matches(keyCode: Int, flags raw: UInt) -> Bool {
        let generic = NSEvent.ModifierFlags(rawValue: raw).intersection([.command, .option, .control, .shift]).rawValue
        return keyCode == key && generic == modifiers && (sides.map { raw & ModifierSides.all == $0 } ?? true)
    }

    var description: String {
        let keyName = Self.keyNames[key] ?? chars.uppercased()
        guard let sides else { return modifierSymbols(flags) + keyName }
        return ModifierSides.symbols.filter { sides & $0.bit != 0 }.map(\.symbol).joined() + keyName
    }

    private static let keyNames: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Return: "↩", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Tab: "⇥", kVK_Space: "Space",
        kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
    var s = ""
    if flags.contains(.control) { s += "⌃" }
    if flags.contains(.option) { s += "⌥" }
    if flags.contains(.shift) { s += "⇧" }
    if flags.contains(.command) { s += "⌘" }
    return s
}

extension Action {
    /// Defaults match Rectangle's, so switching over needs no relearning.
    var defaultShortcut: Shortcut? {
        let co: NSEvent.ModifierFlags = [.control, .option]
        switch self {
        case .leftHalf:        return Shortcut(kVK_LeftArrow, "\u{F702}", co)
        case .rightHalf:       return Shortcut(kVK_RightArrow, "\u{F703}", co)
        case .topHalf:         return Shortcut(kVK_UpArrow, "\u{F700}", co)
        case .bottomHalf:      return Shortcut(kVK_DownArrow, "\u{F701}", co)
        case .topLeft:         return Shortcut(kVK_ANSI_U, "u", co)
        case .topRight:        return Shortcut(kVK_ANSI_I, "i", co)
        case .bottomLeft:      return Shortcut(kVK_ANSI_J, "j", co)
        case .bottomRight:     return Shortcut(kVK_ANSI_K, "k", co)
        case .firstThird:      return Shortcut(kVK_ANSI_D, "d", co)
        case .centerThird:     return Shortcut(kVK_ANSI_F, "f", co)
        case .lastThird:       return Shortcut(kVK_ANSI_G, "g", co)
        case .firstTwoThirds:  return Shortcut(kVK_ANSI_E, "e", co)
        case .lastTwoThirds:   return Shortcut(kVK_ANSI_T, "t", co)
        case .maximize:        return Shortcut(kVK_Return, "\r", co)
        case .maximizeHeight:  return Shortcut(kVK_UpArrow, "\u{F700}", co.union(.shift))
        case .center:          return Shortcut(kVK_ANSI_C, "c", co)
        case .larger:          return Shortcut(kVK_ANSI_Equal, "=", co)
        case .smaller:         return Shortcut(kVK_ANSI_Minus, "-", co)
        case .nextDisplay:     return Shortcut(kVK_RightArrow, "\u{F703}", co.union(.command))
        case .previousDisplay: return Shortcut(kVK_LeftArrow, "\u{F702}", co.union(.command))
        case .restore:         return Shortcut(kVK_Delete, "\u{7F}", co)
        case .keyboardGrid:    return Shortcut(kVK_ANSI_G, "g", co.union(.command))
        case .floatOnTop:      return Shortcut(kVK_ANSI_P, "p", co.union(.command))
        default:               return nil
        }
    }

    static var defaultShortcuts: [Action: Shortcut] {
        Dictionary(uniqueKeysWithValues: allCases.compactMap { a in a.defaultShortcut.map { (a, $0) } })
    }
}

enum ShortcutStorage {
    /// Saved entries override defaults; a saved `nil` means the user cleared that shortcut.
    static func merged(saved: [String: Shortcut?]) -> [Action: Shortcut] {
        var result = Action.defaultShortcuts
        for (raw, shortcut) in saved {
            if let action = Action(rawValue: raw) { result[action] = shortcut }
        }
        return result
    }

    /// Every action by name; `nil` marks a cleared shortcut.
    static func dictionary(_ shortcuts: [Action: Shortcut]) -> [String: Shortcut?] {
        Dictionary(uniqueKeysWithValues: Action.allCases.map { ($0.rawValue, shortcuts[$0]) })
    }
}

/// Global hotkeys via Carbon's RegisterEventHotKey: no extra permission, no dependency.
enum Hotkeys {
    private static var registered: [UInt32: (ref: EventHotKeyRef, repeats: Bool, handler: @MainActor () -> Void)] = [:]
    private static var sideSpecific: [(shortcut: Shortcut, repeats: Bool, handler: @MainActor () -> Void)] = []
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false
    nonisolated(unsafe) private static var repeatTimer: Timer?

    /// `repeats`: keep firing while the keys are held, like key repeat.
    static func register(_ shortcut: Shortcut, repeats: Bool = false, handler: @escaping @MainActor () -> Void) {
        if shortcut.sides != nil {
            sideSpecific.append((shortcut, repeats, handler))
            return
        }
        installHandlerOnce()
        let id = EventHotKeyID(signature: OSType(0x464C_4E47), id: nextID) // 'FLNG'
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.key), carbonModifiers(shortcut.flags), id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            registered[id.id] = (ref, repeats, handler)
        } else {
            NSLog("Fling: couldn't register hotkey \(shortcut) (OSStatus \(status))")
        }
    }

    static func unregisterAll() {
        registered.values.forEach { UnregisterEventHotKey($0.ref) }
        registered.removeAll()
        sideSpecific.removeAll()
    }

    private static func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            // Carbon delivers application-target events on the main thread.
            MainActor.assumeIsolated { Hotkeys.hotKey(id.id, pressed: pressed) }
            return noErr
        }, specs.count, &specs, nil, nil)
    }

    /// Fling's event tap offers every key press here first; returns true if a side-specific shortcut used it.
    @MainActor
    static func handleKeyDown(keyCode: Int, flags: UInt, isRepeat: Bool) -> Bool {
        guard let entry = sideSpecific.first(where: { $0.shortcut.matches(keyCode: keyCode, flags: flags) }) else { return false }
        if !isRepeat || entry.repeats { entry.handler() } // key repeat drives hold-to-repeat here
        return true
    }

    @MainActor
    private static func hotKey(_ id: UInt32, pressed: Bool) {
        repeatTimer?.invalidate()
        repeatTimer = nil
        guard pressed, let entry = registered[id] else { return }
        entry.handler()
        guard entry.repeats else { return }
        // Wait like key repeat does, then keep going until the keys are released.
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { _ in
            MainActor.assumeIsolated {
                repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                    MainActor.assumeIsolated { registered[id]?.handler() }
                }
            }
        }
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }
}
