import AppKit

/// Snap Assist, as on Windows: after a window snaps to part of the screen, a panel in the empty space lists the
/// other windows; click one (or press its number) to fill that space. Esc, a click elsewhere or any other key dismisses it.
/// Shows app icons and titles rather than thumbnails, so no Screen Recording permission is needed.
@MainActor
final class SnapAssist {
    private static let width: CGFloat = 340, header: CGFloat = 38, rowHeight: CGFloat = 34, padding: CGFloat = 8
    /// ANSI key codes for 1–9.
    private static let digitKeys = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    private unowned let state: AppState
    private let panel: NSPanel
    private var choices: [Window] = []
    /// Panel frame and the space to fill, in Accessibility coordinates.
    private var panelFrame = CGRect.null
    private(set) var area = CGRect.null
    var isShowing: Bool { !choices.isEmpty }

    init(state: AppState) {
        self.state = state
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true // clicks are read from Fling's event tap, so the panel never takes focus
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
    }

    func offer(after window: Window, placedAt frame: CGRect) {
        hide()
        guard UserDefaults.standard.bool(forKey: Prefs.snapAssist), let area = state.freeArea(beside: frame, window: window),
              let primary = NSScreen.screens.first else { return }
        let candidates = Array(Window.visible().filter { $0.element != window.element }.prefix(Self.digitKeys.count))
        guard !candidates.isEmpty else { return }

        let height = Self.header + CGFloat(candidates.count) * Self.rowHeight + Self.padding
        let size = CGSize(width: min(Self.width, area.width - 20), height: min(height, area.height - 20))
        panelFrame = CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        self.area = area
        choices = candidates
        panel.contentView = content(for: candidates, size: size)
        panel.setFrame(flip(panelFrame, primaryHeight: primary.frame.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        guard isShowing else { return }
        panel.orderOut(nil)
        choices = []
    }

    /// Returns true when the key was used (and should be swallowed); any other key dismisses the panel.
    func handleKey(_ keyCode: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard isShowing else { return false }
        if keyCode == 53, modifiers.isEmpty { // Esc
            hide()
            return true
        }
        if modifiers.isEmpty, let index = Self.digitKeys.firstIndex(of: keyCode), index < choices.count {
            choose(index)
            return true
        }
        hide()
        return false
    }

    /// Returns true when the click picked a window (and should be swallowed); clicks elsewhere dismiss the panel.
    func handleClick(at p: CGPoint) -> Bool {
        guard isShowing else { return false }
        let row = Int((p.y - panelFrame.minY - Self.header) / Self.rowHeight)
        guard panelFrame.contains(p), p.y >= panelFrame.minY + Self.header, row < choices.count else {
            hide()
            return false
        }
        choose(row)
        return true
    }

    private func choose(_ index: Int) {
        let window = choices[index], target = area
        hide()
        state.place(window, at: target, key: "snapAssist")
        window.raise()
    }

    private func content(for windows: [Window], size: CGSize) -> NSView {
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12

        // AppKit views use a bottom-left origin, so rows are laid out from the top down.
        let title = NSTextField(labelWithString: "Fill the space with…")
        title.font = .boldSystemFont(ofSize: 13)
        title.frame = CGRect(x: 14, y: size.height - Self.header + 8, width: size.width - 28, height: 20)
        background.addSubview(title)

        for (i, window) in windows.enumerated() {
            let y = size.height - Self.header - CGFloat(i + 1) * Self.rowHeight
            let app = NSRunningApplication(processIdentifier: window.pid)
            let icon = NSImageView(frame: CGRect(x: 14, y: y + 5, width: 24, height: 24))
            icon.image = app?.icon
            background.addSubview(icon)

            let name = window.title.isEmpty ? (app?.localizedName ?? "Window") : "\(app?.localizedName ?? "") — \(window.title)"
            let label = NSTextField(labelWithString: name)
            label.lineBreakMode = .byTruncatingTail
            label.frame = CGRect(x: 46, y: y + 8, width: size.width - 90, height: 18)
            background.addSubview(label)

            let key = NSTextField(labelWithString: "\(i + 1)")
            key.textColor = .secondaryLabelColor
            key.alignment = .right
            key.frame = CGRect(x: size.width - 38, y: y + 8, width: 24, height: 18)
            background.addSubview(key)
        }
        return background
    }
}
