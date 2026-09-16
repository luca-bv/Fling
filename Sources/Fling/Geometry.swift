import CoreGraphics

// All rects use Accessibility coordinates: origin at the top-left of the primary display, y grows down.

enum Action: String, CaseIterable, Codable {
    case winArrowLeft, winArrowRight, winArrowUp, winArrowDown
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, centerTwoThirds, lastTwoThirds
    case firstFourth, secondFourth, thirdFourth, lastFourth, firstThreeFourths, lastThreeFourths
    case topLeftSixth, topCenterSixth, topRightSixth, bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    case maximize, almostMaximize, maximizeHeight, center, upperCenter
    case fillLeft, fillRight
    case larger, smaller, moveLeft, moveRight, moveUp, moveDown, nudgeLeft, nudgeRight, nudgeUp, nudgeDown
    case nextDisplay, previousDisplay, nextSpace, previousSpace
    case restore, minimize, fullScreen, close, hideApp, quitApp, showMenu, keyboardGrid, floatOnTop, unfloatAll
    case stashLeft, stashRight, stashAll, stashAllExceptFront, toggleStashed, cycleStashed, unstashAll
    case togglePin, reflowPin
    case tile2x2, tile2x3, cascadeAll, cascadeApp, appLeftHalf, appRightHalf

    enum Category: String, CaseIterable {
        case winArrows = "Win Arrow Keys", halves = "Halves", corners = "Corners", thirds = "Thirds", fourths = "Fourths", sixths = "Sixths"
        case maximize = "Maximize & Center", sizeAndMove = "Size & Move", display = "Display & Space", window = "Window"
        case fill = "Fill", multiple = "Multiple Windows", stash = "Stash", pin = "Pin Mode"
    }

    static let sizeStep: CGFloat = 30

    var title: String {
        switch self {
        case .tile2x2: "2×2 Tiles"
        case .tile2x3: "2×3 Tiles"
        default: titleCase(rawValue)
        }
    }

    /// Name used by the URL scheme: "left-half".
    var urlName: String {
        rawValue.replacingOccurrences(of: "([A-Z])", with: "-$1", options: .regularExpression).lowercased()
    }

    /// Actions that place a window by frame, usable in layouts and throws.
    var placesWindow: Bool {
        switch category {
        case .halves, .corners, .thirds, .fourths, .sixths, .maximize: true
        case .sizeAndMove: self == .moveLeft || self == .moveRight || self == .moveUp || self == .moveDown
        default: false
        }
    }

    var category: Category {
        switch self {
        case .winArrowLeft, .winArrowRight, .winArrowUp, .winArrowDown: .winArrows
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: .halves
        case .topLeft, .topRight, .bottomLeft, .bottomRight: .corners
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds: .thirds
        case .firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .lastThreeFourths: .fourths
        case .topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth: .sixths
        case .maximize, .almostMaximize, .maximizeHeight, .center, .upperCenter: .maximize
        case .fillLeft, .fillRight: .fill
        case .larger, .smaller, .moveLeft, .moveRight, .moveUp, .moveDown, .nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown: .sizeAndMove
        case .nextDisplay, .previousDisplay, .nextSpace, .previousSpace: .display
        case .restore, .minimize, .fullScreen, .close, .hideApp, .quitApp, .showMenu, .keyboardGrid, .floatOnTop, .unfloatAll: .window
        case .stashLeft, .stashRight, .stashAll, .stashAllExceptFront, .toggleStashed, .cycleStashed, .unstashAll: .stash
        case .togglePin, .reflowPin: .pin
        case .tile2x2, .tile2x3, .cascadeAll, .cascadeApp, .appLeftHalf, .appRightHalf: .multiple
        }
    }

    /// Actions that tile against the screen or other windows get gaps; free-floating ones don't.
    private var usesGaps: Bool {
        switch category {
        case .halves, .corners, .thirds, .fourths, .sixths, .fill: true
        default: self == .maximize || self == .almostMaximize
        }
    }

