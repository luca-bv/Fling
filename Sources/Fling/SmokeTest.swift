import AppKit

/// `Fling --smoke-test <bundle id>`: runs real actions against another app's window through the
/// Accessibility API and prints PASS/FAIL per step. `make smoke` runs it against Tests/Smoke/TestWindow.swift.
@MainActor
enum SmokeTest {
    static func run(_ state: AppState, bundleID: String) async -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let window = Window.all(of: app.processIdentifier).first, let original = window.frame,
              let screen = Screen.all().first(where: { $0.visible.intersects(original) })
        else {
            print("FAIL no usable window for \(bundleID) (is Fling allowed in Accessibility settings?)")
            return false
        }
        let defaults = UserDefaults.standard
        let touched = [Prefs.gap, Prefs.cycleHalves, Prefs.pinEnabled, Prefs.pinBundleID, Prefs.pinWidth, Prefs.pinRight]
        // Only values the user actually set; registered defaults read back as values too.
        let persisted = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let saved = touched.map { persisted[$0] }
        defaults.set(0, forKey: Prefs.gap)
        defaults.set(true, forKey: Prefs.cycleHalves)
        defaults.set(false, forKey: Prefs.pinEnabled)

        let s = screen.visible
        var failures = 0
        func check(_ name: String, _ expected: CGRect, _ run: () -> Void) async {
            run()
            try? await Task.sleep(for: .milliseconds(300))
            let actual = window.frame ?? .null
            let pass = actual.isClose(to: expected, tolerance: 2)
            if !pass { failures += 1 }
            print(pass ? "PASS" : "FAIL", name, pass ? "" : "— expected \(expected), got \(actual)")
        }
        func expect(_ name: String, _ pass: Bool) {
            if !pass { failures += 1 }
            print(pass ? "PASS" : "FAIL", name)
        }

        await check("left half", CGRect(x: s.minX, y: s.minY, width: s.width / 2, height: s.height)) {
            state.perform(.leftHalf, on: window)
        }
        await check("left half again cycles to ⅔", CGRect(x: s.minX, y: s.minY, width: s.width * 2 / 3, height: s.height)) {
            state.perform(.leftHalf, on: window)
        }
        await check("bottom right", CGRect(x: s.midX, y: s.midY, width: s.width / 2, height: s.height / 2)) {
            state.perform(.bottomRight, on: window)
        }
        await check("center", CGRect(x: s.midX - s.width / 4, y: s.midY - s.height / 4, width: s.width / 2, height: s.height / 2)) {
            state.perform(.center, on: window)
        }
        await check("restore", original) { state.perform(.restore, on: window) }
        await check("nudge right", original.offsetBy(dx: Action.sizeStep, dy: 0)) { state.perform(.nudgeRight, on: window) }
        let others = Window.visible().filter { $0.element != window.element }.compactMap(\.frame)
        await check("fill left", fillFrame(left: true, others: others, in: s)) { state.perform(.fillLeft, on: window) }
        await check("restore after nudge and fill", original) { state.perform(.restore, on: window) }
        await check("win arrow right", CGRect(x: s.midX, y: s.minY, width: s.width / 2, height: s.height)) {
            state.perform(.winArrowRight, on: window)
        }
        await check("win arrow up → top right", CGRect(x: s.midX, y: s.minY, width: s.width / 2, height: s.height / 2)) {
            state.perform(.winArrowUp, on: window)
        }
        await check("win arrow left → top left", CGRect(x: s.minX, y: s.minY, width: s.width / 2, height: s.height / 2)) {
            state.perform(.winArrowLeft, on: window)
        }
        await check("restore after win arrows", original) { state.perform(.restore, on: window) }
        state.keyboardGrid?.show(for: window)
        _ = state.keyboardGrid?.handleKey(13) // W: top row, second column
        await check("keyboard grid W then C spans the middle columns", CGRect(x: s.minX + s.width / 4, y: s.minY,
                                                                              width: s.width / 2, height: s.height)) {
            _ = state.keyboardGrid?.handleKey(8) // C: bottom row, third column
        }
        expect("keyboard grid closes and hotkeys resume", state.keyboardGrid?.isShowing == false && !state.capturingKeys)
        let logged = state.diagnostics.last
        expect("diagnostics logged the grid placement", logged?.command == "Keyboard Grid" && logged?.problem == nil)
        await check("restore after keyboard grid", original) { state.perform(.restore, on: window) }

