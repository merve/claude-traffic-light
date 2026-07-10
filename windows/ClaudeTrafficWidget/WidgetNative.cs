using System.Runtime.InteropServices;

namespace ClaudeTrafficWidget;

/// <summary>Minimal P/Invoke for click-drag moving of the borderless widget window.</summary>
internal static class WidgetNative
{
    internal const int WM_NCLBUTTONDOWN = 0x00A1;
    internal const int WM_SIZING = 0x0214;
    internal const int HTCAPTION = 0x0002;

    // Resize hit-test codes.
    internal const int HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13,
                       HTTOPRIGHT = 14, HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17;

    [StructLayout(LayoutKind.Sequential)]
    internal struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    internal static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    // DWM corner rounding (Windows 11+). Unlike SetWindowRgn — which is a hard 1-bit mask
    // that leaves jagged, aliased corners with the desktop showing through the staircase —
    // the compositor rounds the corners smoothly (anti-aliased) and follows live resizes.
    private const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
    private const int DWMWCP_ROUND = 2;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hWnd, int attr, ref int value, int size);

    /// <summary>Ask the DWM compositor to round the window's corners (no-op before Win11).</summary>
    internal static void EnableRoundedCorners(IntPtr hWnd)
    {
        int pref = DWMWCP_ROUND;
        try { DwmSetWindowAttribute(hWnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref pref, sizeof(int)); }
        catch { /* older Windows: corners stay square — harmless */ }
    }

    /// <summary>Start a window drag as if the title bar was grabbed.</summary>
    internal static void DragMove(IntPtr hWnd)
    {
        ReleaseCapture();
        SendMessage(hWnd, WM_NCLBUTTONDOWN, HTCAPTION, IntPtr.Zero);
    }

    /// <summary>Start a native window resize from the given hit-test edge/corner.</summary>
    internal static void ResizeStart(IntPtr hWnd, int htCode)
    {
        ReleaseCapture();
        SendMessage(hWnd, WM_NCLBUTTONDOWN, (IntPtr)htCode, IntPtr.Zero);
    }
}
