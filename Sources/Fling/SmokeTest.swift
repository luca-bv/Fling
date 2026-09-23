import AppKit

/// `Fling --smoke-test <bundle id>`: runs real actions against another app's window through the
/// Accessibility API and prints PASS/FAIL per step. `make smoke` runs it against Tests/Smoke/TestWindow.swift.
@MainActor
enum SmokeTest {
    private static func waitUntil(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return condition()
    }

    /// Runs the flingctl bundled next to this app and returns its exit status and combined output.
    private static func flingctl(_ arguments: [String]) async -> (status: Int32, output: String) {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "flingctl") else { return (-1, "flingctl isn't in the app bundle") }
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        // Talk to this instance, not the user's own Fling.
        process.environment = ProcessInfo.processInfo.environment.merging(["FLING_SOCKET": CommandServer.socketPath]) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        // Read off the main thread: flingctl's request is answered on the main queue, which must stay free.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }

    static func run(_ state: AppState, bundleID: String) async -> Bool {
        // A just-opened app can take a few seconds to answer Accessibility (longer on a busy Mac); wait up to 15 s.
        var found: (app: NSRunningApplication, window: Window)?
        _ = await waitUntil(seconds: 15) {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                  let window = Window.all(of: app.processIdentifier).first, window.frame != nil else { return false }
            found = (app, window)
            return true
        }
        guard let (app, window) = found, let original = window.frame,
              let screen = Screen.all().first(where: { $0.visible.intersects(original) })
        else {
            print("FAIL no usable window for \(bundleID) (is Fling allowed in Accessibility settings?)")
            return false
        }
        let defaults = UserDefaults.standard
        let touched = [Prefs.displayMemory, Prefs.gap, Prefs.cycleHalves, Prefs.pinEnabled, Prefs.pinBundleID, Prefs.pinWidth,
                       Prefs.pinRight, Prefs.throwTrackpadFingers]
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
        let othersVisible = Window.visible().contains { $0.element != window.element }
        // Both are the user's own settings, and this runs against their Fling's preferences: say so rather than fail.
        let offered = UserDefaults.standard.bool(forKey: Prefs.fillRest)
            && UserDefaults.standard.bool(forKey: FillRest.Source.shortcut.prefKey)
        let skip = !othersVisible ? " (skipped: no other windows)" : !offered ? " (skipped: switched off in Settings)" : ""
        expect("fill the rest offers the other half" + skip,
               !skip.isEmpty || (state.fillRest?.isShowing == true
                   && state.fillRest?.area.isClose(to: CGRect(x: s.midX, y: s.minY, width: s.width / 2, height: s.height)) == true))
        // Checked once; keep it off the screen for the rest of the run (without touching the user's setting).
        state.fillRest?.hide()
        state.fillRest?.suppressed = true
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
        let beforeLayout = window.frame ?? .null
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
        // Every other window is put back to the frame it already has, so nothing of the user's moves.
        await check("undo layout puts the window back", beforeLayout) { state.perform(.undoLayout) }

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
            if let newWindow, let frame = window.frame {
                newWindow.setFrame(frame)
                try? await Task.sleep(for: .milliseconds(500))
                let visible = Window.visible().map(\.element)
                expect("visible windows include both of two exactly stacked windows",
                       visible.contains(window.element) && visible.contains(newWindow.element))
            }
            _ = newWindow?.performControl(.close)
            state.layouts.removeAll { $0.id == opened.id }
        }

        if let url = URL(string: "fling://save-layout?name=Smoke%20URL") { state.handle(url) }
        expect("save-layout URL saves a named layout", state.layouts.contains { $0.name == "Smoke URL" })
        state.layouts.removeAll { $0.name == "Smoke URL" }

