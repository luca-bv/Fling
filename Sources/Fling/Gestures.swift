import AppKit

/// Mouse-driven features on one CGEventTap: drag-to-edge snapping, Window Throw, Quick Throw, Move & Resize.
/// Events pass through unchanged, except a mouse-button Window Throw's own button events. It's an active tap
/// because those only need Accessibility, which Fling already has; listen-only taps need Input Monitoring too.
@MainActor
final class Gestures {
    private unowned let state: AppState
    private var tap: CFMachPort?
    private var moveTap: CFMachPort?
    private var moveTapEnabled = true
    private let footprint = Overlay(cornerRadius: 10)
    private let reticle = Overlay(cornerRadius: 12)
    private let snapPanel = SnapPanel()
    private var targetOutlines: [Overlay] = []
    private var footprintFrame: CGRect?
    private var swallowNextLeftUp = false
    private var lastFlags: NSEvent.ModifierFlags = []

    private enum Snap {
        case action(Action, screen: Int)
        case custom(UUID)
    }

    private struct Drag {
        let window: Window?
        let start: CGRect
        var checks = 0
        var moving = false
        var resizing = false
        var targets: [(id: UUID, frame: CGRect)] = []
        var snap: Snap?
    }
    private var drag: Drag?

    private struct Throw {
        let window: Window
        let frame: CGRect
        let origin: CGPoint
        /// For mouse-button throws: the swallowed button press, replayed if the user just clicked.
        var buttonDown: CGEvent?
        var byTrackpad = false
        /// Held modifiers start and end this throw (rather than a mouse button or the trackpad).
        var byModifiers: Bool { buttonDown == nil && !byTrackpad }
        var target: (action: Action, screen: Int)?
    }
    private var throwing: Throw?

    private var trail: [(time: TimeInterval, point: CGPoint)] = []
    private var quick: (action: Action, point: CGPoint, time: TimeInterval)?

    private var manipulation: (window: Window, frame: CGRect, origin: CGPoint, modifiers: NSEvent.ModifierFlags, resize: Bool)?
    private var trackpad: Trackpad?

    init(state: AppState) {
        self.state = state
        start()
        trackpad = Trackpad(onStart: { [weak self] in self?.beginTrackpadThrow() },
                            onEnd: { [weak self] in self?.endThrow(apply: self?.throwing?.target != nil) })
    }

