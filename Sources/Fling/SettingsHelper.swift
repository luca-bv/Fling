import AppKit
import SwiftUI

/// Settings runs as a second copy of Fling, started with `--settings`.
///
/// SwiftUI builds a Settings window's views once and keeps them for the life of the process — about 45 MB that is
/// never given back, even after the window closes. As its own process, Settings hands that memory back to the system
/// a minute after you close the window, and the part of Fling that runs all day stays small.
///
/// The helper runs no engine: no hotkeys, no event tap, no window watching. It edits the same stored configuration
/// and asks the engine to act through the flingctl socket, the way the command line does.
@MainActor
enum SettingsHelper {
    nonisolated static let isHelper = CommandLine.arguments.contains("--settings")

    private static var running: Process?

    /// True while the helper this process started is up (its window may be closed; see `run`).
    static var isRunning: Bool { running?.isRunning == true }
    static var processIdentifier: pid_t? { isRunning ? running?.processIdentifier : nil }

    /// Opens Settings: tells a helper that's still up to show its window, otherwise starts one.
    static func open() {
        if let running, running.isRunning {
            // Activating another app from the background can be refused, so the helper is told directly.
            DistributedNotificationCenter.default().postNotificationName(showWindowNotification,
                                                                         object: String(running.processIdentifier),
                                                                         deliverImmediately: true)
            NSRunningApplication(processIdentifier: running.processIdentifier)?.activate()
            return
        }
        guard let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--settings"]
        // The smoke test's helper must reach the smoke test's engine, not the user's own Fling.
        if smokeTesting {
            process.environment = ProcessInfo.processInfo.environment.merging(["FLING_SOCKET": CommandServer.socketPath]) { _, new in new }
        }
        do { try process.run() } catch { return NSLog("Fling: couldn't open Settings: \(error)") }
        running = process
    }

    private static let showWindowNotification = NSNotification.Name("com.lucabv.Fling.showSettings")
    private static var pendingQuit: Task<Void, Never>?

    private static var hasVisibleWindow: Bool { NSApp.windows.contains { $0.isVisible && $0.canBecomeMain } }

    /// In the helper: shows the window now and again whenever the engine asks, and quits a minute after it's closed.
    /// Staying up that long makes reopening Settings soon after instant (the window is kept, not rebuilt); quitting
    /// after it hands the memory back.
    static func run(_ content: @escaping () -> some View) {
        let show = {
            NSApp.activate(ignoringOtherApps: true) // an accessory app's window opens behind everything otherwise
            showWindow(content)
        }
        DistributedNotificationCenter.default().addObserver(forName: showWindowNotification, object: String(getpid()),
                                                            queue: .main) { _ in
            MainActor.assumeIsolated(show)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                pendingQuit?.cancel()
                pendingQuit = Task {
                    try? await Task.sleep(for: .seconds(60))
                    // Checked now, not at the close: it may have been a save panel, or the window was reopened.
                    if !Task.isCancelled, !hasVisibleWindow { NSApp.terminate(nil) }
                }
            }
        }
        show()
    }

    private static var fallbackWindow: NSWindow?

    /// Opens the Settings window macOS dresses as preferences (toolbar tabs, the right size, a title per tab).
    /// Nothing outside a view can open it, so the app menu's own Settings item is used; if that ever stops
    /// working, a plain window stands in rather than leaving the helper with nothing on screen.
    private static func showWindow(_ content: @escaping () -> some View) {
        if let menu = NSApp.mainMenu?.items.first?.submenu,
           let item = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
            menu.performActionForItem(at: item)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard !hasVisibleWindow else { return }
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = "Fling Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.center()
            window.makeKeyAndOrderFront(nil)
            fallbackWindow = window
        }
    }

    /// Closes the Settings window when Fling quits.
    static func terminate() {
        guard let running, running.isRunning else { return }
        running.terminate()
    }

    /// Sends a command to the engine and ignores the reply.
    static func send(_ arguments: [String]) {
        Task { _ = await reply(to: arguments) }
    }

    /// Sends a command to the engine and returns its output, or nil if it couldn't be reached.
    /// ponytail: runs the bundled flingctl rather than opening the socket here; a process per command is plenty
    /// for button clicks and the once-a-second diagnostics refresh. Talk to the socket directly if that changes.
    static func reply(to arguments: [String]) async -> String? {
        guard let flingctl = Bundle.main.url(forAuxiliaryExecutable: "flingctl") else { return nil }
        let process = Process()
        process.executableURL = flingctl
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
            }
        }
    }
}
