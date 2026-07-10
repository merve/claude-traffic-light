using System.Drawing;
using Microsoft.Win32;

namespace ClaudeTrafficWidget;

/// <summary>Widget preferences in <c>HKCU\Software\ClaudeTrafficWidget</c> — separate from the tray app.</summary>
internal static class WidgetSettings
{
    private const string KeyPath = @"Software\ClaudeTrafficWidget";
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValue = "ClaudeTrafficWidget";

    public static bool Pinned
    {
        get => ReadInt("Pinned", 1) != 0;   // default: always-on-top
        set => WriteInt("Pinned", value ? 1 : 0);
    }

    public static bool ListExpanded
    {
        get => ReadInt("ListExpanded", 1) != 0;   // default: list open
        set => WriteInt("ListExpanded", value ? 1 : 0);
    }

    public static int CollapsedHeight
    {
        get => Math.Clamp(ReadInt("CollapsedHeight", 140), 96, 300);
        set => WriteInt("CollapsedHeight", Math.Clamp(value, 96, 300));
    }

    public static Point? Position
    {
        get
        {
            int x = ReadInt("PosX", int.MinValue);
            int y = ReadInt("PosY", int.MinValue);
            return (x == int.MinValue || y == int.MinValue) ? null : new Point(x, y);
        }
        set
        {
            if (value is { } p) { WriteInt("PosX", p.X); WriteInt("PosY", p.Y); }
        }
    }

    public static bool Autostart
    {
        get
        {
            try
            {
                using var k = Registry.CurrentUser.OpenSubKey(RunKeyPath);
                return k?.GetValue(RunValue) is not null;
            }
            catch { return false; }
        }
        set
        {
            try
            {
                if (value)
                {
                    using var k = Registry.CurrentUser.CreateSubKey(RunKeyPath);
                    string exe = Environment.ProcessPath ?? "";
                    if (!string.IsNullOrEmpty(exe)) k?.SetValue(RunValue, $"\"{exe}\"");
                }
                else
                {
                    using var k = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
                    k?.DeleteValue(RunValue, throwOnMissingValue: false);
                }
            }
            catch { /* non-fatal */ }
        }
    }

    private static int ReadInt(string name, int fallback)
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(KeyPath);
            return k?.GetValue(name) is int i ? i : fallback;
        }
        catch { return fallback; }
    }

    private static void WriteInt(string name, int value)
    {
        try
        {
            using var k = Registry.CurrentUser.CreateSubKey(KeyPath);
            k?.SetValue(name, value, RegistryValueKind.DWord);
        }
        catch { /* non-fatal */ }
    }
}
