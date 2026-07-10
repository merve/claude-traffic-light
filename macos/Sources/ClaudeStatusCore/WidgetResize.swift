import Foundation

/// Pure geometry for the collapsed widget's aspect-locked resize. Kept free of AppKit so
/// the traffic-light proportions, size clamping and edge anchoring are unit-testable.
/// The widget window feeds it the proposed frame and the drag edge; it returns the
/// corrected frame. Mirrors the Windows port's `WidgetResize` (`WM_SIZING` handler) so both
/// platforms clamp/anchor identically.
public enum WidgetResize {

    /// Which edge/corner is being dragged.
    public enum Edge {
        case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    }

    /// Correct a proposed frame so it keeps the traffic-light aspect ratio and its height
    /// stays within `[minH, maxH]`. Dragging a side edge lets that dimension drive; the
    /// opposite side/corner stays anchored so the widget grows toward the cursor, not away
    /// from it.
    ///
    /// - Parameters:
    ///   - edge: the dragged edge/corner.
    ///   - aspect: width / height ratio to preserve.
    public static func apply(
        edge: Edge, left: Double, top: Double, right: Double, bottom: Double,
        aspect: Double, minH: Double, maxH: Double
    ) -> (left: Double, top: Double, right: Double, bottom: Double) {
        var w = right - left
        var h = bottom - top

        // Bounds are rounded to whole points first (mirrors the Windows port's int RECT
        // arithmetic), then the proposed dimension is clamped against those whole-point
        // bounds — NOT clamped against the unrounded bounds and rounded afterward, which
        // would derive the locked dimension from a slightly different (unrounded) value.
        let horizontal = edge == .left || edge == .right // a left/right edge → width drives
        if horizontal {
            let minW = (minH * aspect).rounded()
            let maxW = (maxH * aspect).rounded()
            w = w.clamped(to: minW, maxW)
            h = (w / aspect).rounded()
        } else {
            h = h.clamped(to: minH, maxH)
            w = (h * aspect).rounded()
        }

        var newLeft = left, newTop = top, newRight = right, newBottom = bottom
        switch edge {
        case .left, .topLeft, .bottomLeft: newLeft = right - w
        default: newRight = left + w
        }
        switch edge {
        case .top, .topLeft, .topRight: newTop = bottom - h
        default: newBottom = top + h
        }
        return (newLeft, newTop, newRight, newBottom)
    }
}

private extension Double {
    func clamped(to lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
