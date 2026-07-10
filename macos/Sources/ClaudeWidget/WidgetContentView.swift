import AppKit

/// The window's root content view. Draws the background fill and, only in expanded mode,
/// the divider under the title and the outline border (collapsed mode has no chrome — the
/// traffic light housing fills the whole window and IS the visible edge, matching the
/// Windows port's `WidgetForm.OnPaint`).
final class WidgetContentView: NSView {
    var theme: WidgetTheme { didSet { needsDisplay = true } }
    var expanded = true { didSet { needsDisplay = true } }

    static let radius: CGFloat = 10
    static let sideInset: CGFloat = 14
    var dividerY: CGFloat = 0

    /// Builds a fresh right-click menu (state always current — no persistent menu to keep in sync).
    var menuProvider: (() -> NSMenu)?

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    init(theme: WidgetTheme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.radius
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        theme.background.setFill()
        bounds.fill()
        guard expanded else { return } // collapsed: the light housing is the only visible chrome

        theme.separator.setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: Self.sideInset, y: dividerY))
        sep.line(to: NSPoint(x: bounds.width - Self.sideInset, y: dividerY))
        sep.lineWidth = 1
        sep.stroke()

        theme.border.setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.radius, yRadius: Self.radius)
        outline.lineWidth = 1
        outline.stroke()
    }
}
