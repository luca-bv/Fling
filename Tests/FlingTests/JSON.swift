// Swift Testing's Foundation overlay is missing from Command Line Tools installs, so test files that import
// Testing can't also import Foundation. Helpers that need Foundation live here instead.
import Foundation
@testable import Fling

func jsonData(_ text: String) -> Data { Data(text.utf8) }
func url(_ text: String) -> URL { URL(string: text)! }

/// Encodes diagnostics the way `flingctl diagnostics --json` does.
func diagnosticsJSON(_ entries: [DiagnosticEntry]) -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try! encoder.encode(entries), as: UTF8.self)
}
func seconds(from a: Date, to b: Date) -> Double { b.timeIntervalSince(a) }
