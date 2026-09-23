import AppKit

/// A `flingctl` command, parsed from its arguments (pure, so it's unit tested).
enum CLIRequest: Equatable {
    enum Listing: String { case actions, layouts, customs, windows, displays, diagnostics }

    case help, version
    case list(Listing, json: Bool)
    case action(Action, app: String?)
    case custom(String, app: String?)
    case frame(CGRect, app: String?)
    case layout(String), saveLayout(String?)
    case exportConfig, importConfig(path: String)
    /// Sent by the Settings helper, which has no engine of its own (see SettingsHelper).
    case reload, captureKeys(Bool), reflowPin, forgetPositions, clearDiagnostics

    static let usage = """
    Usage: flingctl <command> [--app APP] [--json]

    Window commands act on the focused window, or with --app on that app's front window
    (APP is a name like "Safari" or a bundle ID like com.apple.Safari):
      flingctl left-half              any action; `flingctl actions` lists them
      flingctl frame X Y WIDTH HEIGHT  exact frame in points, from the top-left of the main display
      flingctl custom NAME            a custom position from Settings → Custom

    Layouts:
      flingctl layout NAME            apply a layout
      flingctl save-layout [NAME]     save the visible windows as a layout (replaces one with that name)

    Listings (add --json for JSON):
      flingctl actions | layouts | customs | windows | displays
      flingctl diagnostics            recent window actions, with the reason any of them fell short

    Configuration:
      flingctl config export          print shortcuts, custom positions, layouts and settings as JSON
      flingctl config import FILE     replace them from a JSON file

    If Fling isn't running, flingctl opens it. Exit status is 0 on success, 1 if Fling reports a problem.
    """

    static func parse(_ arguments: [String]) -> Result<CLIRequest, CLIError> {
        var positional: [String] = []
        var app: String?
        var json = false
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "--app":
                guard i + 1 < arguments.count else { return .failure(CLIError("--app needs an app name or bundle ID.")) }
                app = arguments[i + 1]
                i += 1
            case "--json":
                json = true
            case "-h", "--help":
                return .success(.help)
            default:
                positional.append(arguments[i])
            }
            i += 1
        }

        guard let command = positional.first else { return .success(.help) }
        let rest = Array(positional.dropFirst())
        let name = rest.joined(separator: " ")
        switch command {
        case "help":
            return .success(.help)
        case "version", "--version":
            return .success(.version)
        case let listing where Listing(rawValue: listing) != nil:
            return .success(.list(Listing(rawValue: listing)!, json: json))
        case "layout":
            return name.isEmpty ? .failure(CLIError("layout needs a layout name.")) : .success(.layout(name))
        case "custom":
            return name.isEmpty ? .failure(CLIError("custom needs a custom position name.")) : .success(.custom(name, app: app))
        case "save-layout":
            return .success(.saveLayout(name.isEmpty ? nil : name))
        case "reload":
            return .success(.reload)
        case "capture-keys":
            guard name == "on" || name == "off" else { return .failure(CLIError("Use `capture-keys on` or `capture-keys off`.")) }
            return .success(.captureKeys(name == "on"))
        case "reflow-pin":
            return .success(.reflowPin)
        case "forget-positions":
            return .success(.forgetPositions)
        case "clear-diagnostics":
            return .success(.clearDiagnostics)
        case "frame":
            let values = rest.compactMap(Double.init)
            guard rest.count == 4, values.count == 4, values[2] > 0, values[3] > 0 else {
                return .failure(CLIError("frame needs four numbers: X Y WIDTH HEIGHT."))
            }
            return .success(.frame(CGRect(x: values[0], y: values[1], width: values[2], height: values[3]), app: app))
        case "config":
            if rest == ["export"] { return .success(.exportConfig) }
            if rest.count == 2, rest[0] == "import" { return .success(.importConfig(path: rest[1])) }
            return .failure(CLIError("Use `flingctl config export` or `flingctl config import FILE`."))
        default:
            guard let action = Action.allCases.first(where: { $0.urlName == command }) else {
                return .failure(CLIError("Unknown command “\(command)”. Run `flingctl help`, or `flingctl actions` for action names."))
            }
            return .success(.action(action, app: app))
        }
    }
}

struct CLIError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

extension AppState {
    func runCommand(_ arguments: [String], workingDirectory: String) -> (ok: Bool, output: String) {
        switch CLIRequest.parse(arguments) {
        case .failure(let error): (false, error.message)
        case .success(let request): run(request, workingDirectory: workingDirectory)
        }
    }

