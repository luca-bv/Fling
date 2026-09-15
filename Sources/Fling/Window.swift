import AppKit
import Carbon.HIToolbox

/// A window of another app, via the Accessibility API.
struct Window {
    let element: AXUIElement
    let app: AXUIElement

    /// The focused window of the frontmost app.
    static func focused() -> Window? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let window = element(app, kAXFocusedWindowAttribute) else { return nil }
        return Window(element: window, app: app)
    }

    /// The window under a point in Accessibility coordinates, ignoring Fling's own windows.
    static func at(_ p: CGPoint) -> Window? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &hit) == .success,
              let hit else { return nil }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(hit, kAXRoleAttribute as CFString, &role)
        guard let window = (role as? String) == kAXWindowRole ? hit : element(hit, kAXWindowAttribute) else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid != getpid() else { return nil }
        return Window(element: window, app: AXUIElementCreateApplication(pid))
    }

    /// Standard, non-minimized windows of an app.
    static func all(of pid: pid_t) -> [Window] {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let elements = ref as? [AXUIElement] else { return [] }
        return elements.map { Window(element: $0, app: app) }.filter {
            $0.string(kAXSubroleAttribute) == kAXStandardWindowSubrole && !$0.bool(kAXMinimizedAttribute)
        }
    }

    /// Visible standard windows of other apps on the current Space, front to back.
    static func visible() -> [Window] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var candidates: [pid_t: [Window]] = [:]
        var result: [Window] = []
        for entry in info where (entry[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            if candidates[pid] == nil { candidates[pid] = all(of: pid) }
            // Window server and Accessibility describe the same windows; pair them up by frame.
            if let match = candidates[pid]?.first(where: { $0.frame?.isClose(to: bounds) == true }),
               !result.contains(where: { $0.element == match.element }) {
                result.append(match)
            }
        }
        return result
    }

    /// Role of the element under a point, e.g. to tell a title bar from a button.
    static func role(at p: CGPoint) -> String? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &hit) == .success,
              let hit else { return nil }
        return Window(element: hit, app: hit).string(kAXRoleAttribute)
    }

    var title: String { string(kAXTitleAttribute) ?? "" }

    var pid: pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    var bundleID: String? { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    var frame: CGRect? {
        guard let origin = value(kAXPositionAttribute, .cgPoint, CGPoint.zero),
              let size = value(kAXSizeAttribute, .cgSize, CGSize.zero) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Returns the first Accessibility error, or `.success`.
    @discardableResult
    func setFrame(_ f: CGRect) -> AXError {
        // Enhanced UI (turned on by assistive apps) makes apps animate AX resizes slowly; pause it.
        let enhanced = "AXEnhancedUserInterface" as CFString
        var ref: CFTypeRef?
        let wasEnhanced = AXUIElementCopyAttributeValue(app, enhanced, &ref) == .success && (ref as? Bool) == true
        if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanFalse) }

        // Size, move, size again: the first resize may be clamped by the old screen's bounds.
        let results = [setSize(f.size), setOrigin(f.origin), setSize(f.size)]

        if wasEnhanced { AXUIElementSetAttributeValue(app, enhanced, kCFBooleanTrue) }
        return results.first { $0 != .success } ?? .success
    }

    @discardableResult func setOrigin(_ origin: CGPoint) -> AXError { set(kAXPositionAttribute, .cgPoint, origin) }
    @discardableResult func setSize(_ size: CGSize) -> AXError { set(kAXSizeAttribute, .cgSize, size) }

    /// Handles actions that aren't frame changes. Returns false for frame-based actions.
    func performControl(_ action: Action) -> Bool {
        switch action {
        case .minimize:
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        case .fullScreen:
            let fullScreen = "AXFullScreen" as CFString
            var ref: CFTypeRef?
            AXUIElementCopyAttributeValue(element, fullScreen, &ref)
            AXUIElementSetAttributeValue(element, fullScreen, (ref as? Bool) == true ? kCFBooleanFalse : kCFBooleanTrue)
        case .close:
            if let button = Self.element(element, kAXCloseButtonAttribute) {
                AXUIElementPerformAction(button, kAXPressAction as CFString)
            }
        case .hideApp:
            NSRunningApplication(processIdentifier: pid)?.hide()
        case .quitApp:
            NSRunningApplication(processIdentifier: pid)?.terminate()
        default:
            return false
        }
        return true
    }

    /// There's no public API for moving windows between Spaces, so do what a person would: hold the
    /// title bar and press the Mission Control shortcut (⌃← / ⌃→, which must be enabled in System Settings).
    func moveToAdjacentSpace(right: Bool) async {
        guard let frame else { return }
        // ponytail: grabs a fixed spot right of the traffic lights; apps with a control there won't move.
        let grip = CGPoint(x: frame.minX + min(90, frame.width / 2), y: frame.minY + 12)
        let cursor = CGEvent(source: nil)?.location
        Synthetic.post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: grip, mouseButton: .left))
        try? await Task.sleep(for: .milliseconds(100))
        let arrow = CGKeyCode(right ? kVK_RightArrow : kVK_LeftArrow)
        for down in [true, false] {
            let key = CGEvent(keyboardEventSource: nil, virtualKey: arrow, keyDown: down)
            key?.flags = [.maskControl, .maskSecondaryFn] // arrow keys carry the fn flag
            Synthetic.post(key)
        }
        try? await Task.sleep(for: .milliseconds(450))
        Synthetic.post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: grip, mouseButton: .left))
        if let cursor { CGWarpMouseCursorPosition(cursor) }
    }

    private func string(_ attribute: String) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        return ref as? String
    }

    private func bool(_ attribute: String) -> Bool {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        return (ref as? Bool) == true
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private func value<T: BitwiseCopyable>(_ attribute: String, _ type: AXValueType, _ empty: T) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var out = empty
        return AXValueGetValue(ref as! AXValue, type, &out) ? out : nil
    }

    private func set<T: BitwiseCopyable>(_ attribute: String, _ type: AXValueType, _ value: T) -> AXError {
        var value = value
        guard let axValue = AXValueCreate(type, &value) else { return .illegalArgument }
        return AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
    }
}

private func displayUUID(_ screen: NSScreen) -> String {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
          let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return screen.localizedName }
    return CFUUIDCreateString(nil, uuid) as String
}

/// Events Fling posts itself, tagged so its own event tap ignores them.
enum Synthetic {
    static let tag: Int64 = 0x464C_4E47 // 'FLNG'

    static func post(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: tag)
        event?.post(tap: .cghidEventTap)
    }

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == tag
    }
}

/// A display in Accessibility coordinates: `frame` is the whole screen, `visible` excludes menu bar and Dock.
struct Screen {
    let frame: CGRect
    let visible: CGRect
    let isPrimary: Bool
    /// Stable across reconnects (unlike the index or display number).
    let id: String

    /// Left to right, then top to bottom.
    static func all() -> [Screen] {
        guard let primary = NSScreen.screens.first else { return [] }
        let h = primary.frame.height
        return NSScreen.screens
            .map { Screen(frame: flip($0.frame, primaryHeight: h), visible: flip($0.visibleFrame, primaryHeight: h),
                          isPrimary: $0 == primary, id: displayUUID($0)) }
            .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }
}
