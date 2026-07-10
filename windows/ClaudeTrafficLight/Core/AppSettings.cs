using Microsoft.Win32;

namespace ClaudeTrafficLight.Core;

/// <summary>Persistent user settings in <c>HKCU\Software\ClaudeTrafficLight</c> (§6 / §12.5).</summary>
public static class AppSettings
{
    private const string KeyPath = @"Software\ClaudeTrafficLight";
    private const string NotificationsValue = "NotificationsEnabled";

    public static bool NotificationsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
                var v = key?.GetValue(NotificationsValue);
                return v is null || Convert.ToInt32(v) != 0; // default ON
            }
            catch { return true; }
        }
        set
        {
            try
            {
                using var key = Registry.CurrentUser.CreateSubKey(KeyPath);
                key?.SetValue(NotificationsValue, value ? 1 : 0, RegistryValueKind.DWord);
            }
            catch { /* non-fatal */ }
        }
    }
}
