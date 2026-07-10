import AppKit

/// Widget title bar: title text, a collapse chevron, a pin (always-on-top) toggle, and a
/// close ✕. Doubles as the drag handle for the borderless window. Mirrors the Windows
/// port's `WidgetTitleBar`.
final class WidgetTitleBarView: NSView {
    private var theme: WidgetTheme
    private var pinned: Bool
    private var pinHover = false, closeHover = false, toggleHover = false
    private var trackingArea: NSTrackingArea?

    var onClose: (() -> Void)?
    var onPinToggled: ((Bool) -> Void)?
    var onToggleList: (() -> Void)?

    private static let red = NSColor(calibratedRed: 0.95, green: 0.20, blue: 0.16, alpha: 1)

    private var downPoint: NSPoint = .zero
    private var dragStarted = false

    init(theme: WidgetTheme, pinned: Bool) {
        self.theme = theme
        self.pinned = pinned
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    // Without this, the first click while the widget's window isn't key only activates the
    // window (drag/buttons don't fire) — a second click would be needed to actually act.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setTheme(_ t: WidgetTheme) { theme = t; needsDisplay = true }
    func setPinned(_ p: Bool) { pinned = p; needsDisplay = true }

    private var closeRect: NSRect { NSRect(x: bounds.width - 27, y: (bounds.height - 22) / 2, width: 22, height: 22) }
    private var pinRect: NSRect { NSRect(x: bounds.width - 52, y: (bounds.height - 22) / 2, width: 22, height: 22) }
    private var toggleRect: NSRect { NSRect(x: bounds.width - 77, y: (bounds.height - 22) / 2, width: 22, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        theme.background.setFill()
        bounds.fill()

        // Title, left-aligned across the whole top row.
        let textX: CGFloat = 14
        let tr = toggleRect
        let titleRect = NSRect(x: textX, y: 0, width: max(20, tr.minX - textX - 6), height: bounds.height)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(string: "Claude Traffic Light", attributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: theme.text,
            .paragraphStyle: para,
        ])
        let th = title.size().height
        title.draw(in: NSRect(x: titleRect.minX, y: (bounds.height - th) / 2, width: titleRect.width, height: th))

        // Collapse toggle: a left chevron "‹" (click to hide the list; the light stays).
        if toggleHover { fillCircle(tr, theme.text.withAlphaComponent(0.12)) }
        let chevron = NSBezierPath()
        let ccx = tr.midX, ccy = tr.midY
        chevron.move(to: NSPoint(x: ccx + 2, y: ccy - 5))
        chevron.line(to: NSPoint(x: ccx - 3, y: ccy))
        chevron.line(to: NSPoint(x: ccx + 2, y: ccy + 5))
        chevron.lineWidth = 1.8
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        (toggleHover ? theme.text : theme.subText).setStroke()
        chevron.stroke()

        // Pin toggle: simple push-pin, neutral color only (never a status color). Bright
        // (text) when pinned, dim (subtext) when not.
        let pr = pinRect
        if pinHover { fillCircle(pr, theme.text.withAlphaComponent(0.12)) }
        let pinColor = pinned ? theme.text : theme.subText
        let pcx = pr.midX, pcy = pr.minY + 7
        pinColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: pcx - 4, y: pcy - 4, width: 8, height: 8)).fill()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: pcx, y: pcy + 4))
        stem.line(to: NSPoint(x: pcx, y: pcy + 12))
        stem.lineWidth = 1.7
        stem.lineCapStyle = .round
        pinColor.setStroke()
        stem.stroke()

        // Close ✕.
        let cr = closeRect
        if closeHover { fillCircle(cr, Self.red.withAlphaComponent(0.15)) }
        let x = NSBezierPath()
        let inset: CGFloat = 7
        let r = cr.insetBy(dx: inset, dy: inset)
        x.move(to: NSPoint(x: r.minX, y: r.minY)); x.line(to: NSPoint(x: r.maxX, y: r.maxY))
        x.move(to: NSPoint(x: r.minX, y: r.maxY)); x.line(to: NSPoint(x: r.maxX, y: r.minY))
        x.lineWidth = 1.6
        x.lineCapStyle = .round
        (closeHover ? Self.red : theme.subText).setStroke()
        x.stroke()
    }

    private func fillCircle(_ r: NSRect, _ c: NSColor) {
        c.setFill()
        NSBezierPath(ovalIn: r).fill()
    }

    // MARK: - Hover / click

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let pin = pinRect.contains(p), close = closeRect.contains(p), toggle = toggleRect.contains(p)
        if pin != pinHover || close != closeHover || toggle != toggleHover {
            pinHover = pin; closeHover = close; toggleHover = toggle
            needsDisplay = true
        }
        // Buttons get the pointing-hand hint; the rest of the bar is the drag handle, so
        // an open hand signals "grab here to move the window" (closed while actually dragging).
        (pin || close || toggle) ? NSCursor.pointingHand.set() : NSCursor.openHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        pinHover = false; closeHover = false; toggleHover = false
        needsDisplay = true
        if !dragStarted { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if closeRect.contains(p) { onClose?(); return }
        if pinRect.contains(p) { pinned.toggle(); onPinToggled?(pinned); needsDisplay = true; return }
        if toggleRect.contains(p) { onToggleList?(); return }
        // Anywhere else on the bar → drag the window.
        downPoint = event.locationInWindow
        dragStarted = false
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard !closeRect.contains(p), !pinRect.contains(p), !toggleRect.contains(p) || dragStarted else { return }
        let loc = event.locationInWindow
        if abs(loc.x - downPoint.x) > 2 || abs(loc.y - downPoint.y) > 2 { dragStarted = true }
        guard dragStarted else { return }
        var origin = window.frame.origin
        origin.x += loc.x - downPoint.x
        origin.y += loc.y - downPoint.y
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragStarted = false
        let p = convert(event.locationInWindow, from: nil)
        let pin = pinRect.contains(p), close = closeRect.contains(p), toggle = toggleRect.contains(p)
        (pin || close || toggle) ? NSCursor.pointingHand.set() : NSCursor.openHand.set()
    }
}