        // Config file: Fling writes it out, and an edit to the file comes back in.
        let fileKey = "smokeConfigFile", file = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "fling-smoke-config.json")
        try? FileManager.default.removeItem(at: file)
        defaults.set(true, forKey: fileKey)
        let fileSync = ConfigFileSync(state: state, url: file, enabledKey: fileKey, pollInterval: 0.5)
        fileSync.enabledChanged()
        // Writes wait for 2 s without other settings changes, so poll rather than sleep a fixed time.
        let wasWritten = await waitUntil(seconds: 10) { Config.decode(try? Data(contentsOf: file)) == Config.decode(state.exportConfig()) }
        expect("config file is written", wasWritten)
        if var edited = Config.decode(try? Data(contentsOf: file)) {
            try? await Task.sleep(for: .seconds(1.2)) // the file must look newer than Fling's own write
            edited.layouts.append(Layout(name: "From File"))
            try? edited.encoded()?.write(to: file)
        }
        expect("editing the config file updates Fling", await waitUntil(seconds: 5) { state.layouts.contains { $0.name == "From File" } })
        state.layouts.removeAll { $0.name == "From File" }
        defaults.removeObject(forKey: fileKey)
        defaults.removeObject(forKey: fileKey + "SyncedAt")
        try? FileManager.default.removeItem(at: file)

        // flingctl, the bundled command-line tool, talking to this Fling over its socket.
        window.setFrame(original)
        let moved = await flingctl(["--app", bundleID, "right-half"])
        try? await Task.sleep(for: .milliseconds(300))
        expect("flingctl moves an app's window (exit \(moved.status))", moved.status == 0
            && window.frame?.isClose(to: CGRect(x: s.midX, y: s.minY, width: s.width / 2, height: s.height)) == true)
        let framed = await flingctl(["frame", "120", "140", "500", "360", "--app", bundleID])
        try? await Task.sleep(for: .milliseconds(300))
        expect("flingctl frame sets an exact frame", framed.status == 0
            && window.frame?.isClose(to: CGRect(x: 120, y: 140, width: 500, height: 360)) == true)
        _ = await flingctl(["restore", "--app", bundleID])
        let nothingToRestore = await flingctl(["restore", "--app", bundleID])
        expect("flingctl fails when an action does nothing (exit \(nothingToRestore.status))",
               nothingToRestore.status == 1 && nothingToRestore.output.contains("Nothing to restore"))
        let windows = await flingctl(["windows"])
        expect("flingctl windows lists the test window", windows.status == 0 && windows.output.contains("Fling Smoke Test"))
        let displays = await flingctl(["displays", "--json"])
        expect("flingctl displays --json", displays.status == 0 && displays.output.contains("\"primary\""))
        let unknown = await flingctl(["no-such-command"])
        expect("flingctl fails on an unknown command", unknown.status == 1 && unknown.output.contains("Unknown command"))
        window.setFrame(original)

        // Float on Top needs Screen Recording permission, which only the user can grant.
        if CGPreflightScreenCaptureAccess() {
            state.floating?.toggle(window)
            try? await Task.sleep(for: .seconds(2))
            let mirror = state.floating?.mirrors.first
            expect("float on top mirrors the window (\(mirror?.framesReceived ?? 0) frames)", mirror.map { $0.framesReceived > 0 } == true)
            state.floating?.unfloatAll()
            expect("unfloat all", state.floating?.mirrors.isEmpty == true)
        } else {
            print("SKIP float on top: Screen Recording permission not granted")
        }

        // Display memory: record, let the window wander, then restore as after a display change.
        defaults.set(true, forKey: Prefs.displayMemory)
        window.setFrame(original)
        try? await Task.sleep(for: .milliseconds(300))
        state.displayMemory?.snapshot()
        window.setFrame(CGRect(x: s.minX, y: s.minY, width: 400, height: 300))
        state.displayMemory?.restore(after: 0, only: bundleID)
        try? await Task.sleep(for: .milliseconds(800))
        expect("display memory puts the window back" + (window.frame?.isClose(to: original) == true ? ""
            : " — expected \(original), got \(String(describing: window.frame))"), window.frame?.isClose(to: original) == true)
        state.displayMemory?.forget(bundleID: bundleID)
        state.fillRest?.hide()

        // Trackpad throws: reopening the devices (as on wake) used to stop and free devices already freed,
        // which crashed MultitouchSupport's thread. Surviving three rounds is the check.
        defaults.set(3, forKey: Prefs.throwTrackpadFingers)
        let trackpad = Trackpad(onStart: {}, onEnd: {})
        for _ in 0..<3 {
            trackpad.reconnect()
            try? await Task.sleep(for: .milliseconds(300))
        }
        expect("trackpad devices survive being reopened", true)
        defaults.set(0, forKey: Prefs.throwTrackpadFingers)

        state.perform(.minimize, on: window)
        try? await Task.sleep(for: .milliseconds(800))
        expect("minimize", Window.all(of: app.processIdentifier).isEmpty)
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        try? await Task.sleep(for: .milliseconds(800))

        // A reload applies what's on disk and must not write it back: Settings saves from another process, and
        // a write-back of an already-stale read wiped a shortcut that had just been recorded.
        let storedShortcuts = defaults.data(forKey: "shortcuts.v2")
        // A shortcut equal to its default is dropped when the engine saves, so it survives only if nothing saves.
        let untouched = try! JSONEncoder().encode(["leftHalf": Action.leftHalf.defaultShortcut])
        defaults.set(untouched, forKey: "shortcuts.v2")
        _ = await flingctl(["reload"])
        expect("a reload doesn't write the configuration back", defaults.data(forKey: "shortcuts.v2") == untouched)
        defaults.set(storedShortcuts, forKey: "shortcuts.v2")
        _ = await flingctl(["reload"])

        // Settings runs as its own process (see SettingsHelper): check it starts, reaches this engine, and quits.
        state.log("smoke", window: window, problem: nil)
        let (status, output) = await flingctl(["diagnostics", "--json"])
        let reported = DiagnosticEntry.decode(output)?.last?.command
        expect("the engine serves diagnostics to the Settings helper", status == 0 && reported == "smoke")
        expect("capture-keys pauses the engine's hotkeys", await flingctl(["capture-keys", "on"]).status == 0 && state.capturingKeys)
        _ = await flingctl(["capture-keys", "off"])
        SettingsHelper.open()
        try? await Task.sleep(for: .seconds(3))
        expect("the Settings helper opens", SettingsHelper.isRunning) // by bundle ID it'd match the user's own Fling
        // Closing the window keeps the helper for a minute, and opening Settings again reuses it.
        if let pid = SettingsHelper.processIdentifier {
            Window.all(of: pid).first.map { _ = $0.performControl(.close) }
            try? await Task.sleep(for: .seconds(1))
            expect("closing Settings keeps the helper loaded", SettingsHelper.isRunning && Window.all(of: pid).isEmpty)
            SettingsHelper.open()
            try? await Task.sleep(for: .seconds(1))
            expect("Settings reopens in the running helper", SettingsHelper.processIdentifier == pid && !Window.all(of: pid).isEmpty)
        }
        SettingsHelper.terminate()

        window.setFrame(original)
        for (key, value) in zip(touched, saved) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        print(failures == 0 ? "All smoke tests passed" : "\(failures) smoke test(s) failed")
        return failures == 0
    }
}
