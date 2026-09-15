import AppKit

/// Fling's actions as a pop-up menu at the cursor, acting on a chosen window (shortcut: focused; modifier-click: clicked).
@MainActor
final class ContextMenu: NSObject {
    private unowned let state: AppState
    private var window: Window?

    init(state: AppState) {
        self.state = state
    }

    /// `point` is in Accessibility coordinates.
    func show(for window: Window?, at point: CGPoint) {
        guard let primary = NSScreen.screens.first else { return }
        self.window = window
        let menu = NSMenu()
        for category in Action.Category.allCases {
            let actions = Action.allCases.filter { $0.category == category && $0 != .showMenu }
            let item = submenu(category.rawValue, actions.map { ($0.title, $0.rawValue) })
            item.image = Glyph.image(for: category)
            item.submenu?.items.forEach { $0.image = Action(rawValue: $0.representedObject as? String ?? "").map(Glyph.image(for:)) }
            menu.addItem(item)
        }
        if !state.customActions.isEmpty {
            menu.addItem(submenu("Custom", state.customActions.map { ($0.name, "custom:" + $0.id.uuidString) }))
        }
        if !state.layouts.isEmpty {
            menu.addItem(submenu("Layouts", state.layouts.map { ($0.name, "layout:" + $0.id.uuidString) }))
        }
        menu.popUp(positioning: nil, at: NSPoint(x: point.x, y: primary.frame.height - point.y), in: nil)
    }

    private func submenu(_ title: String, _ items: [(title: String, command: String)]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = NSMenu()
        for entry in items {
            let child = NSMenuItem(title: entry.title, action: #selector(picked(_:)), keyEquivalent: "")
            child.target = self
            child.representedObject = entry.command
            item.submenu?.addItem(child)
        }
        return item
    }

    @objc private func picked(_ item: NSMenuItem) {
        guard let command = item.representedObject as? String else { return }
        if command.hasPrefix("custom:"), let id = UUID(uuidString: String(command.dropFirst(7))) {
            state.perform(custom: id, on: window)
        } else if command.hasPrefix("layout:"), let id = UUID(uuidString: String(command.dropFirst(7))) {
            state.apply(layout: id)
        } else if let action = Action(rawValue: command) {
            state.perform(action, on: window)
        }
    }
}
