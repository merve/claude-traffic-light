namespace ClaudeTrafficWidget;

/// <summary>
/// Pure geometry for the collapsed widget's aspect-locked resize (the <c>WM_SIZING</c> handler).
/// Kept free of WinForms / P-Invoke so the traffic-light proportions, size clamping and edge
/// anchoring are unit-testable. <see cref="WidgetForm"/>'s WndProc feeds it the proposed window
/// rect and the drag edge; it returns the corrected rect.
/// </summary>
internal static class WidgetResize
{
    // WMSZ_* edge codes carried in WM_SIZING's wParam.
    internal const int WMSZ_LEFT = 1, WMSZ_RIGHT = 2, WMSZ_TOP = 3, WMSZ_TOPLEFT = 4,
                       WMSZ_TOPRIGHT = 5, WMSZ_BOTTOM = 6, WMSZ_BOTTOMLEFT = 7, WMSZ_BOTTOMRIGHT = 8;

    /// <summary>
    /// Correct a proposed window rect so it keeps the traffic-light aspect ratio and its height
    /// stays within [<paramref name="minH"/>, <paramref name="maxH"/>]. Dragging a side edge lets
    /// that dimension drive; the opposite side/corner stays anchored so the widget grows toward
    /// the cursor, not away from it.
    /// </summary>
    /// <param name="edge">the WMSZ_* code of the dragged edge/corner.</param>
    /// <param name="aspect">width / height ratio to preserve.</param>
    public static (int Left, int Top, int Right, int Bottom) Apply(
        int edge, int left, int top, int right, int bottom, float aspect, int minH, int maxH)
    {
        int w = right - left, h = bottom - top;

        bool horizontal = edge is WMSZ_LEFT or WMSZ_RIGHT; // a left/right edge → width drives
        if (horizontal)
        {
            w = Math.Clamp(w, (int)Math.Round(minH * aspect), (int)Math.Round(maxH * aspect));
            h = (int)Math.Round(w / aspect);
        }
        else
        {
            h = Math.Clamp(h, minH, maxH);
            w = (int)Math.Round(h * aspect);
        }

        if (edge is WMSZ_LEFT or WMSZ_TOPLEFT or WMSZ_BOTTOMLEFT) left = right - w; else right = left + w;
        if (edge is WMSZ_TOP or WMSZ_TOPLEFT or WMSZ_TOPRIGHT) top = bottom - h; else bottom = top + h;

        return (left, top, right, bottom);
    }
}
