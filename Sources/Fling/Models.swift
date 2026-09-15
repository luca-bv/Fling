import CoreGraphics
import Foundation

/// A Bool that decodes as false when its key is missing, so configs saved before a setting existed still load.
@propertyWrapper
struct DefaultFalse: Codable, Hashable {
    var wrappedValue: Bool

    init(wrappedValue: Bool) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws { wrappedValue = try Bool(from: decoder) }
    func encode(to encoder: Encoder) throws { try wrappedValue.encode(to: encoder) }
}

extension KeyedDecodingContainer {
    func decode(_ type: DefaultFalse.Type, forKey key: Key) throws -> DefaultFalse {
        try decodeIfPresent(type, forKey: key) ?? DefaultFalse(wrappedValue: false)
    }
}

/// "leftHalf" → "Left Half"
func titleCase(_ camel: String) -> String {
    camel.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized
}

/// Which display a custom position or layout entry targets.
enum DisplayTarget: Codable, Hashable {
    case current, next, previous, index(Int)

    func resolve(current: Int, count: Int) -> Int {
        switch self {
        case .current: current
        case .next: (current + 1) % count
        case .previous: (current - 1 + count) % count
        case .index(let i): min(max(i, 0), count - 1)
        }
    }
}

/// A size and position such as "left third" or "800×600 at the top".
/// Values from 0 to 1 are fractions of the screen, anything else is points, blank keeps the window's value.
struct FrameSpec: Codable, Hashable {
    enum Anchor: String, Codable, CaseIterable {
        case center, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight, origin
    }

    var anchor: Anchor = .center
    var x = "", y = ""
    var width = "1/2", height = "1/2"

    func frame(for w: CGRect, in s: CGRect) -> CGRect {
        let width = min(Self.resolve(self.width, s.width) ?? w.width, s.width)
        let height = min(Self.resolve(self.height, s.height) ?? w.height, s.height)
        let left = s.minX, right = s.maxX - width, midX = s.midX - width / 2
        let top = s.minY, bottom = s.maxY - height, midY = s.midY - height / 2
        let origin: CGPoint
        switch anchor {
        case .center:      origin = CGPoint(x: midX, y: midY)
        case .top:         origin = CGPoint(x: midX, y: top)
        case .bottom:      origin = CGPoint(x: midX, y: bottom)
        case .left:        origin = CGPoint(x: left, y: midY)
        case .right:       origin = CGPoint(x: right, y: midY)
        case .topLeft:     origin = CGPoint(x: left, y: top)
        case .topRight:    origin = CGPoint(x: right, y: top)
        case .bottomLeft:  origin = CGPoint(x: left, y: bottom)
        case .bottomRight: origin = CGPoint(x: right, y: bottom)
        case .origin:
            origin = CGPoint(x: s.minX + (Self.resolve(x, s.width) ?? (w.minX - s.minX)),
                             y: s.minY + (Self.resolve(y, s.height) ?? (w.minY - s.minY)))
        }
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    /// "1/3" → a third of `total`, "0.25" → a quarter, "800" → 800 points, "" → nil.
    static func resolve(_ text: String, _ total: CGFloat) -> CGFloat? {
        let parts = text.split(separator: "/").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        let value: Double
        if parts.count == 1, let v = parts[0] {
            value = v
        } else if parts.count == 2, let n = parts[0], let d = parts[1], d != 0 {
            value = n / d
        } else {
            return nil
        }
        return (0...1).contains(value) ? CGFloat(value) * total : CGFloat(value)
    }

    /// Absolute points relative to the screen, as saved from an existing window.
    static func absolute(_ f: CGRect, in s: CGRect) -> FrameSpec {
        // A literal 1 would read as "100%", so nudge it to 0.
        func points(_ v: CGFloat) -> String { Int(v.rounded()) == 1 ? "0" : String(Int(v.rounded())) }
        return FrameSpec(anchor: .origin, x: points(f.minX - s.minX), y: points(f.minY - s.minY),
                         width: points(f.width), height: points(f.height))
    }
}

struct CustomAction: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = "Custom Position"
    var display: DisplayTarget = .current
    /// Later frames apply when the shortcut is repeated.
    var frames = [FrameSpec()]
    var shortcut: Shortcut?
    /// Show as a drop zone while dragging a window.
    @DefaultFalse var snapTarget = false
}

struct Layout: Codable, Hashable, Identifiable {
    enum Trigger: String, Codable, CaseIterable {
        case displayConnected, displayDisconnected, wake, windowOpened
    }

    var id = UUID()
    var name = "Layout"
    var shortcut: Shortcut?
    var triggers: Set<Trigger> = []
    var launchApps = false
    var hideOtherApps = false
    @DefaultFalse var bringToFront = false
    /// Only place windows of the frontmost app: one shortcut, different arrangement per app.
    @DefaultFalse var frontmostAppOnly = false
    /// After pairing entries with windows 1:1, keep applying entries to every other window they match.
    @DefaultFalse var allMatches = false
    var entries: [LayoutEntry] = []
}

struct LayoutEntry: Codable, Hashable, Identifiable {
    enum TitleMatch: String, Codable, CaseIterable {
        /// Prefer the saved title, otherwise take any remaining window of the app.
        case loose, any, exact, contains, regex
    }

    var id = UUID()
    var bundleID: String
    var appName: String
    var titleMatch: TitleMatch = .loose
    var title = ""
    /// A built-in action; nil means use `frame`.
    var action: Action?
    var frame = FrameSpec()
    var display: DisplayTarget = .current

