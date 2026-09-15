import AppKit

/// Reports new standard windows in any app, for layouts that apply when a window opens.
@MainActor
final class WindowWatcher {
    private let onWindow: (Window) -> Void
    private var observers: [pid_t: AXObserver] = [:]

    init(onWindow: @escaping (Window) -> Void) {
        self.onWindow = onWindow
        NSWorkspace.shared.runningApplications.forEach { watch($0) }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                // A just-launched app may not answer Accessibility requests yet.
                _ = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    if let app { self?.watch(app) }
                }
            }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid, let observer = self?.observers.removeValue(forKey: pid) {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
                }
            }
        }
    }

    private func watch(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            let watcher = Unmanaged<WindowWatcher>.fromOpaque(refcon!).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.windowCreated(element) } // observers run on the main run loop
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created,
              AXObserverAddNotification(observer, AXUIElementCreateApplication(pid), kAXWindowCreatedNotification as CFString,
                                        Unmanaged.passUnretained(self).toOpaque()) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func windowCreated(_ element: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        Task {
            // New windows often start at a placeholder size and get their title a moment later.
            try? await Task.sleep(for: .milliseconds(300))
            if let window = Window.all(of: pid).first(where: { $0.element == element }) { onWindow(window) }
        }
    }
}
