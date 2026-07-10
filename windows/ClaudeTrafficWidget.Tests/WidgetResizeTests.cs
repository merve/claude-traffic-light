using ClaudeTrafficWidget;
using Xunit;

namespace ClaudeTrafficWidget.Tests;

/// <summary>
/// The collapsed widget's aspect-locked resize geometry (WM_SIZING). Verifies that the
/// traffic-light proportions are preserved, the height is clamped to [96, 300], and the edge
/// opposite the drag stays anchored so the widget grows toward the cursor.
/// </summary>
public class WidgetResizeTests
{
    // Same proportions the widget uses: 52 × 140 collapsed.
    private const float Aspect = 52f / 140f;
    private const int MinH = 96;
    private const int MaxH = 300;

    private static (int Left, int Top, int Right, int Bottom) Apply(int edge, int l, int t, int r, int b)
        => WidgetResize.Apply(edge, l, t, r, b, Aspect, MinH, MaxH);

    // Expected width derived from a (clamped) height, matching Apply's rounding.
    private static int WidthFor(int h) => (int)Math.Round(h * Aspect);

    [Fact]
    public void Dragging_a_vertical_edge_derives_width_from_height()
    {
        // BOTTOM drag, height 200 within range → width = round(200 * aspect).
        var rc = Apply(WidgetResize.WMSZ_BOTTOM, 0, 0, 52, 200);
        Assert.Equal(200, rc.Bottom - rc.Top);
        Assert.Equal(WidthFor(200), rc.Right - rc.Left);
    }

    [Fact]
    public void Dragging_bottom_past_the_max_clamps_height_and_keeps_top_left_anchored()
    {
        var rc = Apply(WidgetResize.WMSZ_BOTTOM, 100, 100, 152, 500); // proposes height 400
        Assert.Equal(MaxH, rc.Bottom - rc.Top);          // clamped to 300
        Assert.Equal(WidthFor(MaxH), rc.Right - rc.Left);
        Assert.Equal(100, rc.Left);                      // left anchored
        Assert.Equal(100, rc.Top);                       // top anchored (dragging the bottom)
    }

    [Fact]
    public void Dragging_top_below_the_min_clamps_height_and_keeps_bottom_anchored()
    {
        var rc = Apply(WidgetResize.WMSZ_TOP, 100, 100, 152, 150); // proposes height 50
        Assert.Equal(MinH, rc.Bottom - rc.Top);          // clamped up to 96
        Assert.Equal(150, rc.Bottom);                    // bottom anchored (dragging the top)
        Assert.Equal(150 - MinH, rc.Top);
    }

    [Fact]
    public void Dragging_a_horizontal_edge_derives_height_from_width()
    {
        // RIGHT drag, very wide → width clamps to maxW = round(300 * aspect) = 111.
        var rc = Apply(WidgetResize.WMSZ_RIGHT, 100, 100, 300, 240);
        int maxW = (int)Math.Round(MaxH * Aspect);
        Assert.Equal(maxW, rc.Right - rc.Left);
        Assert.Equal((int)Math.Round(maxW / Aspect), rc.Bottom - rc.Top);
        Assert.Equal(100, rc.Left);                      // left anchored (dragging the right)
        Assert.Equal(100, rc.Top);
    }

    [Fact]
    public void Dragging_left_narrower_than_min_clamps_and_keeps_right_anchored()
    {
        var rc = Apply(WidgetResize.WMSZ_LEFT, 100, 100, 110, 240); // proposes width 10
        int minW = (int)Math.Round(MinH * Aspect);
        Assert.Equal(minW, rc.Right - rc.Left);          // clamped up
        Assert.Equal(110, rc.Right);                     // right anchored (dragging the left)
    }

    [Fact]
    public void Top_left_corner_anchors_the_bottom_right()
    {
        var rc = Apply(WidgetResize.WMSZ_TOPLEFT, 100, 100, 152, 500);
        Assert.Equal(152, rc.Right);                     // bottom-right stays put
        Assert.Equal(500, rc.Bottom);
        Assert.Equal(MaxH, rc.Bottom - rc.Top);
        Assert.Equal(WidthFor(MaxH), rc.Right - rc.Left);
    }

    [Fact]
    public void Bottom_right_corner_anchors_the_top_left()
    {
        var rc = Apply(WidgetResize.WMSZ_BOTTOMRIGHT, 100, 100, 152, 500);
        Assert.Equal(100, rc.Left);                      // top-left stays put
        Assert.Equal(100, rc.Top);
        Assert.Equal(MaxH, rc.Bottom - rc.Top);
        Assert.Equal(WidthFor(MaxH), rc.Right - rc.Left);
    }

    [Theory]
    [InlineData(WidgetResize.WMSZ_BOTTOM, 140)]
    [InlineData(WidgetResize.WMSZ_TOP, 140)]
    [InlineData(WidgetResize.WMSZ_BOTTOMRIGHT, 220)]
    public void Aspect_ratio_is_preserved_within_range(int edge, int height)
    {
        var rc = Apply(edge, 0, 0, 999, height); // width proposal ignored for vertical/corner edges
        int h = rc.Bottom - rc.Top;
        int w = rc.Right - rc.Left;
        Assert.Equal(height, h);                         // height in range → unchanged
        Assert.Equal(WidthFor(h), w);                    // width locked to the aspect ratio
    }
}
