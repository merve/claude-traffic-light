import AppKit
import ClaudeStatusCore

// Test/debug: `ClaudeStatus --render <red|yellow|green> <out.png> [scale]`
// Dumps the icon to a file and exits (for visual verification).
if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--render" {
    let state = State(rawValue: CommandLine.arguments[2]) // "off"/invalid → nil (light off)
    let out = CommandLine.arguments[3]
    let scale = CommandLine.arguments.count >= 5 ? (Double(CommandLine.arguments[4]) ?? 1) : 1
    let img = TrafficLightIcon.image(active: state, phase: 0, animate: false)
    let target = NSSize(width: img.size.width * scale, height: img.size.height * scale)
    let scaled = NSImage(size: target)
    scaled.lockFocus()
    img.draw(in: NSRect(origin: .zero, size: target))
    scaled.unlockFocus()
    if let tiff = scaled.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: out))
    }
    exit(0)
}

// `ClaudeStatus --appicon <out.png> <size>` → writes the app icon to a PNG
// (build-app.sh uses this to generate the .icns).
if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--appicon" {
    let out = CommandLine.arguments[2]
    let size = CGFloat(Double(CommandLine.arguments[3]) ?? 1024)
    let img = TrafficLightIcon.appIcon(size: size)
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: out))
    }
    exit(0)
}

// Test/debug: `ClaudeStatus --preview-menu <out.png>` → renders the styled dropdown
// (header + session rows + hint) offscreen to a PNG for visual verification.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--preview-menu" {
    let out = CommandLine.arguments[2]
    _ = NSApplication.shared // spin up AppKit

    // A dark card that mimics the menu material, plus thin separators.
    final class PreviewCard: NSView {
        var sepYs: [CGFloat] = []
        override func draw(_ dirtyRect: NSRect) {
            NSColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1).setFill()
            let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
            path.fill()
            NSColor.white.withAlphaComponent(0.10).setStroke()
            path.lineWidth = 1; path.stroke()
            NSColor.white.withAlphaComponent(0.08).setFill()
            for y in sepYs { NSRect(x: 12, y: y, width: bounds.width - 24, height: 1).fill() }
        }
    }

    let W = kMenuItemWidth
    let topPad: CGFloat = 8, botPad: CGFloat = 8
    let headerH: CGFloat = 34, rowH: CGFloat = 46, hintH: CGFloat = 28, sepGap: CGFloat = 11

    // Sample fleet (mirrors the website popover).
    let rows: [(String, String, State, String)] = [
        ("api-gateway",     "Asking a question · 19 sec. ago", .red,    "VS Code"),
        ("web-frontend",    "Working…",                        .yellow, "iTerm"),
        ("data-pipeline",   "Working…",                        .yellow, "Claude"),
        ("docs-site",       "Done · 1 min. ago",               .green,  "Cursor"),
        ("infra-terraform", "Done · 3 hr. ago",                .green,  "Ghostty"),
    ]

    let totalH = topPad + headerH + sepGap + CGFloat(rows.count) * rowH + hintH + sepGap * 0 + botPad
    let card = PreviewCard(frame: NSRect(x: 0, y: 0, width: W, height: totalH))
    card.appearance = NSAppearance(named: .darkAqua)

    // Non-flipped coords: place from the top downward.
    var y = totalH - topPad
    let summary = NSMutableAttributedString()
    func addSummary(_ n: Int, _ w: String, _ c: NSColor, _ wt: NSFont.Weight) {
        guard n > 0 else { return }
        if summary.length > 0 { summary.append(NSAttributedString(string: "  ·  ", attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.systemFont(ofSize: 11)])) }
        summary.append(NSAttributedString(string: "\(n) \(w)", attributes: [.foregroundColor: c, .font: NSFont.systemFont(ofSize: 11, weight: wt)]))
    }
    addSummary(1, "waiting", MenuPalette.red, .semibold)
    addSummary(2, "working", .secondaryLabelColor, .regular)

    y -= headerH
    let header = MenuHeaderView()
    header.frame = NSRect(x: 0, y: y, width: W, height: headerH)
    header.configure(title: "Active sessions", summary: summary)
    card.addSubview(header)

    y -= sepGap
    card.sepYs.append(y + sepGap / 2)

    for r in rows {
        y -= rowH
        let row = SessionRowView()
        row.frame = NSRect(x: 0, y: y, width: W, height: rowH)
        row.configure(project: r.0, detail: r.1, state: r.2, platform: r.3, showPlatform: true, pid: 1234)
        card.addSubview(row)
    }

    y -= hintH
    let hint = MenuHintView()
    hint.frame = NSRect(x: 0, y: y, width: W, height: hintH)
    hint.configure("Click a session to jump to it")
    card.addSubview(hint)

    // Render at 2x for crisp text.
    let scale: CGFloat = 2
    if let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                  pixelsWide: Int(W * scale), pixelsHigh: Int(totalH * scale),
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0) {
        rep.size = NSSize(width: W, height: totalH)
        card.cacheDisplay(in: card.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
        }
    }
    exit(0)
}

// Test/debug: `ClaudeStatus --strings` → prints the strings for the active language.
if CommandLine.arguments.contains("--strings") {
    let l = L10n.current
    print("localeID:", l.localeID)
    print("working:", l.working, "| asking:", l.asking, "| done:", l.done)
    print("summary words:", l.waitingWord, "/", l.workingWord, "/", l.doneWord)
    print("menu:", l.refresh, "/", l.quit, "| noSessions:", l.noSessions)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// No Dock icon; live only in the menu bar (agent app).
app.setActivationPolicy(.accessory)

app.run()
