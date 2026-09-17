import SwiftUI

struct CustomSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            ForEach($state.customActions) { $custom in
                Section {
                    TextField("Name", text: $custom.name)
                    LabeledContent("Shortcut") { ShortcutRecorder(shortcut: state.binding(forCustom: custom.id)) }
                    DisplayPicker(selection: $custom.display)
                    Toggle("Snap target: drop a dragged window onto this area", isOn: $custom.snapTarget)
                    ForEach(custom.frames.indices, id: \.self) { i in
                        FrameSpecEditor(title: i == 0 ? "Position" : "Repeat \(i)", spec: $custom.frames[i])
                        if i > 0 {
                            Button("Remove Repeat \(i)", role: .destructive) { $custom.wrappedValue.frames.remove(at: i) }
                        }
                    }
                    HStack {
                        Button("Add Repeat") { $custom.wrappedValue.frames.append(custom.frames.last ?? FrameSpec()) }
                        Spacer()
                        Button("Delete", role: .destructive) { state.customActions.removeAll { $0.id == custom.id } }
                    }
                }
            }
            Section {
                Button("Add Custom Position") { state.customActions.append(CustomAction()) }
            } footer: {
                Text("Sizes and positions from 0 to 1 are fractions of the screen (1/3, 0.25); larger numbers are points; blank keeps the window's current value. Repeats apply when the shortcut is pressed again. Run one by URL with fling://execute-custom?name=…")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct LayoutSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                HStack {
                    Button("Save Current Layout") { state.saveCurrentLayout() }
                    Button("New Empty Layout") { state.layouts.append(Layout(name: "Layout \(state.layouts.count + 1)")) }
                }
            } footer: {
                Text("Saving records every visible window: its app, title, and either the Fling action that placed it or its exact frame. Run a layout by URL with fling://execute-layout?name=…\n\nRunning a layout first records where every window was, so Undo Layout (in Shortcuts, the menu, or flingctl undo-layout) puts them back.")
                    .foregroundStyle(.secondary)
            }
            ForEach($state.layouts) { $layout in
                Section {
                    TextField("Name", text: $layout.name)
                    LabeledContent("Shortcut") { ShortcutRecorder(shortcut: state.binding(forLayout: layout.id)) }
                    ForEach(Layout.Trigger.allCases, id: \.self) { trigger in
                        Toggle(triggerTitle(trigger), isOn: Binding(
                            get: { layout.triggers.contains(trigger) },
                            set: { on in
                                if on { $layout.wrappedValue.triggers.insert(trigger) } else { $layout.wrappedValue.triggers.remove(trigger) }
                            }))
                    }
                    Toggle("Launch apps that aren't running", isOn: $layout.launchApps)
                    Toggle("Hide apps that aren't in this layout", isOn: $layout.hideOtherApps)
                    Toggle("Bring the layout's windows to the front", isOn: $layout.bringToFront)
                    Toggle("Only arrange the frontmost app", isOn: $layout.frontmostAppOnly)
                    Toggle("Apply entries to every matching window, not just one each", isOn: $layout.allMatches)
                    Toggle("Snap back if I move a window by hand", isOn: $layout.snapBack)
                    Toggle("Shortcut undoes this layout while it's in effect", isOn: $layout.shortcutToggles)
                    ForEach($layout.entries) { $entry in
                        LayoutEntryEditor(entry: $entry) { $layout.wrappedValue.entries.removeAll { $0.id == entry.id } }
                    }
                    HStack {
                        Menu("Add App") {
                            ForEach(runningAppChoices(), id: \.id) { app in
                                Button(app.name) { $layout.wrappedValue.entries.append(LayoutEntry(bundleID: app.id, appName: app.name)) }
                            }
                        }
                        .fixedSize()
                        Button("Apply Now") { state.apply(layout: layout.id) }
                        Spacer()
                        Button("Delete Layout", role: .destructive) { state.layouts.removeAll { $0.id == layout.id } }
                    }
                } header: {
                    Text(layout.name)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func triggerTitle(_ trigger: Layout.Trigger) -> String {
        switch trigger {
        case .displayConnected: "Apply when a display connects"
        case .displayDisconnected: "Apply when a display disconnects"
        case .wake: "Apply when the Mac wakes"
        case .windowOpened: "Apply to windows as they open"
        }
    }
}

private struct LayoutEntryEditor: View {
    @Binding var entry: LayoutEntry
    let onDelete: () -> Void

    var body: some View {
        DisclosureGroup {
            Picker("Window title", selection: $entry.titleMatch) {
                Text("Prefer this title").tag(LayoutEntry.TitleMatch.loose)
                Text("Any window").tag(LayoutEntry.TitleMatch.any)
                Text("Is exactly").tag(LayoutEntry.TitleMatch.exact)
                Text("Contains").tag(LayoutEntry.TitleMatch.contains)
                Text("Matches regex").tag(LayoutEntry.TitleMatch.regex)
            }
            if entry.titleMatch != .any {
                TextField("Title", text: $entry.title)
            }
            Picker("Place", selection: $entry.action) {
                Text("Custom frame").tag(Action?.none)
                ForEach(Action.allCases.filter(\.placesWindow), id: \.self) { ActionLabel(action: $0).tag(Action?.some($0)) }
            }
            if entry.action == nil {
                FrameSpecEditor(title: "Frame", spec: $entry.frame)
            }
            DisplayPicker(selection: $entry.display)
            Button("Remove", role: .destructive, action: onDelete)
        } label: {
            Text("\(entry.appName) — \(entry.titleMatch == .any || entry.title.isEmpty ? "any window" : entry.title)")
                .lineLimit(1)
        }
    }
}

private struct FrameSpecEditor: View {
    let title: String
    @Binding var spec: FrameSpec

    var body: some View {
        Picker(title, selection: $spec.anchor) {
            ForEach(FrameSpec.Anchor.allCases, id: \.self) { anchor in
                Text(anchor == .origin ? "Custom X / Y" : titleCase(anchor.rawValue)).tag(anchor)
            }
        }
        if spec.anchor == .origin {
            LabeledContent("X / Y") { pair($spec.x, "x", $spec.y, "y") }
        }
        LabeledContent("Width / Height") { pair($spec.width, "width", $spec.height, "height") }
    }

    private func pair(_ a: Binding<String>, _ aPrompt: String, _ b: Binding<String>, _ bPrompt: String) -> some View {
        HStack {
            TextField("", text: a, prompt: Text(aPrompt)).labelsHidden()
            TextField("", text: b, prompt: Text(bPrompt)).labelsHidden()
        }
        .frame(maxWidth: 200)
    }
}

private struct DisplayPicker: View {
    @Binding var selection: DisplayTarget

    var body: some View {
        let selectedIndex = if case .index(let i) = selection { i } else { 0 }
        Picker("Display", selection: $selection) {
            Text("Current").tag(DisplayTarget.current)
            Text("Next").tag(DisplayTarget.next)
            Text("Previous").tag(DisplayTarget.previous)
            ForEach(0..<max(NSScreen.screens.count, selectedIndex + 1), id: \.self) { i in
                Text("Display \(i + 1)").tag(DisplayTarget.index(i))
            }
        }
    }
}
