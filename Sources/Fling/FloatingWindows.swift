import AppKit
import ScreenCaptureKit

/// Always on top for any window. macOS won't let one app raise another app's window level, so Fling shows a live
/// ScreenCaptureKit mirror of the window in a floating panel over its real position. Clicking the mirror brings the
/// real window forward; the mirror comes back when you switch to another app. Needs Screen Recording permission.
/// Full-screen windows can't float (they live in their own Space).
@MainActor
final class FloatingWindows {
    private unowned let state: AppState
    private(set) var mirrors: [WindowMirror] = []
    private var timer: Timer?

    init(state: AppState) {
        self.state = state
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.appActivated(pid) }
        }
    }

    func toggle(_ window: Window) {
        if let index = mirrors.firstIndex(where: { $0.window.element == window.element }) {
            return remove(at: index)
        }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            state.log("Float on Top", window: window,
                      problem: "Screen Recording permission is needed to float windows (System Settings → Privacy & Security → Screen & System Audio Recording)")
            return NSSound.beep()
        }
        Task {
            do {
                let mirror = try await WindowMirror.start(for: window)
                mirror.onStop = { [weak self, weak mirror] in
                    guard let self, let mirror, let index = mirrors.firstIndex(where: { $0 === mirror }) else { return }
                    remove(at: index)
                }
                mirrors.append(mirror)
                // The window's own app is in front, so it's on top already; show the mirror once another app is.
                if NSWorkspace.shared.frontmostApplication?.processIdentifier != window.pid { mirror.show() }
                startTracking()
                state.log("Float on Top", window: window, problem: nil)
            } catch {
                state.log("Float on Top", window: window, problem: "Couldn't mirror this window: \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }

    func unfloatAll() {
        while !mirrors.isEmpty { remove(at: 0) }
    }

    private func remove(at index: Int) {
        mirrors.remove(at: index).stop()
        if mirrors.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    /// The mirror hides while its real window is in front (it's on top anyway) and returns when another app is.
    private func appActivated(_ pid: pid_t?) {
        for mirror in mirrors where mirror.window.pid != pid {
            mirror.show()
        }
    }

    /// Follows the real window as it moves or resizes, and drops mirrors of closed windows.
    private func startTracking() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for (index, mirror) in self.mirrors.enumerated().reversed() {
                    guard let frame = mirror.window.frame else {
                        self.remove(at: index)
                        continue
                    }
                    mirror.follow(frame)
                }
            }
        }
    }
}

/// One window's live mirror: a floating panel fed by a ScreenCaptureKit stream of just that window.
@MainActor
final class WindowMirror: NSObject, SCStreamOutput, SCStreamDelegate {
    let window: Window
    var onStop: (() -> Void)?
    private(set) var framesReceived = 0
    private let panel: NSPanel
    private let content = CALayer()
    private var stream: SCStream?
    private var frame: CGRect

    enum MirrorError: LocalizedError {
        case notCapturable
        var errorDescription: String? { "the window isn't available to screen capture (is it full screen or minimized?)" }
    }

    static func start(for window: Window) async throws -> WindowMirror {
        guard let frame = window.frame else { throw MirrorError.notCapturable }
        let shareable = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        // Pair the Accessibility window with its capture window by owner and frame (both top-left coordinates).
        guard let captured = shareable.windows.first(where: {
            $0.owningApplication?.processID == window.pid && $0.frame.isClose(to: frame, tolerance: 4)
        }) else { throw MirrorError.notCapturable }

        let mirror = WindowMirror(window: window, frame: frame)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: captured),
                              configuration: mirror.configuration(for: frame.size), delegate: mirror)
        try stream.addStreamOutput(mirror, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        mirror.stream = stream
        return mirror
    }

    private init(window: Window, frame: CGRect) {
        self.window = window
        self.frame = frame
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = MirrorView()
        view.wantsLayer = true
        view.layer?.addSublayer(content)
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        view.onClick = { [weak self] in self?.bringRealWindowForward() }
        panel.contentView = view
        content.contentsGravity = .resize
    }

    func show() {
        guard let primary = NSScreen.screens.first else { return }
        panel.alphaValue = CGFloat(UserDefaults.standard.double(forKey: Prefs.floatOpacity))
        panel.setFrame(flip(frame, primaryHeight: primary.frame.height), display: true)
        content.frame = CGRect(origin: .zero, size: frame.size)
        panel.orderFrontRegardless()
    }

    func follow(_ newFrame: CGRect) {
        guard !newFrame.isClose(to: frame, tolerance: 0.5) else { return }
        let resized = newFrame.size != frame.size
        frame = newFrame
        if panel.isVisible { show() }
        if resized { stream?.updateConfiguration(configuration(for: newFrame.size)) { _ in } }
    }

    func stop() {
        panel.orderOut(nil)
        stream?.stopCapture { _ in }
        stream = nil
    }

    // ponytail: the click that raises the real window isn't passed on to it; click again to interact.
    private func bringRealWindowForward() {
        panel.orderOut(nil)
        window.raise()
    }

    private func configuration(for size: CGSize) -> SCStreamConfiguration {
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width * scale)
        configuration.height = Int(size.height * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        return configuration
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              (info[.status] as? Int).flatMap(SCFrameStatus.init) == .complete,
              let surface = CMSampleBufferGetImageBuffer(sampleBuffer).flatMap({ CVPixelBufferGetIOSurface($0)?.takeUnretainedValue() })
        else { return }
        MainActor.assumeIsolated { // frames are delivered on the main queue
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            content.contents = surface
            CATransaction.commit()
            framesReceived += 1
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onStop?() } // e.g. the window closed
        }
    }
}

private final class MirrorView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
