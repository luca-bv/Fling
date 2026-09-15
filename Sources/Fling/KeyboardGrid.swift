import AppKit

/// Tactile-style placement: a lettered grid appears over the screen; type two letters to span the focused
/// window across those cells (the same letter twice fills one cell). Esc, a click or any other key cancels.
@MainActor
final class KeyboardGrid {
    private unowned let state: AppState
    private let panel: NSPanel
    private var cellLayers: [[CALayer]] = []
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
              let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
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
            highlight(cell)
            return true
        }
        let gap = CGFloat(UserDefaults.standard.integer(forKey: Prefs.gap))
        state.place(target.window, at: KeyGrid.frame(from: first, to: cell, in: target.area, gap: gap), key: "keyboardGrid")
        hide()
        return true
    }

    func hide() {
        guard isShowing else { return }
        panel.orderOut(nil)
        target = nil
        first = nil
        state.capturingKeys = false
    }

    private func buildCells(size: CGSize, scale: CGFloat) {
        panel.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        cellLayers = (0..<KeyGrid.rows).map { row in
            (0..<KeyGrid.columns).map { column in
                let cell = KeyGrid.Cell(column: column, row: row)
                let rect = KeyGrid.frame(from: cell, to: cell, in: CGRect(origin: .zero, size: size), gap: 16)
                let layer = CALayer()
                // Layers use a bottom-left origin.
                layer.frame = CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
                layer.cornerRadius = 14
                layer.borderWidth = 2
                layer.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
                layer.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor

                let label = CATextLayer()
                label.string = KeyGrid.labels[row][column]
                label.font = NSFont.systemFont(ofSize: 44, weight: .semibold)
                label.fontSize = 44
                label.alignmentMode = .center
                label.foregroundColor = NSColor.white.cgColor
                label.contentsScale = scale
                label.frame = CGRect(x: 0, y: (rect.height - 54) / 2, width: rect.width, height: 54)
                layer.addSublayer(label)
                panel.contentView?.layer?.addSublayer(layer)
                return layer
            }
        }
    }

    private func highlight(_ cell: KeyGrid.Cell) {
        cellLayers[cell.row][cell.column].backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
    }
}