    /// Target frame on screen `s`. `repeatCount` cycles half actions through ½ → ⅔ → ⅓.
    /// Display moves and window controls are handled by the caller.
    func frame(for w: CGRect, in s: CGRect, gap: CGFloat = 0, repeatCount: Int = 0) -> CGRect {
        guard usesGaps, gap > 0 else { return rawFrame(for: w, in: s, repeatCount: repeatCount) }
        // Half a gap around the screen plus half around each window = a full gap everywhere.
        return rawFrame(for: w, in: s.insetBy(dx: gap / 2, dy: gap / 2), repeatCount: repeatCount)
            .insetBy(dx: gap / 2, dy: gap / 2)
    }

    private func rawFrame(for w: CGRect, in s: CGRect, repeatCount: Int) -> CGRect {
        func grid(_ cols: CGFloat, _ rows: CGFloat, x: CGFloat, y: CGFloat, w: CGFloat = 1, h: CGFloat = 1) -> CGRect {
            CGRect(x: s.minX + s.width * x / cols, y: s.minY + s.height * y / rows,
                   width: s.width * w / cols, height: s.height * h / rows)
        }
        // Thirds and fourths become rows on portrait displays.
        func strip(_ n: CGFloat, _ i: CGFloat, span: CGFloat = 1) -> CGRect {
            s.height > s.width ? grid(1, n, x: 0, y: i, h: span) : grid(n, 1, x: i, y: 0, w: span)
        }
        let halves: [CGFloat] = [1 / 2, 2 / 3, 1 / 3]
        let half = halves[repeatCount % 3]
        let size = CGSize(width: min(w.width, s.width), height: min(w.height, s.height))

        switch self {
        case .leftHalf:          return CGRect(x: s.minX, y: s.minY, width: s.width * half, height: s.height)
        case .rightHalf:         return CGRect(x: s.maxX - s.width * half, y: s.minY, width: s.width * half, height: s.height)
        case .topHalf:           return CGRect(x: s.minX, y: s.minY, width: s.width, height: s.height * half)
        case .bottomHalf:        return CGRect(x: s.minX, y: s.maxY - s.height * half, width: s.width, height: s.height * half)
        case .topLeft:           return grid(2, 2, x: 0, y: 0)
        case .topRight:          return grid(2, 2, x: 1, y: 0)
        case .bottomLeft:        return grid(2, 2, x: 0, y: 1)
        case .bottomRight:       return grid(2, 2, x: 1, y: 1)
        case .firstThird:        return strip(3, 0)
        case .centerThird:       return strip(3, 1)
        case .lastThird:         return strip(3, 2)
        case .firstTwoThirds:    return strip(3, 0, span: 2)
        case .centerTwoThirds:   return strip(6, 1, span: 4)
        case .lastTwoThirds:     return strip(3, 1, span: 2)
        case .firstFourth:       return strip(4, 0)
        case .secondFourth:      return strip(4, 1)
        case .thirdFourth:       return strip(4, 2)
        case .lastFourth:        return strip(4, 3)
        case .firstThreeFourths: return strip(4, 0, span: 3)
        case .lastThreeFourths:  return strip(4, 1, span: 3)
        case .topLeftSixth:      return grid(3, 2, x: 0, y: 0)
        case .topCenterSixth:    return grid(3, 2, x: 1, y: 0)
        case .topRightSixth:     return grid(3, 2, x: 2, y: 0)
        case .bottomLeftSixth:   return grid(3, 2, x: 0, y: 1)
        case .bottomCenterSixth: return grid(3, 2, x: 1, y: 1)
        case .bottomRightSixth:  return grid(3, 2, x: 2, y: 1)
        case .maximize:          return s
        case .almostMaximize:    return s.insetBy(dx: s.width * 0.05, dy: s.height * 0.05)
        case .maximizeHeight:    return CGRect(x: w.minX, y: s.minY, width: w.width, height: s.height)
        case .center:            return CGRect(origin: CGPoint(x: s.midX - size.width / 2, y: s.midY - size.height / 2), size: size)
        case .moveLeft:          return CGRect(origin: CGPoint(x: s.minX, y: s.midY - size.height / 2), size: size)
        case .moveRight:         return CGRect(origin: CGPoint(x: s.maxX - size.width, y: s.midY - size.height / 2), size: size)
        case .moveUp:            return CGRect(origin: CGPoint(x: s.midX - size.width / 2, y: s.minY), size: size)
        case .moveDown:          return CGRect(origin: CGPoint(x: s.midX - size.width / 2, y: s.maxY - size.height), size: size)
        case .upperCenter:       return CGRect(origin: CGPoint(x: s.midX - size.width / 2, y: s.minY + (s.height - size.height) / 3), size: size)
        case .nudgeLeft:         return w.offsetBy(dx: -Self.sizeStep, dy: 0)
        case .nudgeRight:        return w.offsetBy(dx: Self.sizeStep, dy: 0)
        case .nudgeUp:           return w.offsetBy(dx: 0, dy: -Self.sizeStep)
        case .nudgeDown:         return w.offsetBy(dx: 0, dy: Self.sizeStep)
        case .larger:
            let grown = w.insetBy(dx: -Self.sizeStep, dy: -Self.sizeStep).intersection(s)
            return grown.isNull ? w : grown
        case .smaller:
            let shrunk = w.insetBy(dx: Self.sizeStep, dy: Self.sizeStep)
            return shrunk.width < s.width / 4 || shrunk.height < s.height / 4 ? w : shrunk
        case .nextDisplay, .previousDisplay, .nextSpace, .previousSpace, .restore, .minimize, .fullScreen, .close,
             .hideApp, .quitApp, .showMenu, .keyboardGrid, .floatOnTop, .unfloatAll, .stashLeft, .stashRight, .stashAll, .stashAllExceptFront,
             .toggleStashed, .cycleStashed, .unstashAll, .togglePin, .reflowPin,
             .winArrowLeft, .winArrowRight, .winArrowUp, .winArrowDown,
             .fillLeft, .fillRight, .tile2x2, .tile2x3, .cascadeAll, .cascadeApp, .appLeftHalf, .appRightHalf:
            return w // these need other windows; AppState handles them
        }
    }
}

