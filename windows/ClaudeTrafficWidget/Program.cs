using System.Windows.Forms;

namespace ClaudeTrafficWidget;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();

        var args = Environment.GetCommandLineArgs();
        if (args.Length >= 3 && args[1] == "--capture")
        {
            WidgetPreview.Capture(args[1..]);
            return;
        }

        // Single instance so autostart + a manual launch don't stack two widgets.
        using var mutex = new Mutex(initiallyOwned: true, "ClaudeTrafficWidget_SingleInstance", out bool isNew);
        if (!isNew) return;

        Application.Run(new WidgetForm());
    }
}