        await check("stash left", CGRect(x: screen.frame.minX - original.width + 8, y: original.minY,
                                         width: original.width, height: original.height)) {
            state.stash.stash(window, to: .left)
        }
        let shownLeft = CGRect(x: s.minX, y: original.minY, width: original.width, height: original.height)
        let tucked = CGRect(x: screen.frame.minX - original.width + 8, y: original.minY, width: original.width, height: original.height)
        window.setOrigin(shownLeft.origin) // as if macOS pulled it back on screen after sleep
        await check("stash is re-tucked after macOS moves it", tucked) { state.stash.reapply() }
        await check("toggle stashed shows it", shownLeft) { state.perform(.toggleStashed) }
        await check("toggle stashed tucks it back", CGRect(x: screen.frame.minX - original.width + 8, y: original.minY,
                                                          width: original.width, height: original.height)) {
            state.perform(.toggleStashed)
        }
        await check("cycle stashed shows it", shownLeft) { state.perform(.cycleStashed) }
        await check("unstash all", CGRect(x: s.minX, y: original.minY, width: original.width, height: original.height)) {
            state.stash.unstashAll()
        }

        if screen.isPrimary {
            defaults.set(true, forKey: Prefs.pinEnabled)
            defaults.set("com.example.pinned", forKey: Prefs.pinBundleID)
            defaults.set("1/4", forKey: Prefs.pinWidth)
            defaults.set(true, forKey: Prefs.pinRight)
            let rest = pinSplit(s, width: "1/4", right: true).rest
            await check("left half with Pin Mode", CGRect(x: rest.minX, y: rest.minY, width: rest.width / 2, height: rest.height)) {
                state.perform(.leftHalf, on: window)
            }
            defaults.set(false, forKey: Prefs.pinEnabled)
        }

        let custom = CustomAction(name: "Smoke Test", frames: [
            FrameSpec(anchor: .topRight, width: "1/3", height: "1/2"),
            FrameSpec(anchor: .bottomLeft, width: "400", height: "300"),
        ])
        state.customActions.append(custom)
        await check("custom position", CGRect(x: s.maxX - s.width / 3, y: s.minY, width: s.width / 3, height: s.height / 2)) {
            state.perform(custom: custom.id, on: window)
        }
        await check("custom position repeat", CGRect(x: s.minX, y: s.maxY - 300, width: 400, height: 300)) {
            state.perform(custom: custom.id, on: window)
        }
        state.customActions.removeAll { $0.id == custom.id }

        let layout = Layout(name: "Smoke Test", entries: [
            LayoutEntry(bundleID: bundleID, appName: "Smoke Test", titleMatch: .any, action: .topLeft),
        ])
        state.layouts.append(layout)
        await check("apply layout", CGRect(x: s.minX, y: s.minY, width: s.width / 2, height: s.height / 2)) {
            state.apply(layout: layout.id)
        }
        state.layouts.removeAll { $0.id == layout.id }

        let before = Set(state.layouts.map(\.id))
        state.saveCurrentLayout()
        let savedLayout = state.layouts.first { !before.contains($0.id) }
        expect("save layout records the window's action",
               savedLayout?.entries.contains { $0.bundleID == bundleID && $0.action == .topLeft } == true)
        state.layouts.removeAll { !before.contains($0.id) }

        var target = CustomAction(name: "Smoke Target", frames: [FrameSpec(anchor: .bottomRight, width: "1/4", height: "1/4")])
        target.snapTarget = true
        state.customActions.append(target)
        let quarter = CGRect(x: s.maxX - s.width / 4, y: s.maxY - s.height / 4, width: s.width / 4, height: s.height / 4)
        expect("snap target frame", state.snapTargets(for: window, frame: original).first { $0.id == target.id }?.frame.isClose(to: quarter) == true)
        state.customActions.removeAll { $0.id == target.id }

        let exported = state.exportConfig()
        expect("config export → import round-trips",
               exported.map { state.importConfig($0) } == true && state.exportConfig() == exported)

        // The test window app opens a second window on SIGUSR1; other apps would quit on that signal.
        if bundleID == "com.lucabv.Fling.TestWindow" {
            let opened = Layout(name: "Smoke Opened", triggers: [.windowOpened], entries: [
                LayoutEntry(bundleID: bundleID, appName: "Smoke Test", titleMatch: .contains, title: "Opened", action: .bottomLeft),
            ])
            state.layouts.append(opened)
            let existing = Window.all(of: app.processIdentifier).map(\.element)
            kill(app.processIdentifier, SIGUSR1)
            try? await Task.sleep(for: .seconds(1.5))
            let newWindow = Window.all(of: app.processIdentifier).first { !existing.contains($0.element) }
            expect("layout applies to a newly opened window",
                   newWindow?.frame?.isClose(to: CGRect(x: s.minX, y: s.midY, width: s.width / 2, height: s.height / 2)) == true)
            _ = newWindow?.performControl(.close)
            state.layouts.removeAll { $0.id == opened.id }
        }

        state.perform(.minimize, on: window)
        try? await Task.sleep(for: .milliseconds(800))
        expect("minimize", Window.all(of: app.processIdentifier).isEmpty)
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        try? await Task.sleep(for: .milliseconds(800))

        window.setFrame(original)
        for (key, value) in zip(touched, saved) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        print(failures == 0 ? "All smoke tests passed" : "\(failures) smoke test(s) failed")
        return failures == 0
    }
}
