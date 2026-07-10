import XCTest
@testable import ClaudeStatusCore

/// Covers the widget's must-not-break scenarios: every session gets a row (no cap), the
/// window grows/shrinks by exactly one row per session with a sane floor, rows stay
/// vertically centered, the collapsed size stays aspect-locked and clamped, and toggling
/// expanded/collapsed resizes the window without moving its top-left corner (the regression
/// class behind the "widget jumps to the top-left" bug).
final class WidgetLayoutTests: XCTestCase {

    // MARK: - All sessions are listed (no cap)

    func testListHeightGrowsOneRowPerSession() {
        for n in 1...12 {
            XCTAssertEqual(WidgetLayout.listHeight(sessionCount: n), Double(n) * WidgetLayout.rowHeight,
                           "session \(n) should add exactly one row's worth of height")
        }
    }

    func testListHeightHasNoUpperCap() {
        // A large fleet of sessions must still get one row each — nothing truncates the list.
        XCTAssertEqual(WidgetLayout.listHeight(sessionCount: 50), 50 * WidgetLayout.rowHeight)
    }

    func testEmptyStateUsesPlaceholderHeight() {
        XCTAssertEqual(WidgetLayout.listHeight(sessionCount: 0), 44)
    }

    // MARK: - Expanded sizing (open/close must not corrupt geometry)

    func testExpandedWidthIsConstantRegardlessOfSessionCount() {
        for n in 0...10 {
            XCTAssertEqual(WidgetLayout.expandedSize(sessionCount: n).width, WidgetLayout.railW + WidgetLayout.rowWidth)
        }
    }

    func testExpandedHeightGrowsWithEachAdditionalSessionOnceAboveTheFloor() {
        // Once there are enough sessions to exceed the minimum-content floor, each extra
        // session must add exactly one row's height — no clamping, no truncation.
        let h3 = WidgetLayout.expandedSize(sessionCount: 3).height
        let h4 = WidgetLayout.expandedSize(sessionCount: 4).height
        XCTAssertEqual(h4 - h3, WidgetLayout.rowHeight)
    }

    func testExpandedHeightNeverGoesBelowTheMinimumContentFloor() {
        // 0 or 1 sessions would make for a cramped/degenerate window; a floor keeps the
        // light rail looking right regardless of how few sessions are open.
        let floor = WidgetLayout.contentTop + WidgetLayout.minContentH + WidgetLayout.pad
        for n in 0...1 {
            XCTAssertEqual(WidgetLayout.expandedSize(sessionCount: n).height, floor)
        }
    }

    func testExpandedHeightExceedsFloorOnceEnoughSessionsArePresent() {
        // With many sessions the list itself should be taller than the floor (i.e. the
        // floor stops being the binding constraint) — otherwise sessions would silently
        // overlap/clip instead of growing the window.
        let bigCount = 10
        let listH = WidgetLayout.listHeight(sessionCount: bigCount)
        let height = WidgetLayout.expandedSize(sessionCount: bigCount).height
        XCTAssertEqual(height, WidgetLayout.contentTop + listH + WidgetLayout.pad)
        XCTAssertGreaterThan(height, WidgetLayout.contentTop + WidgetLayout.minContentH + WidgetLayout.pad)
    }

    // MARK: - Row positioning (rows must stay visible and centered, never off the top/bottom)

    func testRowsAreVerticallyCenteredWhenAboveTheFloor() {
        let count = 8
        let (_, totalH) = WidgetLayout.expandedSize(sessionCount: count)
        let listH = WidgetLayout.listHeight(sessionCount: count)
        let layout = WidgetLayout.rowsLayout(sessionCount: count, totalHeight: totalH)
        // Centered means equal leftover space above the first row and below the last row.
        let spaceAbove = layout.rowsTop - WidgetLayout.contentTop
        let spaceBelow = (WidgetLayout.contentTop + layout.contentHeight) - (layout.rowsTop + listH)
        XCTAssertEqual(spaceAbove, spaceBelow, accuracy: 0.001)
    }

    func testRowsNeverStartAboveContentTop() {
        // A widget sized exactly to the floor (few/no sessions) must not push rows above
        // the divider — that would draw them under the title bar.
        for n in 0...2 {
            let (_, totalH) = WidgetLayout.expandedSize(sessionCount: n)
            let layout = WidgetLayout.rowsLayout(sessionCount: n, totalHeight: totalH)
            XCTAssertGreaterThanOrEqual(layout.rowsTop, WidgetLayout.contentTop - 0.001)
        }
    }

