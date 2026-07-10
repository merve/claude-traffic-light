import AppKit
import ClaudeStatusCore

/// A **horizontal 3-light traffic light** icon for the menu bar.
/// The housing is a full stadium (pill) shape; each lens sits in a socket with a
/// slight hood on top. The active lens glows brightly (pulse + halo), the others
/// stay dim. Red left, yellow middle, green right.
///
/// - `active`: the lens that glows. `nil` means no lens is lit (light off).
/// - `phase`: 0...1 animation phase (pulse).
/// - `animate == false` renders a steady, fully bright light.
/// - `height`: target height (menu bar thickness, typically 22pt).
enum TrafficLightIcon {

    private static let colors: [State: NSColor] = [
        .red:    NSColor(calibratedRed: 0.95, green: 0.20, blue: 0.16, alpha: 1),
        .yellow: NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.05, alpha: 1),
        .green:  NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.35, alpha: 1)
    ]

    static func image(active: State?, phase: CGFloat, animate: Bool, height: CGFloat = 22) -> NSImage {
        let H = height
        let padY: CGFloat = H * 0.19                 // increased inner padding
        let lensD: CGFloat = H - 2 * padY
        let socket: CGFloat = max(1.0, lensD * 0.10) // socket ring around the lens
        let gap: CGFloat = lensD * 0.34
        let padX: CGFloat = H * 0.26                  // side padding for the rounded ends
        let firstCX = padX + lensD / 2
        let step = lensD + gap
        let width: CGFloat = 2 * padX + 3 * lensD + 2 * gap

        let size = NSSize(width: width, height: H)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

        let housing = NSColor(calibratedWhite: 0.17, alpha: 1)     // dark housing
        let socketCol = NSColor(calibratedWhite: 0.09, alpha: 1)   // socket (very dark ring)
        let capCol = NSColor(calibratedWhite: 0.08, alpha: 1.0)    // hood (dark, opaque)

        // --- Housing (stadium: corner radius = H/2) ---
        let body = CGRect(x: 0.5, y: 0.5, width: width - 1, height: H - 1)
        let bodyPath = CGPath(roundedRect: body, cornerWidth: (H - 1) / 2, cornerHeight: (H - 1) / 2, transform: nil)
        ctx.addPath(bodyPath)
        ctx.setFillColor(housing.cgColor)
        ctx.fillPath()
        ctx.addPath(bodyPath)
        ctx.setStrokeColor(NSColor(calibratedWhite: 0.10, alpha: 0.55).cgColor)
        ctx.setLineWidth(0.8)
        ctx.strokePath()

        // --- Lenses (left to right) ---
        let order: [State] = [.red, .yellow, .green]
        let cy = H / 2
        let cxs: [CGFloat] = [firstCX, firstCX + step, firstCX + 2 * step]
        let pulse: CGFloat = animate ? (0.75 + 0.25 * (0.5 - 0.5 * cos(phase * 2 * .pi))) : 1.0

        for (i, light) in order.enumerated() {
            let base = colors[light] ?? .gray
            let lensRect = CGRect(x: cxs[i] - lensD / 2, y: cy - lensD / 2, width: lensD, height: lensD)
            let lensPath = CGPath(ellipseIn: lensRect, transform: nil)

            // Socket ring (dark, slightly larger than the lens).
            let socketRect = lensRect.insetBy(dx: -socket, dy: -socket)
            ctx.setFillColor(socketCol.cgColor)
            ctx.fillEllipse(in: socketRect)

            // Lens fill.
            if light == active {   // nil → no lens is lit
                // Saturated color + strong halo. No white wash-out.
                let bright = base.blended(withFraction: 0.06, of: .white) ?? base
                ctx.saveGState()
                ctx.addPath(bodyPath); ctx.clip()
                ctx.setShadow(offset: .zero, blur: lensD * 0.6, color: base.withAlphaComponent(1.0).cgColor)
                ctx.setFillColor(bright.withAlphaComponent(pulse).cgColor)
                // Three passes: intensifies the halo (lens color stays saturated).
                ctx.fillEllipse(in: lensRect)
                ctx.fillEllipse(in: lensRect)
                ctx.fillEllipse(in: lensRect)
                ctx.restoreGState()
            } else {
                ctx.setFillColor(base.withAlphaComponent(0.30).cgColor)
                ctx.fillEllipse(in: lensRect)
            }

            // Eyelid (concave hood) — the top edge follows the lens curve, the
            // bottom edge curves upward (concave, doesn't bulge down).
            let r = lensD / 2
            let cxp = lensRect.midX
            let cyp = lensRect.midY
            let ang: CGFloat = 15 * .pi / 180
            let leftEnd = CGPoint(x: cxp - r * cos(ang), y: cyp + r * sin(ang))
            let cap = CGMutablePath()
            cap.move(to: leftEnd)
            cap.addArc(center: CGPoint(x: cxp, y: cyp), radius: r,
                       startAngle: .pi - ang, endAngle: ang, clockwise: true)
            // Control point above the endpoints → concave (eyelid); 0.42r gives a
            // noticeable thickness in the middle.
            cap.addQuadCurve(to: leftEnd, control: CGPoint(x: cxp, y: cyp + r * 0.42))
            cap.closeSubpath()
            ctx.saveGState()
            ctx.addPath(lensPath); ctx.clip()
            ctx.addPath(cap)
            ctx.setFillColor(capCol.cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            // On the active lens, a thin glass highlight just under the hood.
            if light == active {
                let hlD = lensD * 0.26
                let hl = CGRect(x: lensRect.minX + lensD * 0.20,
                                y: lensRect.minY + lensD * 0.50,
                                width: hlD, height: hlD * 0.7)
                ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.42 * pulse).cgColor)
                ctx.fillEllipse(in: hl)
            }
        }

        image.isTemplate = false
        return image
    }

    /// App icon (Finder/Spotlight/Dock): rounded macOS background + a horizontal
    /// traffic light with all three lights on. `size` is the square pixel size (e.g. 1024).
    static func appIcon(size s: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: s, height: s))
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

        // Background: rounded square + vertical gradient.
        let inset = s * 0.02
        let corner = s * 0.2237 // close to the Apple squircle
        let bgPath = CGPath(roundedRect: CGRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset),
                            cornerWidth: corner, cornerHeight: corner, transform: nil)
        ctx.saveGState()
        ctx.addPath(bgPath); ctx.clip()
        let bgColors = [NSColor(calibratedRed: 0.22, green: 0.24, blue: 0.28, alpha: 1).cgColor,
                        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1).cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
        }
        ctx.restoreGState()

        // Horizontal traffic light (same proportions as image()), all lenses lit.
        // H is sized so the width (~2.8·H) fits inside the icon with margins.
        let H = s * 0.27
        let padY = H * 0.19
        let lensD = H - 2 * padY
        let socket = max(1.0, lensD * 0.10)
        let gap = lensD * 0.34
        let padX = H * 0.26
        let tlW = 2 * padX + 3 * lensD + 2 * gap
        let ox = (s - tlW) / 2
        let oy = (s - H) / 2

        let body = CGRect(x: ox, y: oy, width: tlW, height: H)
        let bodyPath = CGPath(roundedRect: body, cornerWidth: H / 2, cornerHeight: H / 2, transform: nil)

        // Housing + a soft shadow underneath.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.03,
                      color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.addPath(bodyPath)
        ctx.setFillColor(NSColor(calibratedWhite: 0.16, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(bodyPath)
        ctx.setStrokeColor(NSColor(calibratedWhite: 0.05, alpha: 0.6).cgColor)
        ctx.setLineWidth(s * 0.004)
        ctx.strokePath()

        let cy = oy + H / 2
        let firstCX = ox + padX + lensD / 2
        let step = lensD + gap

        for (i, light) in [State.red, .yellow, .green].enumerated() {
            let base = colors[light] ?? .gray
            let cx = firstCX + CGFloat(i) * step
            let lensRect = CGRect(x: cx - lensD / 2, y: cy - lensD / 2, width: lensD, height: lensD)
            let lensPath = CGPath(ellipseIn: lensRect, transform: nil)

            // Socket.
            ctx.setFillColor(NSColor(calibratedWhite: 0.09, alpha: 1).cgColor)
            ctx.fillEllipse(in: lensRect.insetBy(dx: -socket, dy: -socket))

            // Lit lens (saturated + halo).
            let bright = base.blended(withFraction: 0.06, of: .white) ?? base
            ctx.saveGState()
            ctx.addPath(bodyPath); ctx.clip()
            ctx.setShadow(offset: .zero, blur: lensD * 0.5, color: base.withAlphaComponent(1.0).cgColor)
            ctx.setFillColor(bright.cgColor)
            ctx.fillEllipse(in: lensRect); ctx.fillEllipse(in: lensRect); ctx.fillEllipse(in: lensRect)
            ctx.restoreGState()

            // Eyelid (concave hood).
            let r = lensD / 2, cxp = lensRect.midX, cyp = lensRect.midY
            let ang: CGFloat = 15 * .pi / 180
            let leftEnd = CGPoint(x: cxp - r * cos(ang), y: cyp + r * sin(ang))
            let cap = CGMutablePath()
            cap.move(to: leftEnd)
            cap.addArc(center: CGPoint(x: cxp, y: cyp), radius: r, startAngle: .pi - ang, endAngle: ang, clockwise: true)
            cap.addQuadCurve(to: leftEnd, control: CGPoint(x: cxp, y: cyp + r * 0.42))
            cap.closeSubpath()
            ctx.saveGState(); ctx.addPath(lensPath); ctx.clip()
            ctx.addPath(cap); ctx.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 1).cgColor); ctx.fillPath()
            ctx.restoreGState()

            // Glass highlight.
            let hlD = lensD * 0.26
            let hl = CGRect(x: lensRect.minX + lensD * 0.20, y: lensRect.minY + lensD * 0.50, width: hlD, height: hlD * 0.7)
            ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.40).cgColor)
            ctx.fillEllipse(in: hl)
        }

        image.isTemplate = false
        return image
    }
}
