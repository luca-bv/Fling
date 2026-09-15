// A throwaway window for `make smoke`: Fling's smoke test moves it around through the Accessibility API.
// SIGUSR1 opens a second window, to test layouts that apply when a window opens.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

func makeWindow(_ frame: NSRect, _ title: String) -> NSWindow {
    let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
    window.title = title
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    return window
}

var windows = [makeWindow(NSRect(x: 300, y: 300, width: 500, height: 350), "Fling Smoke Test")]
signal(SIGUSR1, SIG_IGN)
let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
source.setEventHandler { windows.append(makeWindow(NSRect(x: 200, y: 200, width: 320, height: 240), "Opened Later")) }
source.resume()
DispatchQueue.main.asyncAfter(deadline: .now() + 300) { exit(0) } // never outlive a forgotten test run
app.run()
