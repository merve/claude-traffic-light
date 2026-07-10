import AppKit

final class WidgetAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: WidgetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = WidgetController()
    }

    // Single-instance-style behavior: relaunching while already running just re-shows it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.window.orderFrontRegardless()
        return true
    }
}