/// Fill the Rest: the biggest empty strip beside a snapped window (left, right, above or below; ties favor
/// left/right), or nil if it's under 15% of the screen. With gaps, the strip keeps a full gap on every side.
func fillRestArea(placed f: CGRect, in s: CGRect, gap: CGFloat = 0) -> CGRect? {
    let area = s.insetBy(dx: gap / 2, dy: gap / 2), placed = f.insetBy(dx: -gap / 2, dy: -gap / 2)
    let strips = [
        CGRect(x: area.minX, y: area.minY, width: placed.minX - area.minX, height: area.height),
        CGRect(x: placed.maxX, y: area.minY, width: area.maxX - placed.maxX, height: area.height),
        CGRect(x: area.minX, y: area.minY, width: area.width, height: placed.minY - area.minY),
        CGRect(x: area.minX, y: placed.maxY, width: area.width, height: area.maxY - placed.maxY),
    ]
    var best: CGRect?
    for strip in strips where strip.width > 1 && strip.height > 1 {
        if strip.width * strip.height > (best.map { $0.width * $0.height } ?? 0) { best = strip }
    }
    guard let best, best.width * best.height >= area.width * area.height * 0.15 else { return nil }
    return best.insetBy(dx: gap / 2, dy: gap / 2)
}

/// The keyboard grid's layout: keys sit where their cells do (Q W E R / A S D F / Z X C V).
enum KeyGrid {
    struct Cell: Equatable {
        let column: Int, row: Int
    }

