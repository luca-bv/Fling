import CoreGraphics
import Testing
@testable import Fling

private let screen = CGRect(x: 0, y: 25, width: 1200, height: 800)
private let window = CGRect(x: 100, y: 100, width: 400, height: 300)

@Test func frameSpecValues() {
    #expect(FrameSpec.resolve("1/3", 1200) == 400)
    #expect(FrameSpec.resolve("0.25", 800) == 200)
    #expect(FrameSpec.resolve("640", 1200) == 640)
    #expect(FrameSpec.resolve("-20", 1200) == -20)
    #expect(FrameSpec.resolve("", 1200) == nil)
    #expect(FrameSpec.resolve("1/0", 1200) == nil)

    let topRightThird = FrameSpec(anchor: .topRight, width: "1/3", height: "1")
    #expect(topRightThird.frame(for: window, in: screen) == CGRect(x: 800, y: 25, width: 400, height: 800))
    // Blank width/height keep the window's size; custom origin is relative to the screen.
    let origin = FrameSpec(anchor: .origin, x: "50", y: "0.5", width: "", height: "")
    #expect(origin.frame(for: window, in: screen) == CGRect(x: 50, y: 425, width: 400, height: 300))
    // Saving an absolute frame round-trips.
    #expect(FrameSpec.absolute(window, in: screen).frame(for: .zero, in: screen) == window)
}

@Test func displayTargets() {
    #expect(DisplayTarget.next.resolve(current: 1, count: 2) == 0)
    #expect(DisplayTarget.previous.resolve(current: 0, count: 3) == 2)
    #expect(DisplayTarget.index(5).resolve(current: 0, count: 2) == 1)
}

@Test func layoutWindowMatching() {
    func entry(_ match: LayoutEntry.TitleMatch, _ title: String) -> LayoutEntry {
        LayoutEntry(bundleID: "app", appName: "App", titleMatch: match, title: title)
    }
    let titles = ["Inbox", "Notes.txt", "Draft"]
    let entries = [entry(.any, ""), entry(.loose, "Draft"), entry(.contains, ".txt"), entry(.loose, "Gone")]
    let pairs = Dictionary(uniqueKeysWithValues: LayoutEntry.match(entries, titles: titles).map { ($0.entry, $0.window) })
    #expect(pairs[1] == 2) // loose finds its exact title
    #expect(pairs[2] == 1) // contains
    #expect(pairs[0] == 0) // any takes a leftover window
    #expect(pairs[3] == nil) // no windows left for the missing title
    #expect(entry(.regex, "^In").matches(title: "Inbox"))
}

@Test func urlsBecomeCommands() {
    #expect(commandArguments(for: url("fling://execute-action?name=top-left-sixth")) == ["top-left-sixth"])
    #expect(commandArguments(for: url("fling://execute-layout?name=Work%20Setup")) == ["layout", "Work Setup"])
    #expect(commandArguments(for: url("fling://execute-custom?name=Wide")) == ["custom", "Wide"])
    #expect(commandArguments(for: url("fling://save-layout?name=Desk")) == ["save-layout", "Desk"])
    #expect(commandArguments(for: url("fling://save-layout")) == ["save-layout"])
    // Only real actions, so a URL can't run other commands (execute-action?name=windows).
    #expect(commandArguments(for: url("fling://execute-action?name=windows")) == nil)
    #expect(commandArguments(for: url("fling://execute-layout")) == nil)
    #expect(commandArguments(for: url("other://execute-action?name=left-half")) == nil)
    #expect(CLIRequest.parse(commandArguments(for: url("fling://execute-layout?name=Work%20Setup"))!) == .success(.layout("Work Setup")))
}

@Test func pinModeGeometry() {
    let split = pinSplit(screen, width: "1/4", right: true)
    #expect(split.pinned == CGRect(x: 900, y: 25, width: 300, height: 800))
    #expect(split.rest == CGRect(x: 0, y: 25, width: 900, height: 800))
    #expect(pinSplit(screen, width: "200", right: false).rest == CGRect(x: 200, y: 25, width: 1000, height: 800))
    // A window overlapping the pinned strip slides left; one too wide is narrowed.
    #expect(clamp(CGRect(x: 700, y: 100, width: 400, height: 300), into: split.rest) == CGRect(x: 500, y: 100, width: 400, height: 300))
    #expect(clamp(CGRect(x: 0, y: 0, width: 1200, height: 300), into: split.rest).width == 900)
}

@Test func configRoundTrip() {
    var custom = CustomAction(name: "Wide")
    custom.snapTarget = true
    var shortcuts = Action.defaultShortcuts
    shortcuts[.leftHalf] = nil
    let config = Config(shortcuts: ShortcutStorage.dictionary(shortcuts), customActions: [custom],
                        layouts: [Layout(name: "Desk", triggers: [.wake])],
                        preferences: ["gap": .int(8), "snapPanel": .bool(true), "pinWidth": .string("1/3")])
    // Stable bytes, so iCloud sync can tell "unchanged" from "changed".
    #expect(config.encoded() == config.encoded())
    let decoded = Config.decode(config.encoded())
    #expect(decoded == config)
    #expect(decoded.map { ShortcutStorage.merged(saved: $0.shortcuts)[.leftHalf] } == .some(nil))
}

