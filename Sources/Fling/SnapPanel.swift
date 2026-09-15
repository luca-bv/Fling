import AppKit

/// A strip of layout tiles shown near the top of the screen while dragging a window; drop on a tile to snap.
@MainActor
final class SnapPanel {
    static let actions: [Action] = [
        .leftHalf, .rightHalf, .maximize, .center, .firstThird, .centerThird, .lastThird,
        .topLeft, .topRight, .bottomLeft, .bottomRight,
    ]

    private static let tile = CGSize(width: 54, height: 36)
    private static let spacing: CGFloat = 8
    private let panel: NSPanel
    private var tileLayers: [CALayer] = []
    /// Panel frame in Accessibility coordinates.
    private var frame = CGRect.null

    init() {
        let size = CGSize(width: CGFloat(Self.actions.count) * (Self.tile.width + Self.spacing) + Self.spacing,
                          height: Self.tile.height + 2 * Self.spacing)
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        panel.contentView = background

        for (i, action) in Self.actions.enumerated() {
            let tile = CALayer()
            tile.frame = CGRect(x: Self.spacing + CGFloat(i) * (Self.tile.width + Self.spacing), y: Self.spacing,
                                width: Self.tile.width, height: Self.tile.height)
            tile.cornerRadius = 5
            tile.borderWidth = 1.5
            tile.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
            // The action's area inside a tiny "screen"; layers use a bottom-left origin, so flip it.
            let area = action.frame(for: CGRect(x: 0, y: 0, width: 30, height: 20),
                                    in: CGRect(origin: .zero, size: Self.tile).insetBy(dx: 4, dy: 4))
            let fill = CALayer()
            fill.frame = CGRect(x: area.minX, y: Self.tile.height - area.maxY, width: area.width, height: area.height)
            fill.cornerRadius = 2
            fill.backgroundColor = NSColor.white.withAlphaComponent(0.8).cgColor
            tile.addSublayer(fill)
            background.layer?.addSublayer(tile)
            tileLayers.append(tile)
        }
    }

    func show(on screen: Screen) {
        guard !panel.isVisible, let primary = NSScreen.screens.first else { return }
        let size = panel.frame.size
        frame = CGRect(x: screen.visible.midX - size.width / 2, y: screen.visible.minY + 24, width: size.width, height: size.height)
        panel.setFrame(flip(frame, primaryHeight: primary.frame.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        highlight(nil)
        if panel.isVisible { panel.orderOut(nil) }
        frame = .null
    }

    /// The action of the tile under the cursor (highlighting it), if any.
    func action(at p: CGPoint) -> Action? {
        guard panel.isVisible, frame.contains(p) else { return highlight(nil) }
        let x = p.x - frame.minX - Self.spacing
        let index = Int(x / (Self.tile.width + Self.spacing))
        let insideTile = x.truncatingRemainder(dividingBy: Self.tile.width + Self.spacing) <= Self.tile.width
        return highlight(insideTile && Self.actions.indices.contains(index) ? index : nil)
    }

    @discardableResult
    private func highlight(_ index: Int?) -> Action? {
        for (i, layer) in tileLayers.enumerated() {
            layer.backgroundColor = i == index ? NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor : nil
        }
        return index.map { Self.actions[$0] }
    }
}