    static let columns = 4, rows = 3
    static let labels = [["Q", "W", "E", "R"], ["A", "S", "D", "F"], ["Z", "X", "C", "V"]]
    /// Physical key positions (ANSI virtual key codes), so the grid matches the keyboard in any layout.
    static let keyCodes = [[12, 13, 14, 15], [0, 1, 2, 3], [6, 7, 8, 9]]

    static func cell(forKey code: Int) -> Cell? {
        for (row, codes) in keyCodes.enumerated() {
            if let column = codes.firstIndex(of: code) { return Cell(column: column, row: row) }
        }
        return nil
    }

    /// The rectangle spanning two cells in screen area `s` (the same cell twice fills just that cell).
    static func frame(from a: Cell, to b: Cell, in s: CGRect, gap: CGFloat = 0) -> CGRect {
        let area = s.insetBy(dx: gap / 2, dy: gap / 2)
        let width = area.width / CGFloat(columns), height = area.height / CGFloat(rows)
        let left = min(a.column, b.column), top = min(a.row, b.row)
        return CGRect(x: area.minX + CGFloat(left) * width, y: area.minY + CGFloat(top) * height,
                      width: CGFloat(abs(a.column - b.column) + 1) * width,
                      height: CGFloat(abs(a.row - b.row) + 1) * height)
            .insetBy(dx: gap / 2, dy: gap / 2)
    }
}

/// Win Arrow Keys: like Windows, each arrow moves one step from where the window is now
/// (e.g. Right → right half, then Up → top right). `nil` from Down means restore.
func winArrowAction(_ arrow: Action, from current: Action?) -> Action? {
    switch (arrow, current) {
    case (.winArrowLeft, .topRight): .topLeft
    case (.winArrowLeft, .bottomRight): .bottomLeft
    case (.winArrowRight, .topLeft): .topRight
    case (.winArrowRight, .bottomLeft): .bottomRight
    case (.winArrowLeft, _): .leftHalf
    case (.winArrowRight, _): .rightHalf
    case (.winArrowUp, .leftHalf): .topLeft
    case (.winArrowUp, .rightHalf): .topRight
    case (.winArrowUp, .bottomLeft): .leftHalf
    case (.winArrowUp, .bottomRight): .rightHalf
    case (.winArrowUp, _): .maximize
    case (.winArrowDown, .leftHalf): .bottomLeft
    case (.winArrowDown, .rightHalf): .bottomRight
    case (.winArrowDown, .topLeft): .leftHalf
    case (.winArrowDown, .topRight): .rightHalf
    case (.winArrowDown, .maximize): nil
    case (.winArrowDown, _): .minimize
    default: nil
    }
}

/// Drag-to-edge snap areas, each configurable in Settings.
enum SnapArea: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight, left, right, top, bottom

    /// Setting values are an action name, "thirds" (the bottom edge's left/center/right thirds) or "none".
    var defaultSetting: String {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: rawValue
        case .left: Action.leftHalf.rawValue
        case .right: Action.rightHalf.rawValue
        case .top: Action.maximize.rawValue
        case .bottom: "thirds"
        }
    }

    /// Portrait displays have their own settings.
    func prefKey(portrait: Bool = false) -> String { (portrait ? "snapArea.portrait." : "snapArea.") + rawValue }
}

/// The snap area under the cursor, using the screen's full frame (menu bar included).
func snapArea(at p: CGPoint, in s: CGRect, margin: CGFloat = 5, corner: CGFloat = 25) -> SnapArea? {
    let left = p.x <= s.minX + margin, right = p.x >= s.maxX - 1 - margin
    let top = p.y <= s.minY + margin, bottom = p.y >= s.maxY - 1 - margin
    let nearLeft = p.x <= s.minX + corner, nearRight = p.x >= s.maxX - 1 - corner
    let nearTop = p.y <= s.minY + corner, nearBottom = p.y >= s.maxY - 1 - corner

    if (left && nearTop) || (top && nearLeft) { return .topLeft }
    if (right && nearTop) || (top && nearRight) { return .topRight }
    if (left && nearBottom) || (bottom && nearLeft) { return .bottomLeft }
    if (right && nearBottom) || (bottom && nearRight) { return .bottomRight }
    if left { return .left }
    if right { return .right }
    if top { return .top }
    return bottom ? .bottom : nil
}

