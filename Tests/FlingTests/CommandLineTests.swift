import CoreGraphics
import Testing
@testable import Fling

private func parse(_ arguments: [String]) -> CLIRequest? {
    try? CLIRequest.parse(arguments).get()
}

private func error(_ arguments: [String]) -> String? {
    if case .failure(let error) = CLIRequest.parse(arguments) { return error.message }
    return nil
}

@Test func commandLineParsing() {
    #expect(parse([]) == .help)
    #expect(parse(["windows", "--json"]) == .list(.windows, json: true))
    #expect(parse(["left-half"]) == .action(.leftHalf, app: nil))
    // Options can come anywhere; names with spaces don't need quotes.
    #expect(parse(["--app", "Safari", "top-left-sixth"]) == .action(.topLeftSixth, app: "Safari"))
    #expect(parse(["layout", "Deep", "Work"]) == .layout("Deep Work"))
    #expect(parse(["save-layout"]) == .saveLayout(nil))
    #expect(parse(["custom", "Wide", "--app", "com.apple.Notes"]) == .custom("Wide", app: "com.apple.Notes"))
    #expect(parse(["frame", "10", "20", "800", "600.5"]) == .frame(CGRect(x: 10, y: 20, width: 800, height: 600.5), app: nil))
    #expect(parse(["config", "import", "~/fling.json"]) == .importConfig(path: "~/fling.json"))

    #expect(error(["frame", "10", "20", "800"])?.contains("four numbers") == true)
    #expect(error(["layout"]) != nil)
    #expect(error(["left-half", "--app"]) != nil)
    #expect(error(["lefthalf"])?.contains("Unknown command") == true)
}
