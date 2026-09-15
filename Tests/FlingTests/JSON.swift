// Swift Testing's Foundation overlay is missing from Command Line Tools installs, so test files that import
// Testing can't also import Foundation. Helpers that need Foundation live here instead.
import Foundation

func jsonData(_ text: String) -> Data { Data(text.utf8) }
func url(_ text: String) -> URL { URL(string: text)! }