/// The action for the snap area under the cursor, given each area's setting.
func snapAction(at p: CGPoint, in s: CGRect, setting: (SnapArea) -> String = { $0.defaultSetting }) -> Action? {
    guard let area = snapArea(at: p, in: s) else { return nil }
    switch setting(area) {
    case "none": return nil
    case "thirds":
        let x = (p.x - s.minX) / s.width
        return x < 1 / 3 ? .firstThird : x < 2 / 3 ? .centerThird : .lastThird
    case let name: return Action(rawValue: name)
    }
}

/// Window Throw sectors, clockwise from the right: Right, Down Right, Down, Down Left, Left, Up Left, Up, Up Right.
enum ThrowSectors {
    static let names = ["Right", "Down Right", "Down", "Down Left", "Left", "Up Left", "Up", "Up Right"]
    static let short: [Action] = [.rightHalf, .bottomRight, .bottomHalf, .bottomLeft, .leftHalf, .topLeft, .topHalf, .topRight]
    static let long: [Action] = [.lastTwoThirds, .bottomRight, .center, .bottomLeft, .firstTwoThirds, .topLeft, .maximize, .topRight]

    static func prefKey(sector: Int, long: Bool, portrait: Bool = false) -> String {
        "throw\(portrait ? "Portrait" : "")\(long ? "Long" : "Short")\(sector)"
    }
}

