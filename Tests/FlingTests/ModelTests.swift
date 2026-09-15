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

@Test func urlCommands() {
    #expect(URLCommand(string: "fling://execute-action?name=left-half") == .action(.leftHalf))
    #expect(URLCommand(string: "fling://execute-action?name=top-left-sixth") == .action(.topLeftSixth))
    #expect(URLCommand(string: "fling://execute-layout?name=Work%20Setup") == .layout("Work Setup"))
    #expect(URLCommand(string: "fling://execute-action?name=nope") == nil)
    #expect(URLCommand(string: "other://execute-action?name=left-half") == nil)
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