@Test func winArrowKeys() {
    #expect(winArrowAction(.winArrowRight, from: nil) == .rightHalf)
    #expect(winArrowAction(.winArrowUp, from: .rightHalf) == .topRight)
    #expect(winArrowAction(.winArrowLeft, from: .topRight) == .topLeft)
    #expect(winArrowAction(.winArrowDown, from: .topLeft) == .leftHalf)
    #expect(winArrowAction(.winArrowUp, from: .center) == .maximize)
    #expect(winArrowAction(.winArrowDown, from: .maximize) == nil) // restore
    #expect(winArrowAction(.winArrowDown, from: nil) == .minimize)
}

@Test func configsFromOlderVersionsStillLoad() {
    // Written before snapTarget and the layout options existed.
    let old = jsonData("""
    {"shortcuts": {}, "preferences": {},
     "customActions": [{"id": "6A1F3F5E-0000-4000-8000-000000000001", "name": "Old", "display": {"current": {}},
                        "frames": [{"anchor": "center", "x": "", "y": "", "width": "1/2", "height": "1/2"}]}],
     "layouts": [{"id": "6A1F3F5E-0000-4000-8000-000000000002", "name": "Desk", "triggers": ["wake"],
                  "launchApps": true, "hideOtherApps": false, "entries": []}]}
    """)
    let config = Config.decode(old)
    #expect(config?.customActions.first?.snapTarget == false)
    #expect(config?.layouts.first?.launchApps == true)
    #expect(config?.layouts.first?.allMatches == false)
}

@Test func displayMemory() {
    let laptop = Screen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: screen, isPrimary: true, id: "B-LAPTOP")
    let monitor = Screen(frame: CGRect(x: 1440, y: -300, width: 2560, height: 1440), visible: screen, isPrimary: false, id: "A-MONITOR")
    // Order-independent, and a different arrangement or resolution is a different setup.
    #expect(DisplayMemoryStore.key(for: [laptop, monitor]) == DisplayMemoryStore.key(for: [monitor, laptop]))
    let moved = Screen(frame: CGRect(x: -2560, y: 0, width: 2560, height: 1440), visible: screen, isPrimary: false, id: "A-MONITOR")
    #expect(DisplayMemoryStore.key(for: [laptop, monitor]) != DisplayMemoryStore.key(for: [laptop, moved]))

    let inbox = DisplayMemoryStore.Record(title: "Inbox", frame: CGRect(x: 0, y: 25, width: 700, height: 800))
    let draft = DisplayMemoryStore.Record(title: "Draft", frame: CGRect(x: 700, y: 25, width: 700, height: 800))
    // Windows find their own titles first, whatever order they're listed in.
    let placements = DisplayMemoryStore.placements(records: [inbox, draft], titles: ["Draft", "Inbox"])
    #expect(Dictionary(uniqueKeysWithValues: placements.map { ($0.window, $0.frame) }) == [0: draft.frame, 1: inbox.frame])
    // A reopened "Draft" window goes to Draft's spot; a new untitled one takes the spot no open window claims.
    #expect(DisplayMemoryStore.placement(forNewWindow: "Draft", otherTitles: ["Inbox"], records: [inbox, draft]) == draft.frame)
    #expect(DisplayMemoryStore.placement(forNewWindow: "Untitled", otherTitles: ["Inbox"], records: [inbox, draft]) == draft.frame)
    #expect(DisplayMemoryStore.placement(forNewWindow: "Untitled", otherTitles: ["Inbox", "Draft"], records: [inbox, draft]) == nil)

    // Recording keeps apps that weren't seen, and drops the least recently used setup past the limit.
    var store = DisplayMemoryStore()
    store.record(["mail": [inbox]], for: "one")
    store.record(["notes": [draft]], for: "one")
    #expect(store.configurations["one"]?.apps.keys.sorted() == ["mail", "notes"])
    for i in 0..<DisplayMemoryStore.maxConfigurations { store.record(["mail": [inbox]], for: "setup \(i)") }
    #expect(store.configurations.count == DisplayMemoryStore.maxConfigurations)
    #expect(store.configurations["one"] == nil)
}

@Test func storedDataKeysDontCollideWithSettings() {
    // A settings key that's also used for stored JSON gets overwritten by it (display memory once turned itself off).
    let settings = Set(Prefs.snapshot().keys).union([Prefs.iCloudSync, Prefs.configFile])
    #expect(settings.isDisjoint(with: ["shortcuts", "shortcuts.v2", "customActions", "layouts", "displayMemoryStore"]))
}
