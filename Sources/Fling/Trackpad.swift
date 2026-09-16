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
    /// The list owns the devices: while Fling holds it, their pointers stay valid. Dropping it frees them, so it
    /// goes only after they have been stopped — releasing them first crashed MultitouchSupport's own thread.
    private var deviceList: CFArray?
    private var armedAt: TimeInterval?
    private var throwing = false

    /// The C callback can't capture context, so it reports to the one live instance.
    private static weak var current: Trackpad?
    // ponytail: shared across trackpads' callback threads; two trackpads touched at once could interleave counts.
    nonisolated(unsafe) private static var lastCount: Int32 = -1

    /// One constant callback: registering and unregistering must pass the same function pointer.
    private static let callback: FrameCallback = { _, _, count, _, _ in
        guard count != Trackpad.lastCount else { return 0 }
        Trackpad.lastCount = count
        DispatchQueue.main.async { MainActor.assumeIsolated { Trackpad.current?.fingersChanged(Int(count)) } }
        return 0
    }

    /// MultitouchSupport's entry points, looked up once.
    private struct Functions {
        let createList: @convention(c) () -> Unmanaged<CFArray>?
        let register: @convention(c) (Device, FrameCallback) -> Void
        let unregister: @convention(c) (Device, FrameCallback) -> Void
        let startDevice: @convention(c) (Device, Int32) -> Int32
        let stopDevice: @convention(c) (Device) -> Int32
    }
    private lazy var functions: Functions? = load()

    init(onStart: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.onStart = onStart
        self.onEnd = onEnd
        Self.current = self
        start()
        // Multitouch devices go quiet after sleep; reconnect them.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Self.current?.reconnect() }
        }
        // The trigger is off by default and can be switched on in Settings.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Self.current?.settingChanged() }
        }
    }

    /// Reopens the trackpads, as after waking.
    func reconnect() { start() }

    private var enabled: Bool { UserDefaults.standard.integer(forKey: Prefs.throwTrackpadFingers) > 0 }

    private func settingChanged() {
        if enabled, devices.isEmpty { start() }
        if !enabled, !devices.isEmpty { stop() }
    }

    /// Opens the trackpads and watches finger counts. Only while the trigger is on: nothing else in Fling needs
    /// the private framework, so it stays untouched for everyone who doesn't use trackpad throws.
    private func start() {
        guard enabled, let functions else { return }
        stop()
        let list = functions.createList()?.takeRetainedValue()
        deviceList = list
        devices = (0..<(list.map(CFArrayGetCount) ?? 0)).compactMap { i in
            CFArrayGetValueAtIndex(list, i).map { UnsafeMutableRawPointer(mutating: $0) }
        }
        for device in devices {
            functions.register(device, Self.callback)
            _ = functions.startDevice(device, 0)
        }
    }

    private func stop() {
        guard let functions else { return }
        for device in devices {
            functions.unregister(device, Self.callback)
            _ = functions.stopDevice(device)
        }
        devices = []
        deviceList = nil // frees the devices, now that they are stopped
    }

    private func load() -> Functions? {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY),
              let createList = symbol(lib, "MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFArray>?).self),
              let register = symbol(lib, "MTRegisterContactFrameCallback", (@convention(c) (Device, FrameCallback) -> Void).self),
              let unregister = symbol(lib, "MTUnregisterContactFrameCallback", (@convention(c) (Device, FrameCallback) -> Void).self),
              let startDevice = symbol(lib, "MTDeviceStart", (@convention(c) (Device, Int32) -> Int32).self),
              let stopDevice = symbol(lib, "MTDeviceStop", (@convention(c) (Device) -> Int32).self)
        else {
            NSLog("Fling: MultitouchSupport unavailable; trackpad throws disabled")
            return nil
        }
        return Functions(createList: createList, register: register, unregister: unregister,
                         startDevice: startDevice, stopDevice: stopDevice)
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
