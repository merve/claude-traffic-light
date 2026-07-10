using System.Drawing;
using System.Drawing.Imaging;
using ClaudeTrafficLight.Core;

namespace ClaudeTrafficLight.UI;

/// <summary>Debug helper: dump the traffic-light icon for a state to a PNG (no tray).</summary>
public static class DebugRender
{
    public static int Run(string[] args)
    {
        State? active = args[1].ToLowerInvariant() switch
        {
            "red" => State.Red,
            "yellow" => State.Yellow,
            "green" => State.Green,
            _ => null // "off" — no session
        };
        string outPath = args[2];
        int size = args.Length >= 4 && int.TryParse(args[3], out var s) ? s : 64;
        int waiting = args.Length >= 5 && int.TryParse(args[4], out var w) ? w : 0;

        double pulse = TrafficLightIcon.Pulse(active, 0.5); // mid-pulse (brightest-ish)
        using var icon = TrafficLightIcon.RenderTrayIcon(active, pulse, waiting, size, out var hicon);
        using (var bmp = icon.ToBitmap())
            bmp.Save(outPath, ImageFormat.Png);
        TrafficLightIcon.DestroyIcon(hicon);
        Console.WriteLine($"wrote {outPath} ({size}px, {args[1]}, waiting={waiting})");
        return 0;
    }
}
