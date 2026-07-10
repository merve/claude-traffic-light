using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using ClaudeTrafficLight.Core;
using ClaudeTrafficLight.UI;

namespace ClaudeTrafficWidget;

/// <summary>
/// A realistic vertical traffic light drawn as the widget's left rail. Shows the aggregate
/// state (red &gt; yellow &gt; green; dim when idle) with a metallic housing, lens sockets,
/// sun visors, glow and glass gloss. The active lens pulses.
/// </summary>
internal sealed class TrafficLightPanel : Control
{
    private readonly MenuTheme _t;
    private State? _active;
    private double _phase;

    private Point _downPt;
    private bool _dragStarted;

    /// <summary>When true the housing fills the whole control (collapsed widget) with no side gap.</summary>
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public bool Fill { get; set; }

    /// <summary>When true, dragging near an edge/corner resizes the (collapsed) window.</summary>
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    public bool Resizable { get; set; }

    private bool _resizeStarted;
    private const int Edge = 7;

    /// <summary>Raised on a click (not a drag) — used to toggle the list open/closed.</summary>
    public event Action? ToggleRequested;

    private static readonly Color Red = Color.FromArgb(242, 51, 41);
    private static readonly Color Yellow = Color.FromArgb(255, 199, 13);
    private static readonly Color Green = Color.FromArgb(46, 184, 89);

    public TrafficLightPanel(MenuTheme t)
    {
        _t = t;
        DoubleBuffered = true;
        Cursor = Cursors.Hand; // clickable → toggles the list
        // ResizeRedraw → full repaint each resize step (prevents ghosting/duplication).
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint
                 | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
    }

    public void SetState(State? active)
    {
        if (_active == active) return;
        _active = active;
        Invalidate();
    }

    public void SetPhase(double phase)
    {
        _phase = phase;
        if (_active is State.Red or State.Yellow) Invalidate();
    }

    private static Color ColorFor(State s) => s switch
    {
        State.Red => Red,
        State.Yellow => Yellow,
        _ => Green
    };

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(_t.Background);

        // --- Housing geometry ---
        float marginY, gapY, lensD, housingW, housingH, hx, hy, corner;
        if (Fill)
        {
            // Housing fills the whole control (collapsed: the light IS the widget, no side gap).
            housingW = Width;
            housingH = Height;
            hx = 0; hy = 0;
            marginY = housingH * 0.07f;
            float inner = housingH - 2 * marginY;
            lensD = inner / 3.4f;
            gapY = (inner - 3 * lensD) / 2f;
            corner = housingW * 0.30f;
        }
        else
        {
            // Rail mode: housing scales to height (capped) and is centered.
            float maxH = Math.Min(Height - 20, 150);
            if (maxH < 40) return;
            marginY = maxH * 0.08f;
            float inner = maxH - 2 * marginY;
            gapY = inner * 0.055f;
            lensD = (inner - 2 * gapY) / 3f;
            float sideMargin = lensD * 0.34f;
            housingW = lensD + 2 * sideMargin;
            housingH = maxH;
            hx = (Width - 1 - housingW) / 2f;
            hy = (Height - housingH) / 2f;
            corner = lensD * 0.42f;
        }
        float cx = hx + housingW / 2f;

        // --- Housing: metallic vertical gradient + soft outline ---
        var housingRect = new RectangleF(hx, hy, housingW, housingH);
        if (Fill)
        {
            // Collapsed: the housing IS the window. Fill it edge-to-edge (fully opaque) so no
            // theme background shows in the corners — the DWM compositor rounds the window
            // smoothly, so no hard/jagged shape is needed here.
            using (var grad = new LinearGradientBrush(
                new PointF(hx, hy), new PointF(hx, hy + housingH),
                Color.FromArgb(60, 60, 63), Color.FromArgb(18, 18, 20)))
                g.FillRectangle(grad, housingRect);
            using (var spec = new LinearGradientBrush(
                new PointF(hx, hy), new PointF(hx + housingW, hy),
                Color.FromArgb(40, 255, 255, 255), Color.FromArgb(0, 255, 255, 255)))
                g.FillRectangle(spec, hx, hy, housingW * 0.55f, housingH);
        }
        else using (var path = Rounded(housingRect, corner))
        {
            using (var grad = new LinearGradientBrush(
                new PointF(hx, hy), new PointF(hx, hy + housingH),
                Color.FromArgb(60, 60, 63), Color.FromArgb(18, 18, 20)))
                g.FillPath(grad, path);

            // Metallic sheen: soft vertical highlight on the left, clipped to the body.
            g.SetClip(path);
            using (var spec = new LinearGradientBrush(
                new PointF(hx, hy), new PointF(hx + housingW, hy),
                Color.FromArgb(40, 255, 255, 255), Color.FromArgb(0, 255, 255, 255)))
                g.FillRectangle(spec, hx, hy, housingW * 0.55f, housingH);
            g.ResetClip();

            using (var hl = new Pen(Color.FromArgb(70, 255, 255, 255), 1f))
                g.DrawArc(hl, hx + 1, hy + 1, 2 * corner, 2 * corner, 180, 90);
            using (var outline = new Pen(Color.FromArgb(140, 0, 0, 0), 1.4f))
                g.DrawPath(outline, path);
        }

