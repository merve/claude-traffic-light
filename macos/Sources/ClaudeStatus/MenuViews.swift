import AppKit
import ClaudeStatusCore

/// Shared width for every custom menu view so the header, rows and hint line up.
let kMenuItemWidth: CGFloat = 320

/// Traffic-light colors used inside the dropdown (match the website popover).
enum MenuPalette {
    static let red    = NSColor(srgbRed: 0.949, green: 0.200, blue: 0.161, alpha: 1)
    static let yellow = NSColor(srgbRed: 1.000, green: 0.780, blue: 0.050, alpha: 1)
    static let green  = NSColor(srgbRed: 0.180, green: 0.720, blue: 0.350, alpha: 1)
    static func color(for s: State) -> NSColor {
        switch s {
        case .red:    return red
        case .yellow: return yellow
        case .green:  return green
        }
    }
}

/// A styled session row: glowing status dot · monospace project name + detail ·
/// platform pill. Red (waiting) rows get a subtle tint; hovering highlights the row.
/// Clicking runs the owning menu item's action (open the session).
final class SessionRowView: NSView {
    private var state: State = .green
    private var isUrgent: Bool { state == .red }
    private var hovering = false
    private var hoveringClose = false

    // Close ("×") button: ends the session. Set by the owner; called with the
    // session's pid + project name when the button is clicked.
    var onClose: ((_ pid: Int32, _ project: String) -> Void)?
    private var pid: Int32 = 0
    private var project = ""
    private var canClose: Bool { pid > 0 }
    private var closeRect: NSRect = .zero

    private let nameLabel = NSTextField(labelWithString: "")
    private let subLabel  = NSTextField(labelWithString: "")
    private let pill      = NSView()
    private let pillLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: kMenuItemWidth, height: 46))
        wantsLayer = true
        setupSubviews()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private func applyLabel(_ l: NSTextField, _ font: NSFont, _ color: NSColor, align: NSTextAlignment = .left) {
        l.font = font; l.textColor = color; l.alignment = align
        l.lineBreakMode = .byTruncatingTail
        l.cell?.usesSingleLineMode = true
        l.drawsBackground = false; l.isBezeled = false; l.isEditable = false
    }

    private func setupSubviews() {
        applyLabel(nameLabel, .monospacedSystemFont(ofSize: 13, weight: .semibold), .labelColor)
        applyLabel(subLabel,  .systemFont(ofSize: 11), .secondaryLabelColor)
        applyLabel(pillLabel, .systemFont(ofSize: 10, weight: .medium), .secondaryLabelColor, align: .center)

        pill.wantsLayer = true
        pill.layer?.cornerRadius = 8

        addSubview(nameLabel)
        addSubview(subLabel)
        pill.addSubview(pillLabel)
        addSubview(pill)
    }

    func configure(project: String, detail: String, state: State, platform: String, showPlatform: Bool, pid: Int32 = 0) {
        self.state = state
        self.pid = pid
        self.project = project
        nameLabel.stringValue = project
        subLabel.stringValue = detail
        pillLabel.stringValue = platform
        pill.isHidden = !showPlatform
        pill.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.14).cgColor
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let dotX: CGFloat = 18
        let textX = dotX + 14
        let rightPad: CGFloat = 14

        // Reserve the far-right slot for the close button (only when killable).
        var rightEdge = bounds.width - rightPad
        if canClose {
            let cs: CGFloat = 16
            closeRect = NSRect(x: rightEdge - cs, y: (bounds.height - cs) / 2, width: cs, height: cs)
            rightEdge -= (cs + 10) // gap between button and pill
        } else {
            closeRect = .zero
        }

        var textRight = rightEdge
        if !pill.isHidden {
            pillLabel.sizeToFit()
            let lh = pillLabel.frame.height // intrinsic text height (for vertical centering)
            let pw = min(96, pillLabel.frame.width + 16)
            let ph: CGFloat = 18
            let px = rightEdge - pw
            pill.frame = NSRect(x: px, y: (bounds.height - ph) / 2, width: pw, height: ph)
            // Center the label vertically inside the pill (a label frame filling the
            // pill would top-align the glyphs, sitting them slightly high).
            pillLabel.frame = NSRect(x: 0, y: (ph - lh) / 2, width: pw, height: lh)
            textRight = px - 10
        }
        let textW = max(20, textRight - textX)
        // NSView is bottom-left origin: name sits above the detail line.
        nameLabel.frame = NSRect(x: textX, y: bounds.midY + 1, width: textW, height: 16)
        subLabel.frame  = NSRect(x: textX, y: bounds.midY - 17, width: textW, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let highlighted = hovering || (enclosingMenuItem?.isHighlighted ?? false)

        // Rounded row background (subtle highlight; red tint for waiting rows).
        let bgRect = bounds.insetBy(dx: 5, dy: 3)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 8, yRadius: 8)
        if highlighted {
            (isUrgent ? MenuPalette.red.withAlphaComponent(0.30)
                      : NSColor.labelColor.withAlphaComponent(0.12)).setFill()
            bgPath.fill()
        } else if isUrgent {
            MenuPalette.red.withAlphaComponent(0.12).setFill()
            bgPath.fill()
        }

        // Status dot with a soft glow.
        let d: CGFloat = 10
        let dot = NSRect(x: 18 - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        let c = MenuPalette.color(for: state)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 6, color: c.withAlphaComponent(0.9).cgColor)
        c.setFill()
        NSBezierPath(ovalIn: dot).fill()
        NSBezierPath(ovalIn: dot).fill() // second pass intensifies the halo
        ctx.restoreGState()

        // Close ("×") button — always shown faintly (discoverable); a red circle
        // with a white × on hover.
        if canClose {
            if hoveringClose {
                MenuPalette.red.withAlphaComponent(0.9).setFill()
                NSBezierPath(ovalIn: closeRect).fill()
            }
            let x = NSBezierPath()
            let inset: CGFloat = 4.5
            let r = closeRect.insetBy(dx: inset, dy: inset)
            x.move(to: NSPoint(x: r.minX, y: r.minY)); x.line(to: NSPoint(x: r.maxX, y: r.maxY))
            x.move(to: NSPoint(x: r.minX, y: r.maxY)); x.line(to: NSPoint(x: r.maxX, y: r.minY))
            x.lineWidth = 1.5
            x.lineCapStyle = .round
            (hoveringClose ? NSColor.white : NSColor.tertiaryLabelColor).setStroke()
            x.stroke()
        }
    }

    // Repaint on hover so the highlight tracks the mouse inside the menu.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  {
        hovering = false; hoveringClose = false; needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) {
        guard canClose else { return }
        // Slightly enlarged hit area so the small × is easy to hit.
        let over = closeRect.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil))
        if over != hoveringClose { hoveringClose = over; needsDisplay = true }
    }

    // Clicking the × ends the session; clicking anywhere else opens it.
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if canClose, closeRect.insetBy(dx: -4, dy: -4).contains(p) {
            enclosingMenuItem?.menu?.cancelTracking()
            onClose?(pid, project)
            return
        }
        guard let item = enclosingMenuItem, let owner = item.menu else { return }
        let idx = owner.index(of: item)
        owner.cancelTracking()
        if idx >= 0 { owner.performActionForItem(at: idx) }
    }
}

