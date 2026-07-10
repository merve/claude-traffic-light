import AppKit
import ClaudeStatusCore

/// A realistic **vertical** traffic light (red top, yellow mid, green bottom) drawn as the
/// widget's left rail — or, when collapsed, as the entire widget housing. Mirrors the
/// Windows port's `TrafficLightPanel`: metallic gradient housing, lens sockets, sun-visor
/// hoods, glow + glass gloss on the active lens. The active lens pulses.
///
/// Also owns the widget's drag-to-move and (when collapsed) edge-to-resize gestures, since
/// on both platforms the light IS the draggable/resizable surface.
final class VerticalTrafficLightView: NSView {
    private var theme: WidgetTheme
    private var active: State?
    private var phase: CGFloat = 0

    /// When true the housing fills the whole view (collapsed widget, no side gap).
    var fill = false
    /// When true, dragging near an edge/corner resizes the (collapsed) window.
    var resizable = false

    /// Raised on a click (not a drag) — used to toggle the list open/closed.
    var onToggle: (() -> Void)?

    private static let red = NSColor(calibratedRed: 0.95, green: 0.20, blue: 0.16, alpha: 1)
    private static let yellow = NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.05, alpha: 1)
    private static let green = NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.35, alpha: 1)

    // Collapsed-widget aspect lock (matches the Windows port's 52×140 rail proportions).
    // Sourced from `WidgetLayout` (tested, single source of truth) — not duplicated here.
    static let collapsedAspect = CGFloat(WidgetLayout.collapsedAspect)
    static let minCollapsedH = CGFloat(WidgetLayout.minCollapsedH)
    static let maxCollapsedH = CGFloat(WidgetLayout.maxCollapsedH)

    private var downPoint: NSPoint = .zero
    private var dragStarted = false
    private var resizeEdge: WidgetResize.Edge?
    private let edgeHit: CGFloat = 7

    init(theme: WidgetTheme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true } // top-left origin, y-down — matches the Windows drawing math

    // Without this, the first click while the widget's window isn't key only activates the
    // window (drag/resize doesn't fire) — a second click would be needed to actually act.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setTheme(_ t: WidgetTheme) { theme = t; needsDisplay = true }

    func setState(_ s: State?) {
        guard active != s else { return }
        active = s
        needsDisplay = true
    }

    func setPhase(_ p: CGFloat) {
        phase = p
        if active == .red || active == .yellow { needsDisplay = true }
    }

    private static func color(for s: State) -> NSColor {
        switch s {
        case .red: return red
        case .yellow: return yellow
        case .green: return green
        }
    }

    private var pulse: CGFloat {
        let animate = active == .red || active == .yellow
        return animate ? 0.72 + 0.28 * (0.5 - 0.5 * cos(phase * 2 * .pi)) : 1.0
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(true)
        theme.background.setFill()
        bounds.fill()

        // --- Housing geometry ---
        var marginY: CGFloat, gapY: CGFloat, lensD: CGFloat
        var housingW: CGFloat, housingH: CGFloat, hx: CGFloat, hy: CGFloat, corner: CGFloat

        if fill {
            // Housing fills the whole view (collapsed: the light IS the widget, no side gap).
            housingW = bounds.width
            housingH = bounds.height
            hx = 0; hy = 0
            marginY = housingH * 0.07
            let inner = housingH - 2 * marginY
            lensD = inner / 3.4
            gapY = (inner - 3 * lensD) / 2
            corner = housingW * 0.30
        } else {
            // Rail mode: housing scales to height (capped) and is centered.
            let maxH = min(bounds.height - 20, 150)
            guard maxH >= 40 else { return }
            marginY = maxH * 0.08
            let inner = maxH - 2 * marginY
            gapY = inner * 0.055
            lensD = (inner - 2 * gapY) / 3
            let sideMargin = lensD * 0.34
            housingW = lensD + 2 * sideMargin
            housingH = maxH
            hx = (bounds.width - housingW) / 2
            hy = (bounds.height - housingH) / 2
            corner = lensD * 0.42
        }
        let cx = hx + housingW / 2

        let housingRect = CGRect(x: hx, y: hy, width: housingW, height: housingH)
        if fill {
            // Collapsed: the housing IS the window; DWM/CALayer rounds the window corners
            // for us, so fill edge-to-edge (fully opaque) with no separate clipped shape.
            drawVerticalGradient(ctx, rect: housingRect,
                                 top: NSColor(calibratedWhite: 0.235, alpha: 1),
                                 bottom: NSColor(calibratedWhite: 0.07, alpha: 1))
            drawSheen(ctx, rect: housingRect)
        } else {
            let path = Self.rounded(housingRect, corner)
            ctx.saveGState()
            ctx.addPath(path); ctx.clip()
            drawVerticalGradient(ctx, rect: housingRect,
                                 top: NSColor(calibratedWhite: 0.235, alpha: 1),
                                 bottom: NSColor(calibratedWhite: 0.07, alpha: 1))
            drawSheen(ctx, rect: housingRect)
            ctx.restoreGState()

            ctx.addPath(path)
            ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.55).cgColor)
            ctx.setLineWidth(1.4)
            ctx.strokePath()
        }

        // --- Three lenses (red top, yellow mid, green bottom) ---
        let firstCy = hy + marginY + lensD / 2
        let step = lensD + gapY
        let order: [State] = [.red, .yellow, .green]
        let p = pulse
        for (i, light) in order.enumerated() {
            let cy = firstCy + CGFloat(i) * step
            drawLens(ctx, cx: cx, cy: cy, r: lensD / 2, color: Self.color(for: light),
                     on: active == light, pulse: p)
        }
    }

    private func drawVerticalGradient(_ ctx: CGContext, rect: CGRect, top: NSColor, bottom: NSColor) {
        guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [top.cgColor, bottom.cgColor] as CFArray,
                                    locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.midX, y: rect.minY),
                              end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        ctx.restoreGState()
    }

    /// Metallic sheen: soft horizontal highlight on the left, clipped to the housing.
    private func drawSheen(_ ctx: CGContext, rect: CGRect) {
        guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [NSColor(calibratedWhite: 1, alpha: 0.16).cgColor,
                                             NSColor(calibratedWhite: 1, alpha: 0).cgColor] as CFArray,
                                    locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.55, height: rect.height))
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.midY),
                              end: CGPoint(x: rect.minX + rect.width, y: rect.midY), options: [])
        ctx.restoreGState()
    }

    private func drawLens(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, r: CGFloat, color: NSColor, on: Bool, pulse: CGFloat) {
        // Socket: dark inset ring giving depth.
        let sr = r * 1.16
        ctx.setFillColor(NSColor(calibratedWhite: 0.05, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - sr, y: cy - sr, width: 2 * sr, height: 2 * sr))
        ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.35).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: CGRect(x: cx - sr, y: cy - sr, width: 2 * sr, height: 2 * sr))

        let rect = CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)

        if on {
            // Outer glow (kept tight so it doesn't bleed into neighbours).
            let glowR = r * 1.7
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [color.withAlphaComponent(0.51 * pulse).cgColor,
                                              color.withAlphaComponent(0).cgColor] as CFArray,
                                     locations: [0, 1]) {
                ctx.drawRadialGradient(grad, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: glowR, options: [])
            }
            // Bulb: radial bright center → saturated edge.
            let bright = color.blended(withFraction: 0.55 * pulse, of: .white) ?? color
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [bright.cgColor, color.cgColor] as CFArray,
                                     locations: [0, 1]) {
                ctx.saveGState()
                ctx.addPath(CGPath(ellipseIn: rect, transform: nil)); ctx.clip()
                ctx.drawRadialGradient(grad, startCenter: CGPoint(x: cx - r * 0.2, y: cy + r * 0.25), startRadius: 0,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: r * 1.15, options: [])
                ctx.restoreGState()
            }
            // Bottom inner shading for a spherical feel (clipped to the bulb; flipped view
            // → "bottom" visually is the larger-Y side).
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [NSColor(calibratedWhite: 0, alpha: 0).cgColor,
                                              NSColor(calibratedWhite: 0, alpha: 0.27).cgColor] as CFArray,
                                     locations: [0, 1]) {
                ctx.saveGState()
                ctx.addPath(CGPath(ellipseIn: rect, transform: nil)); ctx.clip()
                ctx.drawLinearGradient(grad, start: CGPoint(x: cx, y: cy), end: CGPoint(x: cx, y: cy + r), options: [])
                ctx.restoreGState()
            }
            // Specular glass highlight (top-left; flipped view → smaller-Y side).
            let gr = CGRect(x: cx - r * 0.55, y: cy - r * 0.72, width: r * 0.9, height: r * 0.6)
            ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.59 * pulse).cgColor)
            ctx.fillEllipse(in: gr)
        } else {
            // Unlit colored bulb: dark, faintly tinted, with a faint top glass sheen.
            let dark = color.blended(withFraction: 0.82, of: NSColor(calibratedWhite: 0.07, alpha: 1)) ?? color
            ctx.setFillColor(dark.cgColor)
            ctx.fillEllipse(in: rect)
            let sheen = CGRect(x: cx - r * 0.5, y: cy - r * 0.65, width: r * 0.8, height: r * 0.45)
            ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.09).cgColor)
            ctx.fillEllipse(in: sheen)
            ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.27).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: rect)
        }

        // Sun visor (hood): a filled crescent over the top of the lens + a soft shadow it
        // casts. "Top" in this flipped view is the smaller-Y side.
        let ro = r * 1.30, ri = r * 1.04
        let vcy = cy - r * 0.14
        let hood = CGMutablePath()
        hood.addArc(center: CGPoint(x: cx, y: vcy), radius: ro,
                   startAngle: 200 * .pi / 180, endAngle: 340 * .pi / 180, clockwise: false)
        hood.addArc(center: CGPoint(x: cx, y: vcy), radius: ri,
                   startAngle: 340 * .pi / 180, endAngle: 200 * .pi / 180, clockwise: true)
        hood.closeSubpath()
        ctx.addPath(hood)
        ctx.setFillColor(NSColor(calibratedWhite: 0.04, alpha: 0.96).cgColor)
        ctx.fillPath()
        ctx.addPath(hood)
        ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.35).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()

        // Shadow the hood casts on the top of the lens.
        let castShadow = CGMutablePath()
        castShadow.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                          startAngle: 200 * .pi / 180, endAngle: 340 * .pi / 180, clockwise: false)
        ctx.addPath(castShadow)
        ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.24).cgColor)
        ctx.setLineWidth(max(1.5, r * 0.22))
        ctx.strokePath()
    }

    private static func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // MARK: - Drag-to-move / edge-to-resize / click-to-toggle

    private func hitEdge(_ p: NSPoint) -> WidgetResize.Edge? {
        guard resizable else { return nil }
        let l = p.x <= edgeHit, r = p.x >= bounds.width - edgeHit
        let t = p.y <= edgeHit, b = p.y >= bounds.height - edgeHit // flipped: y-down, so small y = visual top
        if t && l { return .topLeft }
        if t && r { return .topRight }
        if b && l { return .bottomLeft }
        if b && r { return .bottomRight }
        if l { return .left }
        if r { return .right }
        if t { return .top }
        if b { return .bottom }
        return nil
    }

    override func resetCursorRects() {
        // Base cursor: the whole light is a drag handle (see the type doc), so an open hand
        // signals "grab here to move the window" everywhere resize edges don't take over.
        addCursorRect(bounds, cursor: .openHand)
        guard resizable else { return }
        let edges: [(NSRect, NSCursor)] = [
            (NSRect(x: 0, y: 0, width: edgeHit, height: bounds.height), .resizeLeftRight),
            (NSRect(x: bounds.width - edgeHit, y: 0, width: edgeHit, height: bounds.height), .resizeLeftRight),
            (NSRect(x: 0, y: 0, width: bounds.width, height: edgeHit), .resizeUpDown),
            (NSRect(x: 0, y: bounds.height - edgeHit, width: bounds.width, height: edgeHit), .resizeUpDown),
        ]
        for (rect, cursor) in edges { addCursorRect(rect, cursor: cursor) }
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        dragStarted = false
        resizeEdge = hitEdge(convert(event.locationInWindow, from: nil))
        if resizeEdge == nil { NSCursor.closedHand.set() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let loc = event.locationInWindow

        if let edge = resizeEdge {
            // Convert the current window frame to the Windows-style (top<bottom, y-down)
            // convention WidgetResize expects, apply, then convert back. AppKit frames are
            // bottom-left-origin/y-up, so "top" (visual) = frame.maxY.
            let f = window.frame
            let screenLoc = window.convertPoint(toScreen: loc)
            var l = f.minX, r = f.maxX, top = -f.maxY, bottom = -f.minY
            switch edge {
            case .left, .topLeft, .bottomLeft: l = screenLoc.x
            case .right, .topRight, .bottomRight: r = screenLoc.x
            default: break
            }
            switch edge {
            case .top, .topLeft, .topRight: top = -screenLoc.y
            case .bottom, .bottomLeft, .bottomRight: bottom = -screenLoc.y
            default: break
            }
            let corrected = WidgetResize.apply(edge: edge, left: l, top: top, right: r, bottom: bottom,
                                                aspect: Double(Self.collapsedAspect),
                                                minH: Double(Self.minCollapsedH), maxH: Double(Self.maxCollapsedH))
            let newFrame = NSRect(x: corrected.left, y: -corrected.bottom,
                                 width: corrected.right - corrected.left,
                                 height: corrected.bottom - corrected.top)
            window.setFrame(newFrame, display: true)
            dragStarted = true
            return
        }

        if abs(loc.x - downPoint.x) > 4 || abs(loc.y - downPoint.y) > 4 { dragStarted = true }
        guard dragStarted else { return }
        var origin = window.frame.origin
        origin.x += loc.x - downPoint.x
        origin.y += loc.y - downPoint.y
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        if !dragStarted { onToggle?() }
        let wasResizing = resizeEdge != nil
        dragStarted = false
        resizeEdge = nil
        if !wasResizing { NSCursor.openHand.set() }
    }
}
