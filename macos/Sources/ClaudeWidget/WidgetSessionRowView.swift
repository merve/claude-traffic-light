import AppKit
import ClaudeStatusCore

/// A styled session row for the floating widget: glowing status dot · monospace project
/// name + detail · platform pill · close (✕) button. Standalone `NSView` (not a menu item,
/// unlike the menu-bar app's `SessionRowView`) so it can sit directly in the widget window
/// and stay live while the mouse is over it. Mirrors the Windows port's `SessionRowControl`.
final class WidgetSessionRowView: NSView {
    static let width: CGFloat = 300
    static let height: CGFloat = 52

    private let theme: WidgetTheme
    private var state: State = .green
    private var isUrgent: Bool { state == .red }
    private var hovering = false
    private var hoveringClose = false

    private var pid: Int32 = 0
    private var project = ""
    private var canClose: Bool { pid > 0 }
    private var closeRect: NSRect = .zero
    private var trackingArea: NSTrackingArea?

    var onClicked: (() -> Void)?
    var onClose: ((Int32) -> Void)?

    private static let red = NSColor(calibratedRed: 0.949, green: 0.200, blue: 0.161, alpha: 1)
    private static let yellow = NSColor(calibratedRed: 1.000, green: 0.780, blue: 0.050, alpha: 1)
    private static let green = NSColor(calibratedRed: 0.180, green: 0.720, blue: 0.350, alpha: 1)

    private static func color(for s: State) -> NSColor {
        switch s {
        case .red: return red
        case .yellow: return yellow
        case .green: return green
        }
    }

    private let nameLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")
    private let pill = NSView()
    private let pillLabel = NSTextField(labelWithString: "")

    init(theme: WidgetTheme) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        wantsLayer = true
        setup()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    // Without this, the first click while the widget's window isn't key only activates the
    // window (the row's click doesn't fire) — a second click would be needed to open it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func style(_ l: NSTextField, _ font: NSFont, _ color: NSColor, align: NSTextAlignment = .left) {
        l.font = font; l.textColor = color; l.alignment = align
        l.lineBreakMode = .byTruncatingTail
        l.cell?.usesSingleLineMode = true
        l.drawsBackground = false; l.isBezeled = false; l.isEditable = false
    }

    private func setup() {
        style(nameLabel, .monospacedSystemFont(ofSize: 13, weight: .semibold), theme.text)
        style(subLabel, .systemFont(ofSize: 11), theme.subText)
        style(pillLabel, .systemFont(ofSize: 10, weight: .medium), theme.subText, align: .center)
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 8
        addSubview(nameLabel)
        addSubview(subLabel)
        pill.addSubview(pillLabel)
        addSubview(pill)
    }

    func configure(session s: SessionStatus, detail: String, platform: String) {
        state = s.state
        pid = s.pid
        project = s.project
        nameLabel.stringValue = s.project
        subLabel.stringValue = detail
        pillLabel.stringValue = platform
        pill.layer?.backgroundColor = theme.subText.withAlphaComponent(0.16).cgColor
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let dotX: CGFloat = 18
        let textX = dotX + 14
        let rightPad: CGFloat = 14

        var rightEdge = bounds.width - rightPad
        if canClose {
            let cs: CGFloat = 16
            closeRect = NSRect(x: rightEdge - cs, y: (bounds.height - cs) / 2, width: cs, height: cs)
            rightEdge -= (cs + 10)
        } else {
            closeRect = .zero
        }

        var textRight = rightEdge
        pillLabel.sizeToFit()
        let lh = pillLabel.frame.height
        let pw = min(96, pillLabel.frame.width + 16)
        let ph: CGFloat = 18
        let px = rightEdge - pw
        pill.frame = NSRect(x: px, y: (bounds.height - ph) / 2, width: pw, height: ph)
        pillLabel.frame = NSRect(x: 0, y: (ph - lh) / 2, width: pw, height: lh)
        textRight = px - 10

        let textW = max(20, textRight - textX)
        // Flipped view: name sits above the detail line (smaller y = higher on screen).
        nameLabel.frame = NSRect(x: textX, y: bounds.midY - 17, width: textW, height: 16)
        subLabel.frame = NSRect(x: textX, y: bounds.midY + 2, width: textW, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bgRect = bounds.insetBy(dx: 5, dy: 3)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 8, yRadius: 8)
        if hovering {
            (isUrgent ? Self.red.withAlphaComponent(0.30) : theme.text.withAlphaComponent(0.10)).setFill()
            bgPath.fill()
        } else if isUrgent {
            Self.red.withAlphaComponent(0.12).setFill()
            bgPath.fill()
        }

        let d: CGFloat = 10
        let dot = NSRect(x: 18 - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        let c = Self.color(for: state)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 6, color: c.withAlphaComponent(0.9).cgColor)
        c.setFill()
        NSBezierPath(ovalIn: dot).fill()
        NSBezierPath(ovalIn: dot).fill()
        ctx.restoreGState()

        if canClose {
            if hoveringClose {
                Self.red.withAlphaComponent(0.9).setFill()
                NSBezierPath(ovalIn: closeRect).fill()
            }
            let x = NSBezierPath()
            let inset: CGFloat = 4.5
            let r = closeRect.insetBy(dx: inset, dy: inset)
            x.move(to: NSPoint(x: r.minX, y: r.minY)); x.line(to: NSPoint(x: r.maxX, y: r.maxY))
            x.move(to: NSPoint(x: r.minX, y: r.maxY)); x.line(to: NSPoint(x: r.maxX, y: r.minY))
            x.lineWidth = 1.5
            x.lineCapStyle = .round
            (hoveringClose ? NSColor.white : theme.subText).setStroke()
            x.stroke()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; hoveringClose = false; needsDisplay = true }
    override func mouseMoved(with event: NSEvent) {
        guard canClose else { return }
        let over = closeRect.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil))
        if over != hoveringClose { hoveringClose = over; needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if canClose, closeRect.insetBy(dx: -4, dy: -4).contains(p) {
            onClose?(pid)
            return
        }
        onClicked?()
    }
}
