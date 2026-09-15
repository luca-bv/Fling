import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettings().tabItem { Label("Shortcuts", systemImage: "keyboard") }
            MouseSettings().tabItem { Label("Mouse", systemImage: "cursorarrow.motionlines") }
            CustomSettings().tabItem { Label("Custom", systemImage: "rectangle.dashed") }
            LayoutSettings().tabItem { Label("Layouts", systemImage: "rectangle.3.group") }
            DiagnosticsSettings().tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 540, height: 640)
    }
}

private struct GeneralSettings: View {
    @State private var trusted = AXIsProcessTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(Prefs.gap) private var gap = 0
    @AppStorage(Prefs.cycleHalves) private var cycleHalves = true
    @AppStorage(Prefs.doubleClickTitleBar) private var doubleClickTitleBar = false
    @AppStorage(Prefs.moveCursorWithWindow) private var moveCursorWithWindow = false
    @AppStorage(Prefs.adjustForDock) private var adjustForDock = false
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Prefs.pinEnabled) private var pinEnabled = false
    @AppStorage(Prefs.pinBundleID) private var pinBundleID = ""
    @AppStorage(Prefs.pinWidth) private var pinWidth = "1/4"
    @AppStorage(Prefs.pinRight) private var pinRight = true
    @AppStorage(Prefs.iCloudSync) private var iCloudSync = false
    @AppStorage(Prefs.stashColorTabs) private var stashColorTabs = false
    @AppStorage(Prefs.stashRevealDelay) private var stashRevealDelay = "0"
    @AppStorage(Prefs.stashRevealWithCommand) private var stashRevealWithCommand = false
    @AppStorage(Prefs.restoreDisplayLayouts) private var restoreDisplayLayouts = false
    @State private var importFailed = false
    @Environment(AppState.self) private var state

    /// Running apps, plus the pinned one if it isn't running.
    private var appChoices: [(id: String, name: String)] {
        var apps = runningAppChoices()
        if !pinBundleID.isEmpty, !apps.contains(where: { $0.id == pinBundleID }) { apps.append((pinBundleID, pinBundleID)) }
        return apps
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Fling Config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let data = state.exportConfig() else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFailed = !((try? Data(contentsOf: url)).map(state.importConfig) ?? false)
    }

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if trusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }
            Section {
                Stepper("Gaps between windows: \(gap) px", value: $gap, in: 0...60, step: 2)
                Toggle("Repeating a half action cycles ½ → ⅔ → ⅓", isOn: $cycleHalves)
                Toggle("Double-click a title bar to maximize or restore", isOn: $doubleClickTitleBar)
                Toggle("Move the cursor with a window sent to another display", isOn: $moveCursorWithWindow)
                Toggle("Adjust windows when the Dock is shown, hidden or moved", isOn: $adjustForDock)
                Toggle("Put windows back when a display is reconnected", isOn: $restoreDisplayLayouts)
            } header: {
                Text("Windows")
            } footer: {
                Text("For double-click, set System Settings → Desktop & Dock → \"Double-click a window's title bar\" to Do Nothing.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Pin Mode", isOn: $pinEnabled)
                    .onChange(of: pinEnabled) { _, on in if on { state.reflowPin() } }
                Picker("App", selection: $pinBundleID) {
                    Text("None").tag("")
                    ForEach(appChoices, id: \.id) { Text($0.name).tag($0.id) }
                }
                LabeledContent("Width") {
                    TextField("", text: $pinWidth, prompt: Text("1/4 or 400"))
                        .labelsHidden()
                        .onSubmit { state.reflowPin() }
                }
                Picker("Side", selection: $pinRight) {
                    Text("Left").tag(false)
                    Text("Right").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: pinRight) { state.reflowPin() }
            } header: {
                Text("Pin Mode")
            } footer: {
                Text("Keeps one app in a strip on the main display; every other action uses the space that's left.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show a color tab for each stashed window", isOn: $stashColorTabs)
                Picker("Show a stashed window", selection: $stashRevealDelay) {
                    Text("Immediately").tag("0")
                    ForEach(1...10, id: \.self) { tenths in
                        Text("After \(Double(tenths) / 10, specifier: "%.1f") s").tag(String(Double(tenths) / 10))
                    }
                }
                Toggle("Only while holding ⌘", isOn: $stashRevealWithCommand)
            } header: {
                Text("Stash")
            } footer: {
                Text("Stash Left/Right tucks a window against the screen edge; touch the edge (or its tab) to slide it out.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Sync configuration over iCloud Drive", isOn: $iCloudSync)
                    .onChange(of: iCloudSync) { _, on in if on { state.cloudSync?.enabledChanged() } }
                HStack {
                    Button("Export…") { exportConfig() }
                    Button("Import…") { importConfig() }
                }
            } header: {
                Text("Configuration")
            } footer: {
                Text("Shortcuts, custom positions, layouts and settings, as JSON. Sync keeps a copy in iCloud Drive → Fling.")
                    .foregroundStyle(.secondary)
            }
            .alert("That file isn't a Fling configuration.", isPresented: $importFailed) {}
            Section("Startup") {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                    .help("When hidden, open Fling again (e.g. from Finder) to bring the icon back.")
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSLog("Fling: launch at login failed: \(error)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .task {
            // Permission can be granted while this tab is open; keep the status live.
            while !Task.isCancelled {
                trusted = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct ShortcutSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            ForEach(Action.Category.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    ForEach(Action.allCases.filter { $0.category == category }, id: \.self) { action in
                        LabeledContent(action.title) {
                            ShortcutRecorder(shortcut: state.binding(for: action))
                        }
                    }
                }
            }
            Section {
                Button("Restore Default Shortcuts") { state.shortcuts = Action.defaultShortcuts }
            } footer: {
                Text("Assigning keys already used by another action moves them to the new one.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MouseSettings: View {
    @AppStorage(Prefs.snapAreas) private var snapAreas = true
    @AppStorage(Prefs.snapPanel) private var snapPanel = false
    @AppStorage(Prefs.snapHaptics) private var snapHaptics = true
    @AppStorage(Prefs.resizeAdjacent) private var resizeAdjacent = false
    @AppStorage(Prefs.contextClickModifiers) private var contextClickModifiers = 0
    @AppStorage(Prefs.windowThrow) private var windowThrow = true
    @AppStorage(Prefs.throwModifiers) private var throwModifiers = 0
    @AppStorage(Prefs.throwMouseButton) private var throwMouseButton = 0
    @AppStorage(Prefs.throwSafeArea) private var throwSafeArea = 15
    @AppStorage(Prefs.throwLongDistance) private var throwLongDistance = 150
    @AppStorage(Prefs.throwTrackpadFingers) private var throwTrackpadFingers = 0
    @AppStorage(Prefs.quickThrow) private var quickThrow = false
    @AppStorage(Prefs.quickThrowModifiers) private var quickThrowModifiers = 0
    @AppStorage(Prefs.moveWindow) private var moveWindow = false
    @AppStorage(Prefs.moveModifiers) private var moveModifiers = 0
    @AppStorage(Prefs.resizeWindow) private var resizeWindow = false
    @AppStorage(Prefs.resizeModifiers) private var resizeModifiers = 0

    var body: some View {
        Form {
            Section {
                Toggle("Snap windows by dragging to screen edges", isOn: $snapAreas)
                Toggle("Show the Snap Panel while dragging", isOn: $snapPanel)
                Toggle("Haptic feedback when a snap area appears", isOn: $snapHaptics)
                DisclosureGroup("Snap areas") {
                    ForEach(SnapArea.allCases, id: \.self) { area in
                        PositionPicker(title: titleCase(area.rawValue) + ([.left, .right, .top, .bottom].contains(area) ? " edge" : " corner"),
                                       key: area.prefKey, extra: area == .bottom ? [("thirds", "Thirds (by cursor position)")] : [])
                    }
                }
                Toggle("Resize neighboring windows when dragging a shared edge", isOn: $resizeAdjacent)
            } footer: {
                note("Sides: halves. Top: maximize. Corners: quarters. Bottom edge: thirds. "
                    + "The Snap Panel appears near the top of the screen; drop a window on a tile. "
                    + "Custom positions marked as snap targets appear as drop zones. "
                    + "Dragging a snapped window away restores its size.")
            }
            Section {
                Toggle("Window Throw", isOn: $windowThrow)
                ModifierPicker(title: "Hold", selection: $throwModifiers).disabled(!windowThrow)
                Picker("Or hold mouse button", selection: $throwMouseButton) {
                    Text("None").tag(0)
                    Text("Middle (3)").tag(3)
                    Text("Button 4").tag(4)
                    Text("Button 5").tag(5)
                }
                .disabled(!windowThrow)
                Picker("Or trackpad", selection: $throwTrackpadFingers) {
                    Text("None").tag(0)
                    ForEach(3...5, id: \.self) { Text("Rest \($0) fingers, lift all but one").tag($0) }
                }
                .disabled(!windowThrow)
                Stepper("Dead zone: \(throwSafeArea) pt", value: $throwSafeArea, in: 5...80, step: 5)
                    .disabled(!windowThrow)
                Stepper("Long throw from: \(throwLongDistance) pt", value: $throwLongDistance, in: 60...400, step: 10)
                    .disabled(!windowThrow)
                DisclosureGroup("Throw positions") {
                    ForEach([false, true], id: \.self) { long in
                        Text(long ? "Long throw (move farther)" : "Short throw").font(.headline)
                        ForEach(0..<8, id: \.self) { sector in
                            PositionPicker(title: ThrowSectors.names[sector], key: ThrowSectors.prefKey(sector: sector, long: long))
                        }
                    }
                }
            } footer: {
                note("Hold the keys with the cursor over any window, move toward a position, then release. "
                    + "Short moves pick halves and corners; long moves pick two-thirds, maximize and center. "
                    + "Move onto another display to center the window there.")
            }
            Section {
                Toggle("Quick Throw", isOn: $quickThrow)
                ModifierPicker(title: "Tap", selection: $quickThrowModifiers).disabled(!quickThrow)
            } footer: {
                note("Sweep the cursor across a window and tap the key: left or right for halves, up to maximize, down to minimize.")
            }
            Section {
                Toggle("Move window", isOn: $moveWindow)
                ModifierPicker(title: "Hold", selection: $moveModifiers).disabled(!moveWindow)
                Toggle("Resize window", isOn: $resizeWindow)
                ModifierPicker(title: "Hold", selection: $resizeModifiers).disabled(!resizeWindow)
            } footer: {
                note("Hold the keys and move the cursor to move or resize the window under it. No click needed.")
            }
            Section {
                ModifierPicker(title: "Show Fling's menu on click with", selection: $contextClickModifiers, allowsNone: true)
            } footer: {
                note("The menu acts on the clicked window. A shortcut for the menu (acting on the focused window) is under Shortcuts → Window → Show Menu.")
            }
        }
        .formStyle(.grouped)
    }

    private func note(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }
}

private struct ModifierPicker: View {
    let title: String
    @Binding var selection: Int
    var allowsNone = false

    private static let options: [NSEvent.ModifierFlags] = [
        [.control, .command], [.option, .command], [.control, .option], [.control, .shift], [.option, .shift],
        [.control, .option, .command], [.control, .option, .shift], [.control], [.option], [.command],
    ]

    var body: some View {
        Picker(title, selection: $selection) {
            if allowsNone { Text("Off").tag(0) }
            ForEach(Self.options, id: \.rawValue) { flags in
                Text(modifierSymbols(flags)).tag(Int(flags.rawValue))
            }
        }
    }
}

/// Picks the action for a snap area or throw sector, stored as an action name in UserDefaults.
private struct PositionPicker: View {
    let title: String
    @AppStorage private var selection: String
    let extra: [(value: String, title: String)]

    init(title: String, key: String, extra: [(value: String, title: String)] = []) {
        self.title = title
        self.extra = extra
        _selection = AppStorage(wrappedValue: "none", key)
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text("None").tag("none")
            ForEach(extra, id: \.value) { Text($0.title).tag($0.value) }
            ForEach(Action.allCases.filter(\.placesWindow), id: \.self) { Text($0.title).tag($0.rawValue) }
        }
    }
}

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @Environment(AppState.self) private var state
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(monitor != nil ? "Type shortcut…" : shortcut?.description ?? "Record Shortcut") {
                monitor == nil ? start() : stop()
            }
            .frame(minWidth: 130)
            Button { shortcut = nil } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(shortcut == nil || monitor != nil ? 0 : 1)
                .help("Clear shortcut")
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        state.capturingKeys = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if Int(event.keyCode) == kVK_Escape, flags.isEmpty {
                stop()
            } else if flags.isEmpty {
                NSSound.beep() // global shortcuts need at least one modifier
            } else {
                shortcut = Shortcut(Int(event.keyCode), event.characters(byApplyingModifiers: []) ?? "", flags)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        state.capturingKeys = false
    }
}

func runningAppChoices() -> [(id: String, name: String)] {
    NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

/// Recent placements, with a plain-language reason when a window didn't end up where it was sent.
private struct DiagnosticsSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            List(state.diagnostics.reversed()) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: entry.problem == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(entry.problem == nil ? .green : .orange)
                        Text(entry.command).bold()
                        Text(entry.window.isEmpty ? entry.app : "\(entry.app) — \(entry.window)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(entry.date, style: .time).foregroundStyle(.secondary)
                    }
                    if let problem = entry.problem {
                        Text(problem).font(.callout)
                    }
                }
                .padding(.vertical, 2)
            }
            .overlay {
                if state.diagnostics.isEmpty {
                    Text("Window actions will show up here.").foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report(), forType: .string)
                }
                Button("Clear") { state.diagnostics.removeAll() }
                Spacer()
                Text("Last 100 actions").foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private func report() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let header = "Fling \(version) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
            + "Accessibility: \(AXIsProcessTrusted() ? "granted" : "missing")\n"
        let lines = state.diagnostics.map { entry in
            [entry.date.formatted(date: .omitted, time: .standard), entry.command, entry.app, entry.window,
             entry.requested.map { "to \(NSStringFromRect($0))" } ?? "", entry.actual.map { "got \(NSStringFromRect($0))" } ?? "",
             entry.problem ?? "ok"]
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
        }
        return header + lines.joined(separator: "\n")
    }
}
