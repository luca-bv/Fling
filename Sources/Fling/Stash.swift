import AppKit

/// Tucks windows against the left or right screen edge and slides them out while the cursor touches that edge.
/// (The idea comes from the app Tuck. Up/down stashing is skipped: macOS won't move windows under the menu bar.)
@MainActor
final class Stash {
    enum Edge { case left, right }

    private struct Entry {
        let window: Window
        let shown: CGRect
        let hidden: CGRect
        let edge: Edge
        let screen: CGRect
        /// Optional colored tab on the screen edge; hovering it reveals only this window.
        var tab: (overlay: Overlay, frame: CGRect)?
        var revealed = false
        /// Shown by Toggle or Cycle rather than by hovering, so moving the cursor away doesn't tuck it back.
        var held = false
    }

    /// How much of a stashed window stays visible.
    private static let peek: CGFloat = 8
    private var entries: [Entry] = []
    private var pendingReveal: Task<Void, Never>?

    var isEmpty: Bool { entries.isEmpty }

    /// Stashes a window against `edge`, or the nearer edge when nil.
    func stash(_ window: Window, to edge: Edge? = nil, tabColor: NSColor? = nil) {
        guard let frame = window.frame else { return }
        forget(window)
        let screens = Screen.all()
        guard !screens.isEmpty else { return }
        // ponytail: an edge shared with another display pushes the window onto that display; pick outer edges.
        let screen = screens[screenIndex(for: frame, in: screens.map(\.visible))]
        let edge = edge ?? (frame.midX < screen.visible.midX ? .left : .right)
        let size = CGSize(width: min(frame.width, screen.visible.width), height: frame.height)
        let shownX = edge == .left ? screen.visible.minX : screen.visible.maxX - size.width
        let hiddenX = edge == .left ? screen.frame.minX - size.width + Self.peek : screen.frame.maxX - Self.peek
        var entry = Entry(window: window, shown: CGRect(origin: CGPoint(x: shownX, y: frame.minY), size: size),
                          hidden: CGRect(origin: CGPoint(x: hiddenX, y: frame.minY), size: size),
                          edge: edge, screen: screen.frame)
        if UserDefaults.standard.bool(forKey: Prefs.stashColorTabs) {
            let tabFrame = tabFrame(for: entry)
            entry.tab = (Overlay(cornerRadius: 4, alpha: 0.9, color: tabColor ?? Self.randomColor()), tabFrame)
            entry.tab?.overlay.show(tabFrame)
        }
        window.setFrame(entry.hidden)
        entries.append(entry)
    }

    /// Tucks tucked-away windows back after macOS pulled them on screen (sleep, display changes).
    func reapply() {
        for entry in entries where !entry.revealed {
            guard entry.window.frame != nil else {
                forget(entry.window)
                continue
            }
            stash(entry.window, to: entry.edge, tabColor: entry.tab?.overlay.color)
        }
    }

    /// Stashes every visible window to its nearer edge, optionally keeping the focused one out.
    func stashAll(exceptFocused: Bool) {
        let focused = exceptFocused ? Window.focused() : nil
        for window in Window.visible() where window.element != focused?.element {
            stash(window)
        }
    }

    func unstashAll() {
        entries.forEach {
            $0.window.setOrigin($0.shown.origin)
            $0.tab?.overlay.hide()
        }
        entries.removeAll()
    }

    /// Shows every stashed window, or tucks them all back if any are showing.
    func toggleAll() {
        let show = !entries.contains(where: \.revealed)
        for i in entries.indices { set(i, revealed: show, held: show) }
    }

    /// Shows the next stashed window, tucking the one shown before it.
    func cycle() {
        guard !entries.isEmpty else { return }
        let current = entries.firstIndex(where: \.revealed) ?? -1
        for i in entries.indices where entries[i].revealed { set(i, revealed: false) }
        set((current + 1) % entries.count, revealed: true, held: true)
    }

    /// Stops tracking a window (because another action placed it somewhere).
    func forget(_ window: Window) {
        entries.filter { $0.window.element == window.element }.forEach { $0.tab?.overlay.hide() }
        entries.removeAll { $0.window.element == window.element }
    }

    func mouseMoved(to p: CGPoint) {
        guard !entries.isEmpty else { return }
        var i = 0
        while i < entries.count {
            let entry = entries[i]
            if entry.revealed, !entry.held, !entry.shown.insetBy(dx: -30, dy: -30).contains(p) {
                // Closed, or dragged away from its slot? Then it's no longer stashed.
                guard let frame = entry.window.frame, frame.isClose(to: entry.shown, tolerance: 10) else {
                    remove(at: i)
                    continue
                }
                set(i, revealed: false)
            }
            i += 1
        }

        guard !entries.contains(where: \.revealed), entries.contains(where: { touchesEdge(p, $0) }) else {
            pendingReveal?.cancel()
            pendingReveal = nil
            return
        }
        guard pendingReveal == nil else { return }
        let delay = UserDefaults.standard.double(forKey: Prefs.stashRevealDelay)
        let needsCommand = UserDefaults.standard.bool(forKey: Prefs.stashRevealWithCommand)
        pendingReveal = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            pendingReveal = nil
            // The cursor may have moved on during the delay.
            let cursor = CGEvent(source: nil)?.location ?? p
            guard !needsCommand || NSEvent.modifierFlags.contains(.command), !entries.contains(where: \.revealed),
                  let index = entries.firstIndex(where: { self.touchesEdge(cursor, $0) }) else { return }
            if entries[index].window.frame == nil { return remove(at: index) }
            set(index, revealed: true)
        }
    }

    private func set(_ index: Int, revealed: Bool, held: Bool = false) {
        var entry = entries[index]
        entry.window.setOrigin(revealed ? entry.shown.origin : entry.hidden.origin)
        if revealed {
            entry.window.raise()
            entry.tab?.overlay.hide()
        } else if let tab = entry.tab {
            tab.overlay.show(tab.frame)
        }
        entry.revealed = revealed
        entry.held = held
        entries[index] = entry
    }

    private func remove(at index: Int) {
        entries[index].tab?.overlay.hide()
        entries.remove(at: index)
    }

    private func touchesEdge(_ p: CGPoint, _ entry: Entry) -> Bool {
        let atEdge = entry.edge == .left ? p.x <= entry.screen.minX + 1 : p.x >= entry.screen.maxX - 2
        if let tab = entry.tab { return atEdge && p.y >= tab.frame.minY && p.y <= tab.frame.maxY }
        return atEdge && p.y >= entry.shown.minY && p.y <= entry.shown.maxY
    }

    /// A 60pt pill beside the window's middle, pushed down past tabs already on that edge.
    private func tabFrame(for entry: Entry) -> CGRect {
        let x = entry.edge == .left ? entry.screen.minX : entry.screen.maxX - 8
        var frame = CGRect(x: x, y: entry.shown.midY - 30, width: 8, height: 60)
        let taken = entries.filter { $0.edge == entry.edge && $0.screen == entry.screen }.compactMap { $0.tab?.frame }
        while taken.contains(where: { $0.insetBy(dx: 0, dy: -4).intersects(frame) }) {
            frame.origin.y += 68
        }
        return frame
    }

    private static func randomColor() -> NSColor {
        [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple, .systemPink]
            .randomElement()!
    }
}
