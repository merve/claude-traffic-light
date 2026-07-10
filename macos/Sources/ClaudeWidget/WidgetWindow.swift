import AppKit

/// A borderless, non-opaque, draggable-anywhere-on-screen window for the floating widget.
/// The rounded corners come from the content view's `CALayer` (masksToBounds), which stands
/// in for the Windows port's DWM `DWMWA_WINDOW_CORNER_PREFERENCE` rounding.
final class WidgetWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false // dragging is handled by the title bar / light views
    }

    // Borderless windows don't become key by default; we need key status so mouse-tracking
    // (hover) and the right-click context menu behave normally.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