    func testAllRowsFitWithinTheWindowForALargeFleet() {
        let count = 15
        let (_, totalH) = WidgetLayout.expandedSize(sessionCount: count)
        let listH = WidgetLayout.listHeight(sessionCount: count)
        let layout = WidgetLayout.rowsLayout(sessionCount: count, totalHeight: totalH)
        let lastRowBottom = layout.rowsTop + listH
        XCTAssertLessThanOrEqual(lastRowBottom, totalH - WidgetLayout.pad + 0.001)
    }

    // MARK: - Collapsed (icon) sizing — aspect lock + clamping, no distortion on resize

    func testCollapsedSizeKeepsAspectRatio() {
        for h in stride(from: 96.0, through: 300.0, by: 17.0) {
            let size = WidgetLayout.collapsedSize(height: h)
            XCTAssertEqual(size.width / size.height, WidgetLayout.collapsedAspect, accuracy: 0.01,
                           "icon must not distort/stretch at height \(h)")
        }
    }

    func testCollapsedSizeClampsBelowMinimum() {
        let size = WidgetLayout.collapsedSize(height: 10)
        XCTAssertEqual(size.height, WidgetLayout.minCollapsedH)
    }

    func testCollapsedSizeClampsAboveMaximum() {
        let size = WidgetLayout.collapsedSize(height: 10_000)
        XCTAssertEqual(size.height, WidgetLayout.maxCollapsedH)
    }

    func testCollapsedSizeWidthIsWholeNumberOfPoints() {
        // Sub-pixel widths cause blurry/misaligned rendering of the housing.
        let size = WidgetLayout.collapsedSize(height: 173)
        XCTAssertEqual(size.width, size.width.rounded())
    }

    // MARK: - Expand/collapse must not move the window (regression: "jumps to the top-left")

    func testTogglingSizePreservesTopLeftCorner() {
        // Simulate: widget sitting somewhere on screen, expanded; user collapses it.
        let oldOriginX = 900.0, oldOriginY = 200.0, oldHeight = 225.0
        let (newW, newH) = WidgetLayout.collapsedSize(height: 140)
        let r = WidgetWindowResize.preservingTopLeft(
            oldOriginX: oldOriginX, oldOriginY: oldOriginY, oldHeight: oldHeight, newWidth: newW, newHeight: newH)

        XCTAssertEqual(r.x, oldOriginX, "left edge must not move")
        let oldTopEdge = oldOriginY + oldHeight
        let newTopEdge = r.y + r.height
        XCTAssertEqual(newTopEdge, oldTopEdge, accuracy: 0.001, "top edge must not move")
    }

    func testTogglingBackAndForthReturnsToTheOriginalFrame() {
        // Expand → collapse → expand must land back exactly where it started (no drift).
        let startX = 500.0, startY = 300.0
        let (expandedW, expandedH) = WidgetLayout.expandedSize(sessionCount: 3)

        let toCollapsed = WidgetWindowResize.preservingTopLeft(
            oldOriginX: startX, oldOriginY: startY, oldHeight: expandedH,
            newWidth: WidgetLayout.collapsedSize(height: 140).width, newHeight: 140)

        let backToExpanded = WidgetWindowResize.preservingTopLeft(
            oldOriginX: toCollapsed.x, oldOriginY: toCollapsed.y, oldHeight: toCollapsed.height,
            newWidth: expandedW, newHeight: expandedH)

        XCTAssertEqual(backToExpanded.x, startX, accuracy: 0.001)
        XCTAssertEqual(backToExpanded.y, startY, accuracy: 0.001)
        XCTAssertEqual(backToExpanded.width, expandedW, accuracy: 0.001)
        XCTAssertEqual(backToExpanded.height, expandedH, accuracy: 0.001)
    }

    func testGrowingWindowMovesTopEdgeUpNotDown() {
        // Height increasing (e.g. more sessions arrive while expanded) must extend the
        // window DOWNWARD on screen (origin.y decreases, since AppKit is y-up) while the
        // top edge itself stays put — never grow upward past the top-left anchor.
        let r = WidgetWindowResize.preservingTopLeft(oldOriginX: 0, oldOriginY: 100, oldHeight: 150, newWidth: 376, newHeight: 200)
        XCTAssertLessThan(r.y, 100, "origin.y must decrease so the window extends downward, keeping the top edge fixed")
    }
}