/// The dropdown header: "Active sessions" on the left, a colored count summary
/// ("2 waiting · 1 working · 3 done") on the right.
final class MenuHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: kMenuItemWidth, height: 34))
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        for l in [titleLabel, summaryLabel] {
            l.drawsBackground = false; l.isBezeled = false; l.isEditable = false
            l.cell?.usesSingleLineMode = true; l.lineBreakMode = .byTruncatingTail
        }
        summaryLabel.alignment = .right
        addSubview(titleLabel)
        addSubview(summaryLabel)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(title: String, summary: NSAttributedString) {
        titleLabel.stringValue = title
        summaryLabel.attributedStringValue = summary
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let y = (bounds.height - 16) / 2
        // Summary takes its natural width on the right; the title truncates into
        // whatever space is left, so the two never overlap.
        summaryLabel.sizeToFit()
        let sw = min(summaryLabel.frame.width, bounds.width - 110)
        summaryLabel.frame = NSRect(x: bounds.width - 16 - sw, y: y, width: sw, height: 16)
        let titleRight = bounds.width - 16 - sw - 12
        titleLabel.frame = NSRect(x: 16, y: y, width: max(20, titleRight - 16), height: 16)
    }
}

/// A quiet, centered footer hint ("Click a session to jump to it").
final class MenuHintView: NSView {
    private let label = NSTextField(labelWithString: "")
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: kMenuItemWidth, height: 28))
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        label.drawsBackground = false; label.isBezeled = false; label.isEditable = false
        label.cell?.usesSingleLineMode = true
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    func configure(_ text: String) { label.stringValue = text; needsLayout = true }
    override func layout() {
        super.layout()
        label.frame = NSRect(x: 12, y: (bounds.height - 14) / 2, width: bounds.width - 24, height: 14)
    }
}