    func matches(title candidate: String) -> Bool {
        switch titleMatch {
        case .any: true
        case .loose, .exact: candidate == title
        case .contains: candidate.localizedCaseInsensitiveContains(title)
        case .regex: candidate.range(of: title, options: .regularExpression) != nil
        }
    }

    /// Pairs entries with one app's windows (by title): specific matches first, then loose and any entries
    /// take whatever windows are left.
    static func match(_ entries: [LayoutEntry], titles: [String]) -> [(entry: Int, window: Int)] {
        var free = Array(titles.indices)
        var pairs: [(entry: Int, window: Int)] = []
        func take(_ entry: Int, _ accepts: (String) -> Bool) {
            guard let slot = free.firstIndex(where: { accepts(titles[$0]) }) else { return }
            pairs.append((entry, free.remove(at: slot)))
        }
        for (i, e) in entries.enumerated() where e.titleMatch != .any {
            take(i, e.matches)
        }
        for (i, e) in entries.enumerated() where e.titleMatch == .any || (e.titleMatch == .loose && !pairs.contains { $0.entry == i }) {
            take(i) { _ in true }
        }
        return pairs
    }
}

/// `fling://` URLs as flingctl arguments, so both share one parser: `execute-action?name=left-half` → `["left-half"]`,
/// `execute-custom?name=…` and `execute-layout?name=…` → `["custom" | "layout", name]`, `save-layout[?name=…]`.
func commandArguments(for url: URL) -> [String]? {
    guard url.scheme == "fling" else { return nil }
    let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "name" }?.value
    switch (url.host, name) {
    case ("save-layout", _): return ["save-layout"] + (name.map { [$0] } ?? [])
    case ("execute-action", let name?) where Action.allCases.contains(where: { $0.urlName == name }): return [name]
    case ("execute-custom", let name?): return ["custom", name]
    case ("execute-layout", let name?): return ["layout", name]
    default: return nil
    }
}

/// Splits a screen into the pinned app's strip and the space left for everything else.
func pinSplit(_ s: CGRect, width: String, right: Bool) -> (pinned: CGRect, rest: CGRect) {
    let w = min(FrameSpec.resolve(width, s.width) ?? s.width / 4, s.width)
    let pinned = CGRect(x: right ? s.maxX - w : s.minX, y: s.minY, width: w, height: s.height)
    let rest = CGRect(x: right ? s.minX : s.minX + w, y: s.minY, width: s.width - w, height: s.height)
    return (pinned, rest)
}

/// Slides (and if needed narrows) a frame horizontally so it fits inside `area`.
func clamp(_ f: CGRect, into area: CGRect) -> CGRect {
    var r = f
    r.size.width = min(r.width, area.width)
    r.origin.x = min(max(r.minX, area.minX), area.maxX - r.width)
    return r
}

/// Saved window positions for each display configuration (see DisplayMemory).
struct DisplayMemoryStore: Codable, Equatable {
    struct Record: Codable, Equatable {
        var title: String
        var frame: CGRect
    }

    struct Configuration: Codable, Equatable {
        var updated = Date()
        /// Windows by app bundle ID.
        var apps: [String: [Record]] = [:]
    }

    static let maxConfigurations = 20
    var configurations: [String: Configuration] = [:]

    /// Identifies a display setup: which displays, where, at what size (so a resolution change is a new setup).
    static func key(for screens: [Screen]) -> String {
        screens.sorted { $0.id < $1.id }
            .map { "\($0.id)@\(Int($0.frame.minX)),\(Int($0.frame.minY)),\(Int($0.frame.width))x\(Int($0.frame.height))" }
            .joined(separator: "|")
    }

    /// Replaces the records of the apps seen now; apps not seen (closed, hidden, on another Space) keep theirs.
    /// ponytail: per app, not per Space; an app's windows on another Space are forgotten once it's seen here.
    mutating func record(_ apps: [String: [Record]], for key: String) {
        var configuration = configurations[key] ?? Configuration()
        configuration.apps.merge(apps) { _, new in new }
        configuration.updated = Date()
        configurations[key] = configuration
        if configurations.count > Self.maxConfigurations,
           let oldest = configurations.min(by: { $0.value.updated < $1.value.updated })?.key {
            configurations[oldest] = nil
        }
    }

    /// Matches an app's current windows to its records by title (exact titles first, then whatever's left).
    static func placements(records: [Record], titles: [String]) -> [(window: Int, frame: CGRect)] {
        LayoutEntry.match(entries(records), titles: titles).map { ($0.window, records[$0.entry].frame) }
    }

    /// Where a newly opened window should go: its title's record if no open window already claims it,
    /// otherwise the first unclaimed record.
    static func placement(forNewWindow title: String, otherTitles: [String], records: [Record]) -> CGRect? {
        let claimed = Set(LayoutEntry.match(entries(records), titles: otherTitles).map(\.entry))
        let free = records.indices.filter { !claimed.contains($0) }
        return (free.first { records[$0].title == title } ?? free.first).map { records[$0].frame }
    }

    private static func entries(_ records: [Record]) -> [LayoutEntry] {
        records.map { LayoutEntry(bundleID: "", appName: "", titleMatch: .loose, title: $0.title) }
    }
}

/// JSON values in UserDefaults.
enum Store {
    static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    static func save(_ value: some Encodable, key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