    private func run(_ request: CLIRequest, workingDirectory: String) -> (ok: Bool, output: String) {
        switch request {
        case .help:
            return (true, CLIRequest.usage)
        case .version:
            return (true, Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
        case .list(let listing, let json):
            return (true, list(listing, json: json))

        case .action(let action, let app):
            let target = app.flatMap(frontWindow)
            if let app, target == nil { return (false, "No window found for “\(app)”.") }
            return reportingProblems { perform(action, on: target) }
        case .custom(let name, let app):
            guard let custom = customActions.first(where: { $0.name == name }) else {
                return (false, "No custom position named “\(name)”. `flingctl customs` lists them.")
            }
            let target = app.flatMap(frontWindow)
            if let app, target == nil { return (false, "No window found for “\(app)”.") }
            return reportingProblems { perform(custom: custom.id, on: target) }
        case .frame(let frame, let app):
            guard let target = app.flatMap(frontWindow) ?? Window.focused() else {
                return (false, app.map { "No window found for “\($0)”." } ?? "No focused window.")
            }
            return reportingProblems { place(target, at: frame, key: "frame") }

        case .layout(let name):
            guard let layout = layouts.first(where: { $0.name == name }) else {
                return (false, "No layout named “\(name)”. `flingctl layouts` lists them.")
            }
            apply(layout: layout.id)
            return (true, "")
        case .saveLayout(let name):
            saveCurrentLayout(name: name)
            let saved = name ?? layouts.last?.name ?? ""
            let count = layouts.first { $0.name == saved }?.entries.count ?? 0
            return (true, "Saved “\(saved)” with \(count) window\(count == 1 ? "" : "s").")

        case .exportConfig:
            return exportConfig().flatMap { String(data: $0, encoding: .utf8) }.map { (true, $0) } ?? (false, "Couldn't export.")
        case .importConfig(let path):
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath,
                          relativeTo: URL(fileURLWithPath: workingDirectory, isDirectory: true))
            guard let data = try? Data(contentsOf: url) else { return (false, "Can't read \(url.path).") }
            return importConfig(data) ? (true, "Imported \(url.path).") : (false, "\(url.path) isn't a Fling configuration.")

        case .reload:
            reloadConfiguration()
            return (true, "")
        case .captureKeys(let capturing):
            capturingKeys = capturing
            return (true, "")
        case .reflowPin:
            reflowPin()
            return (true, "")
        case .forgetPositions:
            displayMemory?.forgetAll()
            return (true, "")
        case .clearDiagnostics:
            diagnostics.removeAll()
            return (true, "")
        }
    }

    /// The front window of an app given by name ("Safari") or bundle ID ("com.apple.Safari").
    private func frontWindow(of app: String) -> Window? {
        let running = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == app || $0.localizedName?.caseInsensitiveCompare(app) == .orderedSame
        }
        return running.flatMap { Window.all(of: $0.processIdentifier).first }
    }

    /// Runs a command and fails with the reason Diagnostics recorded, if any.
    private func reportingProblems(_ body: () -> Void) -> (ok: Bool, output: String) {
        let lastBefore = diagnostics.last?.id
        body()
        let problem = diagnostics.reversed().prefix { $0.id != lastBefore }.compactMap(\.problem).first
        return problem.map { (false, $0) } ?? (true, "")
    }

    private func list(_ listing: CLIRequest.Listing, json: Bool) -> String {
        let screens = Screen.all()
        let rows: [[String: Any]]
        switch listing {
        case .actions:
            rows = Action.allCases.map { ["name": $0.urlName, "title": $0.title, "category": $0.category.rawValue] }
            if !json { return Action.allCases.map { $0.urlName.padding(toLength: 26, withPad: " ", startingAt: 0) + $0.title }.joined(separator: "\n") }
        case .layouts:
            rows = layouts.map { ["name": $0.name, "windows": $0.entries.count, "triggers": $0.triggers.map(\.rawValue).sorted()] }
            if !json { return layouts.map(\.name).joined(separator: "\n") }
        case .customs:
            rows = customActions.map { ["name": $0.name, "snapTarget": $0.snapTarget] }
            if !json { return customActions.map(\.name).joined(separator: "\n") }
        case .windows:
            let windows = Window.visible().compactMap { window in window.frame.map { (window, $0) } }
            rows = windows.map { window, frame in
                let app = NSRunningApplication(processIdentifier: window.pid)
                return ["app": app?.localizedName ?? "", "bundleID": app?.bundleIdentifier ?? "", "title": window.title,
                        "x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height,
                        "display": screenIndex(for: frame, in: screens.map(\.visible)) + 1]
            }
            if !json {
                return rows.map { row in
                    let title = (row["title"] as? String).flatMap { $0.isEmpty ? nil : " — \($0)" } ?? ""
                    return "\(row["app"]!)\(title)  \(Int(row["x"] as! CGFloat)),\(Int(row["y"] as! CGFloat)) "
                        + "\(Int(row["width"] as! CGFloat))×\(Int(row["height"] as! CGFloat))  display \(row["display"]!)"
                }.joined(separator: "\n")
            }
        case .diagnostics:
            if json {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                return (try? encoder.encode(diagnostics)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            }
            return diagnostics.map { entry in
                [entry.date.formatted(date: .omitted, time: .standard), entry.command,
                 entry.window.isEmpty ? entry.app : "\(entry.app) — \(entry.window)", entry.problem ?? "ok"]
                    .filter { !$0.isEmpty }.joined(separator: "  ")
            }.joined(separator: "\n")
        case .displays:
            rows = screens.enumerated().map { i, screen in
                ["display": i + 1, "id": screen.id, "primary": screen.isPrimary,
                 "frame": [screen.frame.minX, screen.frame.minY, screen.frame.width, screen.frame.height],
                 "usable": [screen.visible.minX, screen.visible.minY, screen.visible.width, screen.visible.height]]
            }
            if !json {
                return screens.enumerated().map { i, s in
                    "\(i + 1)\(s.isPrimary ? " (main)" : "")  \(Int(s.frame.minX)),\(Int(s.frame.minY)) \(Int(s.frame.width))×\(Int(s.frame.height))"
                        + "  usable \(Int(s.visible.minX)),\(Int(s.visible.minY)) \(Int(s.visible.width))×\(Int(s.visible.height))  \(s.id)"
                }.joined(separator: "\n")
            }
        }
        guard !rows.isEmpty else { return "[]" }
        let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
