import Foundation

/// Pure layout math for the floating widget — kept free of AppKit so expand/collapse and
/// window-size regressions can be caught by tests instead of only by eyeballing the running
/// app. `WidgetController` computes its actual window/subview geometry through these
/// functions (not a parallel mirror kept only for tests), so a passing test here is a
/// guarantee about the real app's behavior.
public enum WidgetLayout {
    public static let railW: Double = 76         // left traffic-light rail
    public static let rowWidth: Double = 300     // session row column width
    public static let rowHeight: Double = 52
    public static let pad: Double = 12           // outer padding (top / bottom)
    public static let titleH: Double = 26
    public static let titleGap: Double = 8       // title → divider
    public static let dividerGap: Double = 10    // divider → content
    public static let minContentH: Double = 96   // keeps the light looking good with 0-1 sessions

    public static var dividerY: Double { pad + titleH + titleGap }
    public static var contentTop: Double { dividerY + 1 + dividerGap }

    /// Row-list height for a given session count (the empty-state placeholder counts as 44).
    /// No cap — every session gets a row, however many there are.
    public static func listHeight(sessionCount: Int) -> Double {
        sessionCount == 0 ? 44 : Double(sessionCount) * rowHeight
    }

    /// Total (width, height) of the EXPANDED widget for a given session count.
    public static func expandedSize(sessionCount: Int) -> (width: Double, height: Double) {
        let listH = listHeight(sessionCount: sessionCount)
        let height = max(contentTop + listH + pad, contentTop + minContentH + pad)
        return (railW + rowWidth, height)
    }

    /// Where the row list starts (vertically centered against the light rail) and how tall
    /// the available content area is, for a widget already sized to `totalHeight`.
    public static func rowsLayout(sessionCount: Int, totalHeight: Double) -> (contentHeight: Double, rowsTop: Double) {
        let listH = listHeight(sessionCount: sessionCount)
        let contentHeight = totalHeight - contentTop - pad
        let rowsTop = contentTop + (contentHeight - listH) / 2
        return (contentHeight, rowsTop)
    }

    // MARK: - Collapsed (light-only) sizing — same aspect/clamp bounds as `WidgetResize`'s drag-resize.

    public static let collapsedAspect: Double = 52.0 / 140.0
    public static let minCollapsedH: Double = 96
    public static let maxCollapsedH: Double = 300

    /// Total (width, height) of the COLLAPSED widget for a given persisted height (clamped
    /// defensively in case a stale/out-of-range value was ever persisted).
    public static func collapsedSize(height: Double) -> (width: Double, height: Double) {
        let h = min(max(height, minCollapsedH), maxCollapsedH)
        return ((h * collapsedAspect).rounded(), h)
    }
}

/// Resizes a window frame to a new size while preserving its visual TOP-LEFT corner. AppKit
/// frames are bottom-left-origin/y-up, so the "top" edge is `originY + height`. Matches
/// WinForms' `ClientSize` setter (which preserves `Location`), so toggling expanded/collapsed
/// grows or shrinks the widget from the bottom-right instead of jumping it around the screen.
public enum WidgetWindowResize {
    public static func preservingTopLeft(
        oldOriginX: Double, oldOriginY: Double, oldHeight: Double,
        newWidth: Double, newHeight: Double
    ) -> (x: Double, y: Double, width: Double, height: Double) {
        let topEdge = oldOriginY + oldHeight
        return (oldOriginX, topEdge - newHeight, newWidth, newHeight)
    }
}