/// Window Throw: the pie sector of the cursor offset picks the action; a long throw uses the outer ring.
/// `setting` returns the configured action name for a sector ("none" disables it).
func throwAction(dx: CGFloat, dy: CGFloat, long: Bool,
                 setting: (Int, Bool) -> String = { ($1 ? ThrowSectors.long : ThrowSectors.short)[$0].rawValue }) -> Action? {
    // 45° sectors clockwise from the right (y grows down, so "down" is sector 2).
    let angle = (atan2(dy, dx) + .pi / 8 + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
    return Action(rawValue: setting(Int(angle / (.pi / 4)) % 8, long))
}

/// After a window edge is dragged from `old` to `new`, windows that were against that edge follow it.
/// `tolerance` should cover the gap between windows.
func adjacentFrames(old: CGRect, new: CGRect, others: [CGRect], tolerance: CGFloat = 4) -> [Int: CGRect] {
    var result: [Int: CGRect] = [:]
    for (i, o) in others.enumerated() {
        let besideVertically = o.minY < old.maxY && o.maxY > old.minY
        let besideHorizontally = o.minX < old.maxX && o.maxX > old.minX
        var minX = o.minX, maxX = o.maxX, minY = o.minY, maxY = o.maxY
        let gapRight = o.minX - old.maxX, gapLeft = old.minX - o.maxX
        let gapBelow = o.minY - old.maxY, gapAbove = old.minY - o.maxY
        if besideVertically, new.maxX != old.maxX, abs(gapRight) <= tolerance { minX = new.maxX + gapRight }
        if besideVertically, new.minX != old.minX, abs(gapLeft) <= tolerance { maxX = new.minX - gapLeft }
        if besideHorizontally, new.maxY != old.maxY, abs(gapBelow) <= tolerance { minY = new.maxY + gapBelow }
        if besideHorizontally, new.minY != old.minY, abs(gapAbove) <= tolerance { maxY = new.minY - gapAbove }
        let f = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if f != o, f.width >= 100, f.height >= 60 { result[i] = f }
    }
    return result
}

/// When a screen's usable area changes (Dock shown, hidden or moved), edges flush with the old area follow the new one.
func adjusted(_ f: CGRect, from old: CGRect, to new: CGRect, tolerance: CGFloat = 2) -> CGRect? {
    let minX = abs(f.minX - old.minX) <= tolerance ? new.minX : f.minX
    let maxX = abs(f.maxX - old.maxX) <= tolerance ? new.maxX : f.maxX
    let minY = abs(f.minY - old.minY) <= tolerance ? new.minY : f.minY
    let maxY = abs(f.maxY - old.maxY) <= tolerance ? new.maxY : f.maxY
    let r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    return r == f ? nil : r
}

/// Quick Throw: the direction the cursor was travelling when the modifier was tapped.
func quickThrowAction(dx: CGFloat, dy: CGFloat, minDistance: CGFloat = 40) -> Action? {
    guard hypot(dx, dy) >= minDistance else { return nil }
    if abs(dx) > abs(dy) { return dx < 0 ? .leftHalf : .rightHalf }
    return dy < 0 ? .maximize : .minimize
}

/// Fill Left/Right: from the screen edge to the nearest other window beyond a quarter of the screen,
/// or half the screen when nothing is in the way.
func fillFrame(left: Bool, others: [CGRect], in s: CGRect) -> CGRect {
    let onScreen = others.filter { $0.intersects(s) }
    if left {
        let edge = onScreen.map(\.minX).filter { $0 > s.minX + s.width / 4 }.min() ?? s.midX
        return CGRect(x: s.minX, y: s.minY, width: min(edge, s.maxX) - s.minX, height: s.height)
    }
    let edge = max(onScreen.map(\.maxX).filter { $0 < s.maxX - s.width / 4 }.max() ?? s.midX, s.minX)
    return CGRect(x: edge, y: s.minY, width: s.maxX - edge, height: s.height)
}

/// Grid cells for tiling, row by row; windows beyond the cell count aren't placed.
func tileFrames(count: Int, columns: Int, rows: Int, in s: CGRect, gap: CGFloat = 0) -> [CGRect] {
    let area = s.insetBy(dx: gap / 2, dy: gap / 2)
    let width = area.width / CGFloat(columns), height = area.height / CGFloat(rows)
    return (0..<min(count, columns * rows)).map { i in
        CGRect(x: area.minX + CGFloat(i % columns) * width, y: area.minY + CGFloat(i / columns) * height,
               width: width, height: height).insetBy(dx: gap / 2, dy: gap / 2)
    }
}

/// Cascade: each window offset by `step`, shrunk if needed so the last one still fits.
func cascadeFrames(sizes: [CGSize], in s: CGRect, step: CGFloat = 30) -> [CGRect] {
    let room = CGFloat(max(sizes.count - 1, 0)) * step
    return sizes.enumerated().map { i, size in
        CGRect(x: s.minX + CGFloat(i) * step, y: s.minY + CGFloat(i) * step,
               width: min(size.width, s.width - room), height: min(size.height, s.height - room))
    }
}

/// Keeps the window's position and size proportional when moving between screens.
func map(_ w: CGRect, from a: CGRect, to b: CGRect) -> CGRect {
    let sx = b.width / a.width, sy = b.height / a.height
    return CGRect(x: b.minX + (w.minX - a.minX) * sx, y: b.minY + (w.minY - a.minY) * sy,
                  width: w.width * sx, height: w.height * sy)
}

/// Converts between AppKit (bottom-left origin) and Accessibility coordinates; the flip is its own inverse.
func flip(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
}

/// Index of the screen the window overlaps most, falling back to the first.
func screenIndex(for w: CGRect, in screens: [CGRect]) -> Int {
    let areas = screens.map { s -> CGFloat in
        let i = s.intersection(w)
        return i.isNull ? 0 : i.width * i.height
    }
    return areas.indices.max { areas[$0] < areas[$1] } ?? 0
}

extension CGRect {
    /// Apps round frames, so compare with a little slack.
    func isClose(to other: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
