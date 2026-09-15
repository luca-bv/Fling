import AppKit
import SwiftUI

/// Small template images for menus and Settings. Actions that place a window draw the area they fill on a
/// miniature screen, straight from `Action.frame`, so every glyph matches what the action does; the rest use SF Symbols.
/// Images are drawn on demand and cached (a few KB in total).
enum Glyph {
    private static var cache: [Action: NSImage] = [:]

    static func image(for action: Action) -> NSImage {
        if let cached = cache[action] { return cached }
        let image = symbol(for: action).flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: action.title) }
            ?? drawn(action)
        cache[action] = image
        return image
    }

    /// The glyph shown next to a category's submenu: a typical action's, picked so similar categories look different.
    static func image(for category: Action.Category) -> NSImage? {
        let typical: [Action.Category: Action] = [.halves: .leftHalf, .thirds: .centerThird, .fourths: .lastFourth, .window: .minimize]
        return (typical[category] ?? Action.allCases.first { $0.category == category }).map(image(for:))
    }

    /// Fling's menu bar icon: a window flung against the right side of a screen, with two motion lines.
    static let menuBar: NSImage = {
        let image = NSImage(size: CGSize(width: 22, height: 16), flipped: true) { bounds in
            NSColor.black.set()
            let screen = bounds.insetBy(dx: 1.5, dy: 2)
            let outline = NSBezierPath(roundedRect: screen, xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.5
            outline.stroke()
            let window = CGRect(x: screen.maxX - 2.5 - screen.width * 0.36, y: screen.minY + 2.5,
                                width: screen.width * 0.36, height: screen.height - 5)
            NSBezierPath(roundedRect: window, xRadius: 1.5, yRadius: 1.5).fill()
            for (y, start) in [(window.minY + 2, screen.minX + 3), (window.maxY - 2, screen.minX + 4.5)] {
                let line = NSBezierPath()
                line.move(to: CGPoint(x: start, y: y))
                line.line(to: CGPoint(x: window.minX - 2, y: y))
                line.lineWidth = 1.5
                line.lineCapStyle = .round
                line.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// A miniature screen with the action's area filled, using a half-size centered window for actions that keep its size.
    private static func drawn(_ action: Action) -> NSImage {
        // App halves place every window of an app like the plain halves do.
        let shape: Action = action == .appLeftHalf ? .leftHalf : action == .appRightHalf ? .rightHalf : action
        let image = NSImage(size: CGSize(width: 18, height: 14), flipped: true) { bounds in
            NSColor.black.set()
            let screen = bounds.insetBy(dx: 1, dy: 1.5)
            let outline = NSBezierPath(roundedRect: screen.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.5, yRadius: 1.5)
            outline.lineWidth = 1
            outline.stroke()
            let area = screen.insetBy(dx: 1.75, dy: 1.75)
            let window = CGRect(x: area.minX + area.width / 4, y: area.minY + area.height / 4, width: area.width / 2, height: area.height / 2)
            NSBezierPath(roundedRect: shape.frame(for: window, in: area), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func symbol(for action: Action) -> String? {
        switch action {
        case .winArrowLeft: "arrow.left.square"
        case .winArrowRight: "arrow.right.square"
        case .winArrowUp: "arrow.up.square"
        case .winArrowDown: "arrow.down.square"
        case .fillLeft: "rectangle.lefthalf.inset.filled.arrow.left"
        case .fillRight: "rectangle.righthalf.inset.filled.arrow.right"
        case .larger: "arrow.up.left.and.arrow.down.right"
        case .smaller: "arrow.down.right.and.arrow.up.left"
        case .nudgeLeft: "arrow.left"
        case .nudgeRight: "arrow.right"
        case .nudgeUp: "arrow.up"
        case .nudgeDown: "arrow.down"
        case .nextDisplay: "arrow.right.to.line"
        case .previousDisplay: "arrow.left.to.line"
        case .nextSpace, .previousSpace: "macwindow.on.rectangle"
        case .restore: "arrow.uturn.backward"
        case .minimize: "minus.square"
        case .fullScreen: "arrow.up.backward.and.arrow.down.forward"
        case .close: "xmark.square"
        case .hideApp: "eye.slash"
        case .quitApp: "power"
        case .showMenu: "filemenu.and.cursorarrow"
        case .keyboardGrid: "keyboard"
        case .floatOnTop: "pin"
        case .unfloatAll: "pin.slash"
        case .stashLeft: "sidebar.left"
        case .stashRight: "sidebar.right"
        case .stashAll, .stashAllExceptFront: "tray.and.arrow.down"
        case .toggleStashed: "rectangle.on.rectangle"
        case .cycleStashed: "arrow.triangle.2.circlepath"
        case .unstashAll: "tray.and.arrow.up"
        case .togglePin: "sidebar.squares.right"
        case .reflowPin: "arrow.clockwise"
        case .tile2x2: "square.grid.2x2"
        case .tile2x3: "square.grid.3x2"
        case .cascadeAll, .cascadeApp: "square.3.layers.3d.down.right"
        default: nil
        }
    }
}

/// An action's title with its glyph, for menus, pickers and Settings rows.
struct ActionLabel: View {
    let action: Action

    var body: some View {
        Label { Text(action.title) } icon: { Image(nsImage: Glyph.image(for: action)) }
            .labelStyle(.titleAndIcon)
    }
}