        // --- Three lenses (red top, yellow mid, green bottom) ---
        float firstCy = hy + marginY + lensD / 2f;
        float step = lensD + gapY;
        State[] order = { State.Red, State.Yellow, State.Green };
        double pulse = Pulse();
        for (int i = 0; i < 3; i++)
        {
            float cy = firstCy + i * step;
            bool on = _active.HasValue && _active.Value == order[i];
            DrawLens(g, cx, cy, lensD / 2f, ColorFor(order[i]), on, pulse);
        }
    }

    private double Pulse()
    {
        bool animate = _active is State.Red or State.Yellow;
        return animate ? 0.72 + 0.28 * (0.5 - 0.5 * Math.Cos(_phase * 2 * Math.PI)) : 1.0;
    }

    private static void DrawLens(Graphics g, float cx, float cy, float r, Color color, bool on, double pulse)
    {
        // Socket: dark inset ring giving depth.
        float sr = r * 1.16f;
        using (var socket = new SolidBrush(Color.FromArgb(255, 12, 12, 13)))
            g.FillEllipse(socket, cx - sr, cy - sr, 2 * sr, 2 * sr);
        using (var socketEdge = new Pen(Color.FromArgb(90, 0, 0, 0), 1f))
            g.DrawEllipse(socketEdge, cx - sr, cy - sr, 2 * sr, 2 * sr);

        var rect = new RectangleF(cx - r, cy - r, 2 * r, 2 * r);

        if (on)
        {
            // Outer glow (kept tight so it doesn't bleed into neighbours).
            float glowR = r * 1.7f;
            using (var halo = new GraphicsPath())
            {
                halo.AddEllipse(cx - glowR, cy - glowR, 2 * glowR, 2 * glowR);
                using var pgb = new PathGradientBrush(halo)
                {
                    CenterPoint = new PointF(cx, cy),
                    CenterColor = Color.FromArgb((int)(130 * pulse), color),
                    SurroundColors = new[] { Color.FromArgb(0, color) }
                };
                g.FillEllipse(pgb, cx - glowR, cy - glowR, 2 * glowR, 2 * glowR);
            }
            // Bulb: radial bright center → saturated edge.
            using (var bulb = new GraphicsPath())
            {
                bulb.AddEllipse(rect);
                using var rgb = new PathGradientBrush(bulb)
                {
                    CenterPoint = new PointF(cx - r * 0.2f, cy - r * 0.25f),
                    CenterColor = Blend(color, Color.White, 0.55 * pulse),
                    SurroundColors = new[] { color }
                };
                g.FillEllipse(rgb, rect);
            }
            // Bottom inner shading for a spherical feel (clipped to the bulb).
            using (var shade = new LinearGradientBrush(
                new PointF(cx, cy), new PointF(cx, cy + r),
                Color.FromArgb(0, 0, 0, 0), Color.FromArgb(70, 0, 0, 0)))
            using (var bulbClip = EllipseRegion(rect))
            {
                g.Clip = bulbClip;
                g.FillRectangle(shade, cx - r, cy, 2 * r, r);
                g.ResetClip();
            }
            // Specular glass highlight (top-left).
            using (var glossPath = new GraphicsPath())
            {
                var gr = new RectangleF(cx - r * 0.55f, cy - r * 0.72f, r * 0.9f, r * 0.6f);
                glossPath.AddEllipse(gr);
                using var gloss = new SolidBrush(Color.FromArgb((int)(150 * pulse), 255, 255, 255));
                g.FillPath(gloss, glossPath);
            }
        }
        else
        {
            // Unlit colored bulb: dark, faintly tinted, with a faint top glass sheen.
            using (var dark = new SolidBrush(Blend(color, Color.FromArgb(16, 16, 18), 0.82)))
                g.FillEllipse(dark, rect);
            using (var sheen = new GraphicsPath())
            {
                var gr = new RectangleF(cx - r * 0.5f, cy - r * 0.65f, r * 0.8f, r * 0.45f);
                sheen.AddEllipse(gr);
                using var sb = new SolidBrush(Color.FromArgb(22, 255, 255, 255));
                g.FillPath(sb, sheen);
            }
            using var innerShade = new Pen(Color.FromArgb(70, 0, 0, 0), 1f);
            g.DrawEllipse(innerShade, rect);
        }

        // Sun visor (hood): a filled crescent over the top of the lens + a soft shadow it casts.
        float ro = r * 1.30f, ri = r * 1.04f;
        float vcy = cy - r * 0.14f;
        using (var hood = new GraphicsPath())
        {
            hood.AddArc(cx - ro, vcy - ro, 2 * ro, 2 * ro, 200, 140);
            hood.AddArc(cx - ri, vcy - ri, 2 * ri, 2 * ri, 340, -140);
            hood.CloseFigure();
            using var hb = new SolidBrush(Color.FromArgb(245, 9, 9, 10));
            g.FillPath(hb, hood);
            using var he = new Pen(Color.FromArgb(90, 0, 0, 0), 1f);
            g.DrawPath(he, hood);
        }
        // Shadow the hood casts on the top of the lens.
        using (var castShadow = new GraphicsPath())
        {
            castShadow.AddArc(cx - r, cy - r, 2 * r, 2 * r, 200, 140);
            using var sp = new Pen(Color.FromArgb(60, 0, 0, 0), Math.Max(1.5f, r * 0.22f));
            g.DrawPath(sp, castShadow);
        }
    }

    private static Region EllipseRegion(RectangleF rect)
    {
        using var p = new GraphicsPath(); // dispose the path; Region copies its data
        p.AddEllipse(rect);
        return new Region(p);
    }

    private static Color Blend(Color a, Color b, double t)
    {
        t = Math.Clamp(t, 0, 1);
        return Color.FromArgb(
            (int)(a.R + (b.R - a.R) * t),
            (int)(a.G + (b.G - a.G) * t),
            (int)(a.B + (b.B - a.B) * t));
    }

    private static GraphicsPath Rounded(RectangleF r, float radius)
    {
        radius = Math.Min(radius, Math.Min(r.Width, r.Height) / 2f);
        float d = radius * 2f;
        var p = new GraphicsPath();
        p.AddArc(r.Left, r.Top, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Top, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    /// <summary>Which resize edge/corner the point is on (0 = none). Only when Resizable.</summary>
    private int HitEdge(Point p)
    {
        if (!Resizable) return 0;
        bool l = p.X <= Edge, r = p.X >= Width - Edge, t = p.Y <= Edge, b = p.Y >= Height - Edge;
        if (t && l) return WidgetNative.HTTOPLEFT;
        if (t && r) return WidgetNative.HTTOPRIGHT;
        if (b && l) return WidgetNative.HTBOTTOMLEFT;
        if (b && r) return WidgetNative.HTBOTTOMRIGHT;
        if (l) return WidgetNative.HTLEFT;
        if (r) return WidgetNative.HTRIGHT;
        if (t) return WidgetNative.HTTOP;
        if (b) return WidgetNative.HTBOTTOM;
        return 0;
    }

    private static Cursor CursorFor(int ht) => ht switch
    {
        WidgetNative.HTLEFT or WidgetNative.HTRIGHT => Cursors.SizeWE,
        WidgetNative.HTTOP or WidgetNative.HTBOTTOM => Cursors.SizeNS,
        WidgetNative.HTTOPLEFT or WidgetNative.HTBOTTOMRIGHT => Cursors.SizeNWSE,
        WidgetNative.HTTOPRIGHT or WidgetNative.HTBOTTOMLEFT => Cursors.SizeNESW,
        _ => Cursors.Hand
    };

    // Edge → native resize; center click → toggle; center drag → move window.
    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button != MouseButtons.Left) return;
        _dragStarted = false; _resizeStarted = false;
        int ht = HitEdge(e.Location);
        if (ht != 0)
        {
            _resizeStarted = true;
            if (FindForm() is { } f) WidgetNative.ResizeStart(f.Handle, ht);
            return;
        }
        _downPt = e.Location;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (e.Button == MouseButtons.Left)
        {
            if (_dragStarted || _resizeStarted) return;
            if (Math.Abs(e.X - _downPt.X) > 4 || Math.Abs(e.Y - _downPt.Y) > 4)
            {
                _dragStarted = true;
                if (FindForm() is { } f) WidgetNative.DragMove(f.Handle);
            }
            return;
        }
        // Hover: show a resize cursor near edges, hand cursor otherwise.
        Cursor = CursorFor(HitEdge(e.Location));
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button == MouseButtons.Left && !_dragStarted && !_resizeStarted) ToggleRequested?.Invoke();
    }
}
