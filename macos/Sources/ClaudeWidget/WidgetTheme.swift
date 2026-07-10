import AppKit

/// Chrome colors for the widget window, resolved against the current effective appearance
/// (so the widget matches Light/Dark Mode automatically). Kept as plain values (not
/// dynamic NSColor) since the window redraws itself on `viewDidChangeEffectiveAppearance`.
struct WidgetTheme {
    let background: NSColor
    let text: NSColor
    let subText: NSColor
    let border: NSColor
    let separator: NSColor

    static let dark = WidgetTheme(
        background: NSColor(calibratedWhite: 0.13, alpha: 1),
        text: NSColor(calibratedWhite: 0.95, alpha: 1),
        subText: NSColor(calibratedWhite: 0.95, alpha: 0.55),
        border: NSColor(calibratedWhite: 1, alpha: 0.12),
        separator: NSColor(calibratedWhite: 1, alpha: 0.09))

    static let light = WidgetTheme(
        background: NSColor(calibratedWhite: 0.98, alpha: 1),
        text: NSColor(calibratedWhite: 0.10, alpha: 1),
        subText: NSColor(calibratedWhite: 0.10, alpha: 0.55),
        border: NSColor(calibratedWhite: 0, alpha: 0.12),
        separator: NSColor(calibratedWhite: 0, alpha: 0.08))

    static func current(for appearance: NSAppearance?) -> WidgetTheme {
        let dark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? .dark : .light
    }
}