    private func start() {
        tap = makeTap([.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged, .keyDown,
                       .otherMouseDown, .otherMouseDragged, .otherMouseUp])
        guard tap != nil else {
            // Creating a tap fails until Accessibility access is granted; keep trying.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.start()
            }
            return
        }
        // Plain mouse moves get their own tap, on only while something follows the cursor: each event through an
        // active tap is a round trip to the window server, about 2% of a core while the mouse moves. Checking before
        // the run loop sleeps catches every way that changes (a hotkey, a click, the command line, a timer).
        moveTap = makeTap([.mouseMoved])
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateMoveTap() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        updateMoveTap()
    }

    private func makeTap(_ types: [CGEventType]) -> CFMachPort? {
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let gestures = Unmanaged<Gestures>.fromOpaque(refcon!).takeUnretainedValue()
                let pass = MainActor.assumeIsolated { gestures.handle(type, event) } // the tap runs on the main run loop
                return pass ? Unmanaged.passUnretained(event) : nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return tap
    }

    private var needsMouseMoves: Bool {
        throwing != nil || manipulation != nil || !state.stash.isEmpty || state.fillRest?.isShowing == true
            || state.keyboardGrid?.isShowing == true
            || UserDefaults.standard.bool(forKey: Prefs.quickThrow) // it reads the cursor's path from before the tap
    }

    private func updateMoveTap() {
        guard let moveTap, needsMouseMoves != moveTapEnabled else { return }
        moveTapEnabled.toggle()
        CGEvent.tapEnable(tap: moveTap, enable: moveTapEnabled)
        if !moveTapEnabled { trail.removeAll() }
    }

    /// Returns false to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard !Synthetic.isSynthetic(event) else { return true }
        let p = event.location
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Either tap may be the one macOS disabled: re-enable the main one, and let updateMoveTap decide the other.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            moveTapEnabled = false
        case .flagsChanged:
            let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(Prefs.modifierMask)
            flagsChanged(flags, at: p)
            state.fillRest?.flagsChanged(flags)
        case .mouseMoved:
            let now = ProcessInfo.processInfo.systemUptime
            trail.append((now, p))
            trail.removeAll { now - $0.time > 0.25 }
            throwMoved(to: p)
            manipulate(to: p)
            state.stash.mouseMoved(to: p)
            state.fillRest?.mouseMoved(to: p)
            state.keyboardGrid?.mouseMoved(to: p)
        case .keyDown where state.keyboardGrid?.isShowing == true:
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return false }
            return state.keyboardGrid?.handleKey(Int(event.getIntegerValueField(.keyboardEventKeycode))) != true
        case .leftMouseDown, .keyDown:
            if let assist = state.fillRest, assist.isShowing {
                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(Prefs.modifierMask)
                let used = type == .keyDown
                    ? assist.handleKey(Int(event.getIntegerValueField(.keyboardEventKeycode)), modifiers: flags)
                    : assist.handleClick(at: p)
                if used { return false }
            }
            if type == .keyDown, !state.capturingKeys,
               Hotkeys.handleKeyDown(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)), flags: UInt(event.flags.rawValue),
                                     isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0) {
                return false
            }
            state.keyboardGrid?.hide()
            // A click or a shortcut using the same modifiers means the user isn't throwing.
            quick = nil
            if let t = throwing, t.byModifiers { endThrow(apply: false) }
            if type == .leftMouseDown, contextClick(event, at: p) { return false }
            if type == .leftMouseDown, event.getIntegerValueField(.mouseEventClickState) == 2 { titleBarDoubleClicked(at: p) }
        case .otherMouseDown:
            return !beginButtonThrow(event, at: p)
        case .otherMouseDragged:
            if throwing?.buttonDown != nil { throwMoved(to: p) }
        case .otherMouseUp:
            return !endButtonThrow(event)
        case .leftMouseDragged:
            dragged(to: p)
        case .leftMouseUp:
            if swallowNextLeftUp {
                swallowNextLeftUp = false
                return false
            }
            dropped()
        default:
            break
        }
        return true
    }

    // MARK: Modifiers

    private func flagsChanged(_ flags: NSEvent.ModifierFlags, at p: CGPoint) {
        defer { lastFlags = flags }
        let now = ProcessInfo.processInfo.systemUptime

        if let t = throwing, t.byModifiers, flags != Prefs.modifiers(Prefs.throwModifiers) { endThrow(apply: t.target != nil) }
        if let m = manipulation, flags != m.modifiers { manipulation = nil }

        if let q = quick {
            quick = nil
            if flags.isEmpty, now - q.time < 0.5, let window = Window.at(q.point) {
                state.fillRest?.nextSource = .thrown
                state.perform(q.action, on: window)
            }
            return
        }
        guard !flags.isEmpty, throwing == nil, manipulation == nil else { return }

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Prefs.windowThrow), flags == Prefs.modifiers(Prefs.throwModifiers),
           let window = Window.at(p), let frame = window.frame {
            throwing = Throw(window: window, frame: frame, origin: p)
        } else if let resize = manipulationMode(for: flags), let window = Window.at(p), let frame = window.frame {
            manipulation = (window, frame, p, flags, resize)
        } else if defaults.bool(forKey: Prefs.quickThrow), lastFlags.isEmpty, flags == Prefs.modifiers(Prefs.quickThrowModifiers),
                  let first = trail.first(where: { now - $0.time <= 0.25 }), let action = quickThrowAction(dx: p.x - first.point.x, dy: p.y - first.point.y) {
            quick = (action, p, now)
        }
    }

    /// true = resize, false = move, nil = neither is enabled for these modifiers.
    private func manipulationMode(for flags: NSEvent.ModifierFlags) -> Bool? {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Prefs.moveWindow), flags == Prefs.modifiers(Prefs.moveModifiers) { return false }
        if defaults.bool(forKey: Prefs.resizeWindow), flags == Prefs.modifiers(Prefs.resizeModifiers) { return true }
        return nil
    }

    // MARK: Window Throw

    private func throwMoved(to p: CGPoint) {
        guard var t = throwing else { return }
        defer { throwing = t }
        let dx = p.x - t.origin.x, dy = p.y - t.origin.y, distance = hypot(dx, dy)
        guard distance >= CGFloat(UserDefaults.standard.integer(forKey: Prefs.throwSafeArea)) else {
            t.target = nil
            footprint.hide()
            return
        }
        reticle.show(CGRect(x: t.origin.x - 12, y: t.origin.y - 12, width: 24, height: 24))

        let screens = Screen.all()
        let windowScreen = screenIndex(for: t.frame, in: screens.map(\.visible))
        if let cursorScreen = screens.firstIndex(where: { $0.frame.contains(p) }), cursorScreen != windowScreen {
            t.target = (.center, cursorScreen) // thrown onto another display
        } else {
            let portrait = screens.indices.contains(windowScreen) && screens[windowScreen].frame.height > screens[windowScreen].frame.width
            let setting = { (sector: Int, long: Bool) in
                UserDefaults.standard.string(forKey: ThrowSectors.prefKey(sector: sector, long: long, portrait: portrait)) ?? "none"
            }
            t.target = throwAction(dx: dx, dy: dy, long: distance >= CGFloat(UserDefaults.standard.integer(forKey: Prefs.throwLongDistance)), setting: setting).map { ($0, windowScreen) }
        }
        if let target = t.target,
           let frame = state.target(for: target.action, window: t.window, frame: t.frame, screen: target.screen) {
            footprint.show(frame)
        } else {
            footprint.hide()
        }
    }

    private func endThrow(apply: Bool) {
        footprint.hide()
        reticle.hide()
        if apply, let t = throwing, let target = t.target {
            state.fillRest?.nextSource = .thrown
            state.perform(target.action, on: t.window, screen: target.screen)
        }
        throwing = nil
    }

    /// Starts a throw from the configured mouse button (numbered like Rectangle Pro: 3 is the middle button).
    private func beginButtonThrow(_ event: CGEvent, at p: CGPoint) -> Bool {
        let button = UserDefaults.standard.integer(forKey: Prefs.throwMouseButton)
        guard button > 0, throwing == nil, event.getIntegerValueField(.mouseEventButtonNumber) + 1 == button,
              let window = Window.at(p), let frame = window.frame else { return false }
        throwing = Throw(window: window, frame: frame, origin: p, buttonDown: event.copy())
        return true
    }

    private func beginTrackpadThrow() {
        guard UserDefaults.standard.bool(forKey: Prefs.windowThrow), throwing == nil,
              let p = CGEvent(source: nil)?.location, let window = Window.at(p), let frame = window.frame else { return }
        throwing = Throw(window: window, frame: frame, origin: p, byTrackpad: true)
    }

    private func endButtonThrow(_ event: CGEvent) -> Bool {
        guard let t = throwing, let down = t.buttonDown,
              event.getIntegerValueField(.mouseEventButtonNumber) == down.getIntegerValueField(.mouseEventButtonNumber)
        else { return false }
        if t.target != nil {
            endThrow(apply: true)
        } else {
            // The cursor barely moved, so it was an ordinary click: deliver it after all.
            endThrow(apply: false)
            Synthetic.post(down)
            Synthetic.post(event.copy())
        }
        return true
    }

    // MARK: Context menu & title bar

    /// Modifier-click shows Fling's menu for the clicked window; the click itself is swallowed.
    private func contextClick(_ event: CGEvent, at p: CGPoint) -> Bool {
        let modifiers = Prefs.modifiers(Prefs.contextClickModifiers)
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(Prefs.modifierMask)
        guard !modifiers.isEmpty, flags == modifiers else { return false }
        swallowNextLeftUp = true
        // Menus track in a nested run loop; leave the event tap callback first.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.state.contextMenu?.show(for: Window.at(p), at: p) }
        }
        return true
    }


    private func titleBarDoubleClicked(at p: CGPoint) {
        guard UserDefaults.standard.bool(forKey: Prefs.doubleClickTitleBar),
              let window = Window.at(p), let frame = window.frame, p.y - frame.minY <= 30,
              let role = Window.role(at: p), [kAXWindowRole, kAXToolbarRole].contains(role) else { return }
        let maximized = state.target(for: .maximize, window: window, frame: frame)?.isClose(to: frame) == true
        state.perform(maximized ? .restore : .maximize, on: window)
    }

    // MARK: Move & Resize

    private func manipulate(to p: CGPoint) {
        guard let m = manipulation else { return }
        let dx = p.x - m.origin.x, dy = p.y - m.origin.y
        if m.resize {
            m.window.setSize(CGSize(width: max(m.frame.width + dx, 100), height: max(m.frame.height + dy, 60)))
        } else {
            m.window.setOrigin(CGPoint(x: m.frame.minX + dx, y: m.frame.minY + dy))
        }
    }

    // MARK: Drag snapping: screen edges, Snap Panel, snap targets

    private func dragged(to p: CGPoint) {
        let defaults = UserDefaults.standard
        let edges = defaults.bool(forKey: Prefs.snapAreas), usePanel = defaults.bool(forKey: Prefs.snapPanel)
        let resizeAdjacent = defaults.bool(forKey: Prefs.resizeAdjacent)
        guard edges || usePanel || resizeAdjacent || state.customActions.contains(where: \.snapTarget) else { return }
        if drag == nil {
            let window = Window.at(p)
            drag = Drag(window: window, start: window?.frame ?? .null)
        }
        guard var d = drag, let window = d.window else { return }
        defer { drag = d }

        guard !d.resizing else { return }
        if !d.moving {
            // Title-bar drags move a window without resizing it; edge drags resize it; text selection does neither.
            guard d.checks < 20, let current = window.frame else { return }
            d.checks += 1
            if current.size != d.start.size {
                d.resizing = true
                return
            }
            guard current.origin != d.start.origin else { return }
            d.moving = true
            state.unsnapped(window)
            d.targets = state.snapTargets(for: window, frame: d.start)
            showTargetOutlines(d.targets.map(\.frame))
        }

        // Only now, once it's a window move: text selections and resizes drag far more often.
        let screens = Screen.all()
        let screen = screens.firstIndex { $0.frame.contains(p) }
        if usePanel, let screen { snapPanel.show(on: screens[screen]) } // no-op while it's showing

        let panelAction = snapPanel.action(at: p)
        let previousPreview = footprintFrame
        var preview: CGRect?
        let portrait = screen.map { screens[$0].frame.height > screens[$0].frame.width } ?? false
        let areaSetting = { (area: SnapArea) in defaults.string(forKey: area.prefKey(portrait: portrait)) ?? area.defaultSetting }
        if edges, let screen, let action = snapAction(at: p, in: screens[screen].frame, setting: areaSetting) {
            d.snap = .action(action, screen: screen)
            preview = state.target(for: action, window: window, frame: d.start, screen: screen)
        } else if let action = panelAction, let screen {
            d.snap = .action(action, screen: screen)
            preview = state.target(for: action, window: window, frame: d.start, screen: screen)
        } else if let hit = d.targets.first(where: { $0.frame.contains(p) }) {
            d.snap = .custom(hit.id)
            preview = hit.frame
        } else {
            d.snap = nil
        }
        if let preview { footprint.show(preview) } else { footprint.hide() }
        if let preview, preview != previousPreview, UserDefaults.standard.bool(forKey: Prefs.snapHaptics) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        footprintFrame = preview
    }

    private func dropped() {
        let byHand = drag?.moving == true || drag?.resizing == true
        if byHand { state.displayMemory?.windowsChanged() }
        if let d = drag, d.resizing, let window = d.window, let new = window.frame,
           UserDefaults.standard.bool(forKey: Prefs.resizeAdjacent) {
            let others = Window.visible().filter { $0.element != window.element }
            let tolerance = CGFloat(UserDefaults.standard.integer(forKey: Prefs.gap)) + 4
            for (i, frame) in adjacentFrames(old: d.start, new: new, others: others.compactMap(\.frame), tolerance: tolerance) {
                others[i].setFrame(frame)
            }
        }
        if let d = drag, let window = d.window {
            state.fillRest?.nextSource = .drag
            switch d.snap {
            case .action(let action, let screen): state.perform(action, on: window, screen: screen)
            case .custom(let id): state.perform(custom: id, on: window)
            case nil: break
            }
        }
        drag = nil
        // After the snap above, so a layout set to snap back wins over the placement this drag just made.
        if byHand { state.windowMovedByHand() }
        footprint.hide()
        footprintFrame = nil
        snapPanel.hide()
        showTargetOutlines([])
    }

    private func showTargetOutlines(_ frames: [CGRect]) {
        while targetOutlines.count < frames.count { targetOutlines.append(Overlay(cornerRadius: 10, alpha: 0.08)) }
        for (i, outline) in targetOutlines.enumerated() {
            if i < frames.count { outline.show(frames[i]) } else { outline.hide() }
        }
    }
}

/// A click-through translucent panel used for the snap footprint and the throw reticle.
@MainActor
final class Overlay {
    private let panel: NSPanel
    let color: NSColor
    /// Where the panel is headed, in AppKit coordinates; its frame lags behind while it glides.
    private var target = CGRect.null

    init(cornerRadius: CGFloat, alpha: CGFloat = 0.25, color: NSColor = .controlAccentColor) {
        self.color = color
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.borderWidth = 1.5
        view.layer?.backgroundColor = color.withAlphaComponent(alpha).cgColor
        view.layer?.borderColor = color.withAlphaComponent(min(alpha * 2.4, 0.7)).cgColor
        panel.contentView = view
    }

    /// `frame` is in Accessibility coordinates. A visible overlay glides to a new frame; a hidden one fades in.
    func show(_ frame: CGRect) {
        guard let primary = NSScreen.screens.first else { return }
        let appKitFrame = flip(frame, primaryHeight: primary.frame.height)
        guard panel.isVisible else {
            target = appKitFrame
            panel.setFrame(appKitFrame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.08; panel.animator().alphaValue = 1 }
            return
        }
        guard target != appKitFrame else { return }
        target = appKitFrame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(appKitFrame, display: true)
        }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }
}
