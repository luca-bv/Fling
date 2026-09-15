import AppKit

/// Rectangle Pro's trackpad trigger for Window Throw: rest 3–5 fingers, lift all but one, move that finger, lift it.
/// Only finger counts are needed, read from the private MultitouchSupport framework (as MiddleClick does);
/// the remaining finger moves the cursor normally, so the throw runs on ordinary mouse-moved events.
@MainActor
final class Trackpad {
    private typealias Device = UnsafeMutableRawPointer
    private typealias FrameCallback = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

    private let onStart: () -> Void
    private let onEnd: () -> Void
    private var devices: [Device] = []
    private var armedAt: TimeInterval?
    private var throwing = false

    /// The C callback can't capture context, so it reports to the one live instance.
    private static weak var current: Trackpad?
    // ponytail: shared across trackpads' callback threads; two trackpads touched at once could interleave counts.
    nonisolated(unsafe) private static var lastCount: Int32 = -1

    init(onStart: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.onStart = onStart
        self.onEnd = onEnd
        Self.current = self
        start()
        // Multitouch devices go quiet after sleep; reconnect them.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Self.current?.start() }
        }
    }

    private func start() {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY),
              let createList = symbol(lib, "MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFArray>?).self),
              let register = symbol(lib, "MTRegisterContactFrameCallback", (@convention(c) (Device, FrameCallback) -> Void).self),
              let unregister = symbol(lib, "MTUnregisterContactFrameCallback", (@convention(c) (Device, FrameCallback) -> Void).self),
              let startDevice = symbol(lib, "MTDeviceStart", (@convention(c) (Device, Int32) -> Int32).self),
              let stopDevice = symbol(lib, "MTDeviceStop", (@convention(c) (Device) -> Int32).self)
        else { return NSLog("Fling: MultitouchSupport unavailable; trackpad throws disabled") }

        let callback: FrameCallback = { _, _, count, _, _ in
            guard count != Trackpad.lastCount else { return 0 }
            Trackpad.lastCount = count
            DispatchQueue.main.async { MainActor.assumeIsolated { Trackpad.current?.fingersChanged(Int(count)) } }
            return 0
        }
        for device in devices {
            unregister(device, callback)
            _ = stopDevice(device)
        }
        let list = createList()?.takeRetainedValue()
        devices = (0..<(list.map(CFArrayGetCount) ?? 0)).compactMap { i in
            CFArrayGetValueAtIndex(list, i).map { UnsafeMutableRawPointer(mutating: $0) }
        }
        for device in devices {
            register(device, callback)
            _ = startDevice(device, 0)
        }
    }

    private func fingersChanged(_ count: Int) {
        let needed = UserDefaults.standard.integer(forKey: Prefs.throwTrackpadFingers)
        guard needed > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if count >= needed {
            if armedAt == nil { armedAt = now }
        } else if count == 1, let armedAt, !throwing {
            self.armedAt = nil
            // A quick rest-then-lift; a long multi-finger gesture ending with one finger isn't a throw.
            if now - armedAt < 1.5 {
                throwing = true
                onStart()
            }
        } else if count == 0 {
            armedAt = nil
            if throwing {
                throwing = false
                onEnd()
            }
        }
    }

    private func symbol<T>(_ lib: UnsafeMutableRawPointer, _ name: String, _ type: T.Type) -> T? {
        dlsym(lib, name).map { unsafeBitCast($0, to: type) }
    }
}
