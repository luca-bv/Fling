import AppKit
import SwiftUI

/// Settings runs as a second copy of Fling, started with `--settings`.
///
/// SwiftUI builds a Settings window's views once and keeps them for the life of the process — about 45 MB that is
/// never given back, even after the window closes. As its own process, Settings hands that memory back to the system
/// when you close the window, and the part of Fling that runs all day stays small.
///
/// The helper runs no engine: no hotkeys, no event tap, no window watching. It edits the same stored configuration
/// and asks the engine to act through the flingctl socket, the way the command line does.
@MainActor
enum SettingsHelper {
    nonisolated static let isHelper = CommandLine.arguments.contains("--settings")

    private static var running: Process?

    /// True while the Settings window is open (this process started it).
    static var isRunning: Bool { running?.isRunning == true }

    /// Opens Settings: brings the helper forward if it's already up, otherwise starts one.
    static func open() {
        if let running, running.isRunning {
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

    private static var fallbackWindow: NSWindow?

    /// Opens the Settings window macOS dresses as preferences (toolbar tabs, the right size, a title per tab).
    /// Nothing outside a view can open it, so the app menu's own Settings item is used; if that ever stops
    /// working, a plain window stands in rather than leaving the helper with nothing on screen.
    static func showWindow(_ content: @escaping () -> some View) {
        if let menu = NSApp.mainMenu?.items.first?.submenu,
           let item = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) {
            menu.performActionForItem(at: item)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
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
