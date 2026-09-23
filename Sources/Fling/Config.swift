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

/// Keeps the config in a JSON file, both ways: changes in Fling are written out, and edits to the file
/// (from another Mac via iCloud Drive, or by hand in a dotfiles repo) are loaded back in.
/// A plain file needs no iCloud entitlement, so this works for self-signed builds too.
@MainActor
final class ConfigFileSync {
    static let iCloudURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Fling/config.json")
    static let dotfileURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/fling/config.json")

    let url: URL
    private unowned let state: AppState
    private let enabledKey: String
    private let pollInterval: TimeInterval
    private var pendingWrite: Task<Void, Never>?
    private var timer: Timer?

    private var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    /// Modification date of the file as last written or read; anything newer was changed elsewhere.
    private var lastSynced: Date {
        get { UserDefaults.standard.object(forKey: enabledKey + "SyncedAt") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey + "SyncedAt") }
    }

    /// ponytail: polls the file's modification date; an NSFilePresenter would react instantly.
    init(state: AppState, url: URL, enabledKey: String, pollInterval: TimeInterval) {
        self.state = state
        self.url = url
        self.enabledKey = enabledKey
        self.pollInterval = pollInterval
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateTimer()
                self?.scheduleWrite()
            }
        }
        updateTimer()
        pull()
    }

    /// Call when the setting is switched on: load the file if it's newer, otherwise write this Mac's config.
    func enabledChanged() {
        updateTimer()
        pull()
        scheduleWrite()
    }

    /// Polls only while syncing is on, so a Mac that doesn't sync isn't woken every few seconds for nothing.
    private func updateTimer() {
        guard enabled != (timer != nil) else { return }
        timer?.invalidate()
        timer = enabled ? Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pull() }
        } : nil
    }

    private var modified: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Changed on disk since Fling last wrote or read it.
    private var changedElsewhere: Bool {
        modified.map { $0 > lastSynced.addingTimeInterval(1) } ?? false
    }

    private func pull() {
        guard enabled, changedElsewhere, let modified, let data = try? Data(contentsOf: url) else { return }
        lastSynced = modified
        if !state.importConfig(data) { NSLog("Fling: couldn't read the config at \(url.path); keeping the current settings") }
    }

    private func scheduleWrite() {
        guard enabled else { return }
        pendingWrite?.cancel()
        pendingWrite = Task {
            try? await Task.sleep(for: .seconds(2)) // coalesce bursts of changes
            guard !Task.isCancelled else { return }
            // An edit made to the file since (by hand or on another Mac) wins over writing ours out.
            if changedElsewhere { return pull() }
            guard let data = state.exportConfig(), (try? Data(contentsOf: url)) != data else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            if let modified { lastSynced = modified }
        }
    }
}
