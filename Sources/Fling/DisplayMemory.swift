import AppKit

/// Remembers where every app's windows sit for each display configuration, like the app Stay, but built in.
/// When displays are connected, disconnected or rearranged, or the Mac wakes, windows go back to where they were
/// the last time that configuration was in use. Windows of reopened apps return to their last spot too.
@MainActor
final class DisplayMemory {
    private unowned let state: AppState
    private var memory: DisplayMemoryStore
    /// Right after a display change macOS shuffles windows; don't record that shuffle before restoring.
    private var pausedUntil = Date.distantPast
    private var pendingSnapshot: Task<Void, Never>?
    private var timer: Timer?

    private var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.displayMemory) }

    init(state: AppState) {
        self.state = state
        memory = Store.load("displayMemoryStore") ?? DisplayMemoryStore()
        // Catches windows moved by other apps (Fling's own moves and drags record right away, via windowsChanged).
        // Each snapshot asks every app for its windows (~40 ms), which is most of what Fling costs while idle; once
        // a minute, with slack so macOS can bundle the wakeup with others, halves that.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.snapshot() }
        }
        timer?.tolerance = 15
        snapshot()
    }

    /// Windows moved (by Fling or a drag): record soon, once things settle.
    func windowsChanged() {
        pendingSnapshot?.cancel()
        pendingSnapshot = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { self?.snapshot() }
        }
    }

    /// Displays changed or the Mac woke: put windows back for the configuration now in use.
    /// `only` limits the restore to one app (the smoke test uses it to leave every other window alone).
    func restore(after delay: Double, only bundleID: String? = nil) {
        guard enabled else { return }
        pausedUntil = Date().addingTimeInterval(delay + 3)
        pendingSnapshot?.cancel()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay)) // let macOS finish moving windows around first
            self?.restoreNow(only: bundleID)
        }
    }

    /// Places a newly opened window where that app's window last was in this configuration. Returns true if moved.
    func windowOpened(_ window: Window) -> Bool {
        guard enabled, UserDefaults.standard.bool(forKey: Prefs.displayMemoryNewWindows),
              let bundleID = window.bundleID, let frame = window.frame,
              let records = memory.configurations[DisplayMemoryStore.key(for: Screen.all())]?.apps[bundleID] else { return false }
        let others = Window.all(of: window.pid).filter { $0.element != window.element }.map(\.title)
        guard let target = DisplayMemoryStore.placement(forNewWindow: window.title, otherTitles: others, records: records),
              !target.isClose(to: frame), onScreen(target) else { return false }
        state.place(window, at: target, key: "rememberedPosition")
        return true
    }

    /// Drops one app's records everywhere (the smoke test uses this to clean up after itself).
    func forget(bundleID: String) {
        for key in memory.configurations.keys { memory.configurations[key]?.apps[bundleID] = nil }
        Store.save(memory, key: "displayMemoryStore")
    }

    func forgetAll() {
        memory = DisplayMemoryStore()
        Store.save(memory, key: "displayMemoryStore")
    }

    func snapshot() {
        guard enabled, Date() >= pausedUntil else { return }
        let key = DisplayMemoryStore.key(for: Screen.all())
        var apps: [String: [DisplayMemoryStore.Record]] = [:]
        for window in Window.visible() {
            guard let bundleID = window.bundleID, let frame = window.frame else { continue }
            apps[bundleID, default: []].append(.init(title: window.title, frame: frame))
        }
        let before = memory
        memory.record(apps, for: key)
        if memory.configurations[key]?.apps != before.configurations[key]?.apps {
            Store.save(memory, key: "displayMemoryStore")
        }
    }

    private func restoreNow(only: String? = nil) {
        guard let configuration = memory.configurations[DisplayMemoryStore.key(for: Screen.all())] else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden {
            guard let bundleID = app.bundleIdentifier, only == nil || only == bundleID,
                  let records = configuration.apps[bundleID] else { continue }
            let windows = Window.all(of: app.processIdentifier)
            for (index, frame) in DisplayMemoryStore.placements(records: records, titles: windows.map(\.title)) {
                guard let current = windows[index].frame, !current.isClose(to: frame), onScreen(frame) else { continue }
                state.place(windows[index], at: frame, key: "restoreDisplayMemory")
            }
        }
    }

    private func onScreen(_ frame: CGRect) -> Bool {
        Screen.all().contains { $0.visible.intersects(frame) }
    }
}
