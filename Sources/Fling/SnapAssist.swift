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
    /// Marks the row under the cursor.
    private var hoverHighlight: NSView?
    /// Panel frame and the space to fill, in Accessibility coordinates.
    private var panelFrame = CGRect.null
    private(set) var area = CGRect.null
    /// What placed the window, so the panel can be switched off per source. Gestures set it before placing;
    /// everything else (shortcuts, the menu, flingctl, URLs) leaves it at .shortcut. Cleared by the next offer.
    var nextSource = Source.shortcut

    enum Source: String, CaseIterable {
        case shortcut, drag, thrown
        var prefKey: String { "snapAssist." + rawValue }
    }
    /// The smoke test checks the panel once, then stops it appearing for the rest of the run.
    var suppressed = false
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
        let source = nextSource
        nextSource = .shortcut
        guard !suppressed, UserDefaults.standard.bool(forKey: Prefs.snapAssist),
              UserDefaults.standard.bool(forKey: source.prefKey),
              let area = state.freeArea(beside: frame, window: window),
              let primary = NSScreen.screens.first else { return }
        let candidates = Array(Window.visible().filter { $0.element != window.element }.prefix(Self.digitKeys.count))
        guard !candidates.isEmpty else { return }

        let height = Self.header + CGFloat(candidates.count) * Self.rowHeight + Self.padding
        let size = CGSize(width: min(Self.width, area.width - 20), height: min(height, area.height - 20))
        panelFrame = CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        self.area = area
        choices = candidates
        let side = area.minX >= frame.maxX - 1 ? "on the right" : area.maxX <= frame.minX + 1 ? "on the left"
            : area.minY >= frame.maxY - 1 ? "below" : "above"
        panel.contentView = content(for: candidates, size: size, title: "Fill the space \(side)")
        panel.setFrame(flip(panelFrame, primaryHeight: primary.frame.height), display: true)
        panel.orderFrontRegardless()
        panel.invalidateShadow() // the content and size change with every offer
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

    /// Highlights the row under the cursor, so it's clear what a click picks.
    func mouseMoved(to p: CGPoint) {
        guard isShowing, let hoverHighlight else { return }
        let row = Int((p.y - panelFrame.minY - Self.header) / Self.rowHeight)
        let over = panelFrame.contains(p) && p.y >= panelFrame.minY + Self.header && row < choices.count
        hoverHighlight.isHidden = !over
        if over { hoverHighlight.frame.origin.y = rowY(row) }
    }

    /// A row's bottom edge in the panel's view (AppKit views use a bottom-left origin, so rows go from the top down).
    private func rowY(_ index: Int) -> CGFloat {
        panel.frame.height - Self.header - CGFloat(index + 1) * Self.rowHeight
    }

    private func choose(_ index: Int) {
        let window = choices[index], target = area
        hide()
        state.place(window, at: target, key: "snapAssist")
        window.raise()
    }

    private func content(for windows: [Window], size: CGSize, title: String) -> NSView {
        let background = roundedMaterial(.popover, cornerRadius: 12)
        background.frame = CGRect(origin: .zero, size: size)
        // Layer colors don't follow appearance changes on their own; resolve them for the current one.
        var keycapBorder = CGColor.clear
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            keycapBorder = NSColor.tertiaryLabelColor.cgColor
        }

        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.frame = CGRect(x: 14, y: size.height - Self.header + 10, width: size.width - 70, height: 18)
        background.addSubview(header)
        let escape = NSTextField(labelWithString: "esc")
        escape.font = .systemFont(ofSize: 11)
        escape.textColor = .tertiaryLabelColor
        escape.alignment = .right
        escape.frame = CGRect(x: size.width - 54, y: size.height - Self.header + 11, width: 40, height: 16)
        background.addSubview(escape)

        let highlight = NSView(frame: CGRect(x: 6, y: 0, width: size.width - 12, height: Self.rowHeight))
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 7
        highlight.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        highlight.isHidden = true
        background.addSubview(highlight)
        hoverHighlight = highlight

        for (i, window) in windows.enumerated() {
            let y = size.height - Self.header - CGFloat(i + 1) * Self.rowHeight
            let keycap = NSView(frame: CGRect(x: 14, y: y + 7, width: 20, height: 20))
            keycap.wantsLayer = true
            keycap.layer?.cornerRadius = 5
            keycap.layer?.borderWidth = 1
            keycap.layer?.borderColor = keycapBorder
            let number = NSTextField(labelWithString: "\(i + 1)")
            number.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            number.textColor = .secondaryLabelColor
            number.alignment = .center
            number.frame = CGRect(x: 0, y: 3, width: 20, height: 14)
            keycap.addSubview(number)
            background.addSubview(keycap)

            let app = NSRunningApplication(processIdentifier: window.pid)
            let icon = NSImageView(frame: CGRect(x: 44, y: y + 6, width: 22, height: 22))
            icon.image = app?.icon
            background.addSubview(icon)

            let name = NSMutableAttributedString(string: app?.localizedName ?? "Window",
                                                 attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
            if !window.title.isEmpty {
                name.append(NSAttributedString(string: "  " + window.title,
                                               attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]))
            }
            let label = NSTextField(labelWithAttributedString: name)
            label.lineBreakMode = .byTruncatingTail
            label.frame = CGRect(x: 74, y: y + 8, width: size.width - 88, height: 18)
            background.addSubview(label)
        }
        return background
    }
}
