import AppKit

// Single instance: a second launch (e.g. double-clicking the .app again, or autostart
// racing a manual launch) just activates the already-running widget instead of stacking
// two windows. Mirrors the Windows port's named-mutex guard. Skipped when there's no
// bundle identifier (`swift run` in development).
if let bundleID = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if let existing = others.first {
        existing.activate()
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = WidgetAppDelegate()
app.delegate = delegate

// No Dock icon; the widget IS the visible surface (agent app), same as the menu-bar app.
app.setActivationPolicy(.accessory)

app.run()
