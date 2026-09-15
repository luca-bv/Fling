import AppKit

/// Everything the user configures, as one JSON document for export/import and iCloud Drive sync.
struct Config: Codable, Equatable {
    enum Preference: Codable, Equatable {
        case bool(Bool), int(Int), string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int.self) {
                self = .int(value)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .bool(let value): try value.encode(to: encoder)
            case .int(let value): try value.encode(to: encoder)
            case .string(let value): try value.encode(to: encoder)
            }
        }
    }

    var shortcuts: [String: Shortcut?]
    var customActions: [CustomAction]
    var layouts: [Layout]
    var preferences: [String: Preference]

    static func decode(_ data: Data?) -> Config? {
        data.flatMap { try? JSONDecoder().decode(Config.self, from: $0) }
    }

    /// Sorted keys keep the output stable, so unchanged configs produce identical files.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }
}

/// Keeps the config in iCloud Drive (~/Library/Mobile Documents/com~apple~CloudDocs/Fling/config.json).
/// A plain file needs no iCloud entitlement, so this works for self-signed builds too.
@MainActor
final class CloudSync {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Fling/config.json")

    private unowned let state: AppState
    private var pendingWrite: Task<Void, Never>?
    private var timer: Timer?

    private var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.iCloudSync) }
    /// Modification date of the file we last wrote or read; anything newer came from another Mac.
    private var lastSynced: Date {
        get { UserDefaults.standard.object(forKey: "iCloudSyncedAt") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "iCloudSyncedAt") }
    }

    init(state: AppState) {
        self.state = state
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleWrite() }
        }
        // ponytail: polls every 30 s; an NSFilePresenter would react instantly.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pull() }
        }
        pull()
    }

    /// Call when the setting is switched on: take a newer copy from iCloud, otherwise upload this Mac's.
    func enabledChanged() {
        pull()
        scheduleWrite()
    }

    private func pull() {
        guard enabled,
              let modified = (try? FileManager.default.attributesOfItem(atPath: Self.url.path))?[.modificationDate] as? Date,
              modified > lastSynced.addingTimeInterval(1),
              let data = try? Data(contentsOf: Self.url) else { return }
        lastSynced = modified
        if !state.importConfig(data) { NSLog("Fling: couldn't read iCloud config") }
    }

    private func scheduleWrite() {
        guard enabled else { return }
        pendingWrite?.cancel()
        pendingWrite = Task {
            try? await Task.sleep(for: .seconds(2)) // coalesce bursts of changes
            guard !Task.isCancelled, let data = state.exportConfig(), (try? Data(contentsOf: Self.url)) != data else { return }
            try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Self.url, options: .atomic)
            if let modified = (try? FileManager.default.attributesOfItem(atPath: Self.url.path))?[.modificationDate] as? Date {
                lastSynced = modified
            }
        }
    }
}
