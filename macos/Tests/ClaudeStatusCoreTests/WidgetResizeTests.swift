import XCTest
@testable import ClaudeStatusCore

/// The collapsed widget's aspect-locked resize geometry. Verifies that the traffic-light
/// proportions are preserved, the height is clamped to [96, 300], and the edge opposite the
/// drag stays anchored so the widget grows toward the cursor. Mirrors the Windows port's
/// `WidgetResizeTests` (same 52×140 aspect, same clamp range) so both platforms behave
/// identically; coordinates here use the Windows-style convention (top < bottom).
final class WidgetResizeTests: XCTestCase {
    // Same proportions the widget uses: 52 × 140 collapsed.
    private let aspect = 52.0 / 140.0
    private let minH = 96.0
    private let maxH = 300.0

    private func apply(_ edge: WidgetResize.Edge, _ l: Double, _ t: Double, _ r: Double, _ b: Double)
        -> (left: Double, top: Double, right: Double, bottom: Double) {
        WidgetResize.apply(edge: edge, left: l, top: t, right: r, bottom: b, aspect: aspect, minH: minH, maxH: maxH)
    }

    private func widthFor(_ h: Double) -> Double { (h * aspect).rounded() }

    func testDraggingVerticalEdgeDerivesWidthFromHeight() {
        let rc = apply(.bottom, 0, 0, 52, 200)
        XCTAssertEqual(rc.bottom - rc.top, 200)
        XCTAssertEqual(rc.right - rc.left, widthFor(200))
    }

    func testDraggingBottomPastMaxClampsHeightAndKeepsTopLeftAnchored() {
        let rc = apply(.bottom, 100, 100, 152, 500) // proposes height 400
        XCTAssertEqual(rc.bottom - rc.top, maxH)
        XCTAssertEqual(rc.right - rc.left, widthFor(maxH))
        XCTAssertEqual(rc.left, 100)
        XCTAssertEqual(rc.top, 100)
    }

    func testDraggingTopBelowMinClampsHeightAndKeepsBottomAnchored() {
        let rc = apply(.top, 100, 100, 152, 150) // proposes height 50
        XCTAssertEqual(rc.bottom - rc.top, minH)
        XCTAssertEqual(rc.bottom, 150)
        XCTAssertEqual(rc.top, 150 - minH)
    }

    func testDraggingHorizontalEdgeDerivesHeightFromWidth() {
        let rc = apply(.right, 100, 100, 300, 240)
        let maxW = (maxH * aspect).rounded()
        XCTAssertEqual(rc.right - rc.left, maxW)
        XCTAssertEqual(rc.bottom - rc.top, (maxW / aspect).rounded())
        XCTAssertEqual(rc.left, 100)
        XCTAssertEqual(rc.top, 100)
    }

    func testDraggingLeftNarrowerThanMinClampsAndKeepsRightAnchored() {
        let rc = apply(.left, 100, 100, 110, 240) // proposes width 10
        let minW = (minH * aspect).rounded()
        XCTAssertEqual(rc.right - rc.left, minW)
        XCTAssertEqual(rc.right, 110)
    }

    func testTopLeftCornerAnchorsBottomRight() {
        let rc = apply(.topLeft, 100, 100, 152, 500)
        XCTAssertEqual(rc.right, 152)
        XCTAssertEqual(rc.bottom, 500)
        XCTAssertEqual(rc.bottom - rc.top, maxH)
        XCTAssertEqual(rc.right - rc.left, widthFor(maxH))
    }

    func testBottomRightCornerAnchorsTopLeft() {
        let rc = apply(.bottomRight, 100, 100, 152, 500)
        XCTAssertEqual(rc.left, 100)
        XCTAssertEqual(rc.top, 100)
        XCTAssertEqual(rc.bottom - rc.top, maxH)
        XCTAssertEqual(rc.right - rc.left, widthFor(maxH))
    }

    func testAspectRatioPreservedWithinRange() {
        for (edge, height) in [(WidgetResize.Edge.bottom, 140.0), (.top, 140.0), (.bottomRight, 220.0)] {
            let rc = apply(edge, 0, 0, 999, height) // width proposal ignored for vertical/corner edges
            let h = rc.bottom - rc.top
            let w = rc.right - rc.left
            XCTAssertEqual(h, height)
            XCTAssertEqual(w, widthFor(h))
        }
    }
}
