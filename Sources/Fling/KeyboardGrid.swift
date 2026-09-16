import AppKit

/// Tactile-style placement: a lettered grid appears over the screen; type two letters to span the focused
/// window across those cells (the same letter twice fills one cell). After the first letter, pointing at a cell
/// outlines the area that cell's letter would give. Esc, a click or any other key cancels.
@MainActor
final class KeyboardGrid {
    private unowned let state: AppState
    private let panel: NSPanel
    private var cellLayers: [[CALayer]] = []
    private var colors = Colors()
    private var target: (window: Window, area: CGRect)?
    private var first: KeyGrid.Cell?

    var isShowing: Bool { target != nil }

    init(state: AppState) {
        self.state = state
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        panel.contentView = view
    }

    func show(for window: Window) {
        guard let frame = window.frame, let area = state.usableArea(for: window, frame: frame),
              let primary = NSScreen.screens.first
        else { return NSSound.beep() }
        target = (window, area)
        first = nil
        state.capturingKeys = true // a held shortcut modifier plus a letter mustn't trigger other Fling hotkeys
        panel.setFrame(flip(area, primaryHeight: primary.frame.height), display: false)
        buildCells(size: area.size, scale: primary.backingScaleFactor)
        panel.orderFrontRegardless()
    }

    /// Handles a key press while the grid is showing. Returns true when the key was used (and should be swallowed).
    func handleKey(_ keyCode: Int) -> Bool {
        guard let target else { return false }
        guard let cell = KeyGrid.cell(forKey: keyCode) else {
            hide()
            return true
        }
        guard let first else {
            first = cell
            paint(span: (cell, hoveredCell(at: CGEvent(source: nil)?.location) ?? cell))
            return true
        }
        let gap = CGFloat(UserDefaults.standard.integer(forKey: Prefs.gap))
        let frame = KeyGrid.frame(from: first, to: cell, in: target.area, gap: gap)
        state.place(target.window, at: frame, key: "keyboardGrid")
        hide()
        state.fillRest?.offer(after: target.window, placedAt: frame)
        return true
    }

    func hide() {
        guard isShowing else { return }
        panel.orderOut(nil)
        target = nil
        first = nil
        state.capturingKeys = false
    }

    /// After the first letter, outlines the span to the cell under the cursor.
    func mouseMoved(to p: CGPoint) {
        guard let first else { return }
        paint(span: (first, hoveredCell(at: p) ?? first))
    }

    private func hoveredCell(at p: CGPoint?) -> KeyGrid.Cell? {
        guard let p, let area = target?.area, area.contains(p) else { return nil }
        let column = min(Int((p.x - area.minX) / (area.width / CGFloat(KeyGrid.columns))), KeyGrid.columns - 1)
        let row = min(Int((p.y - area.minY) / (area.height / CGFloat(KeyGrid.rows))), KeyGrid.rows - 1)
        return KeyGrid.Cell(column: column, row: row)
    }

    /// Layer colors, resolved for the current light or dark appearance each time the grid is shown.
    private struct Colors {
        var cell = CGColor.clear, cellBorder = CGColor.clear, keycap = CGColor.clear, keycapBorder = CGColor.clear
        var text = CGColor.clear, chosen = CGColor.clear, span = CGColor.clear, accent = CGColor.clear
    }

    private func buildCells(size: CGSize, scale: CGFloat) {
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            colors = Colors(cell: NSColor.windowBackgroundColor.withAlphaComponent(0.55).cgColor,
                            cellBorder: NSColor.labelColor.withAlphaComponent(0.15).cgColor,
                            keycap: NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor,
                            keycapBorder: NSColor.labelColor.withAlphaComponent(0.2).cgColor,
                            text: NSColor.labelColor.cgColor,
                            chosen: NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor,
                            span: NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor,
                            accent: NSColor.controlAccentColor.cgColor)
        }
        panel.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        cellLayers = (0..<KeyGrid.rows).map { row in
            (0..<KeyGrid.columns).map { column in
                let cell = KeyGrid.Cell(column: column, row: row)
                let rect = KeyGrid.frame(from: cell, to: cell, in: CGRect(origin: .zero, size: size), gap: 16)
                let layer = CALayer()
                // Layers use a bottom-left origin.
                layer.frame = CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
                layer.cornerRadius = 16
                layer.borderWidth = 1

                let keycap = CALayer()
                keycap.frame = CGRect(x: (rect.width - 72) / 2, y: (rect.height - 72) / 2, width: 72, height: 72)
                keycap.cornerRadius = 16
                keycap.borderWidth = 1
                keycap.backgroundColor = colors.keycap
                keycap.borderColor = colors.keycapBorder
                let label = CATextLayer()
                label.string = KeyGrid.labels[row][column]
                label.font = NSFont.systemFont(ofSize: 32, weight: .medium)
                label.fontSize = 32
                label.alignmentMode = .center
                label.foregroundColor = colors.text
                label.contentsScale = scale
                label.frame = CGRect(x: 0, y: (72 - 40) / 2, width: 72, height: 40)
                keycap.addSublayer(label)
                layer.addSublayer(keycap)
                panel.contentView?.layer?.addSublayer(layer)
                return layer
            }
        }
        paint(span: nil)
    }

    /// Colors every cell: the first letter's cell, the cells a second letter would add, or neither.
    private func paint(span: (from: KeyGrid.Cell, to: KeyGrid.Cell)?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        for (row, layers) in cellLayers.enumerated() {
            for (column, layer) in layers.enumerated() {
                let chosen = span.map { $0.from == KeyGrid.Cell(column: column, row: row) } ?? false
                let inSpan = span.map { (min($0.from.column, $0.to.column)...max($0.from.column, $0.to.column)).contains(column)
                    && (min($0.from.row, $0.to.row)...max($0.from.row, $0.to.row)).contains(row) } ?? false
                layer.backgroundColor = chosen ? colors.chosen : inSpan ? colors.span : colors.cell
                layer.borderColor = inSpan ? colors.accent : colors.cellBorder
                layer.borderWidth = inSpan ? 2 : 1
            }
        }
        CATransaction.commit()
    }
}
