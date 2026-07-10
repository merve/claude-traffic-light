using ClaudeTrafficLight.Core;
using Xunit;

namespace ClaudeTrafficLight.Tests;

/// <summary>
/// Routing decision behind every click in the tray bar and the widget — both call
/// <see cref="SessionRouter.Action"/>. Windows adaptation of the macOS SessionRouterTests.
/// </summary>
public class SessionRouterTests
{
    private static OpenAction Act(string platform, int pid = 0, string cwd = "/proj", string id = "s1")
        => SessionRouter.Action(platform, pid, cwd, id);

    [Fact]
    public void VSCode_opens_the_folder_in_VS_Code()
        => Assert.Equal(new OpenAction.OpenInEditor("code", "/work/app"), Act("vscode", cwd: "/work/app"));

    [Fact]
    public void Cursor_opens_the_folder_in_Cursor()
        => Assert.Equal(new OpenAction.OpenInEditor("cursor", "/work/app"), Act("cursor", cwd: "/work/app"));

    [Fact]
    public void Desktop_uses_the_deep_link()
        => Assert.Equal(new OpenAction.DesktopDeepLink("abc"), Act("desktop", id: "abc"));

    // THE BUG this project hit: a terminal session must bring its OWN window to the
    // front (FocusProcessWindow) — never open VS Code or the Claude desktop deep link.
    [Fact]
    public void Terminal_with_a_pid_focuses_its_window()
        => Assert.Equal(new OpenAction.FocusProcessWindow(4321, "/work/app"),
                        Act("terminal", pid: 4321, cwd: "/work/app"));

    [Fact]
    public void Terminal_with_a_pid_is_not_routed_to_an_editor_or_the_desktop()
    {
        var a = Act("terminal", pid: 4321, cwd: "/work/app", id: "xyz");
        Assert.IsType<OpenAction.FocusProcessWindow>(a);
        Assert.NotEqual((OpenAction)new OpenAction.OpenInEditor("code", "/work/app"), a);
        Assert.NotEqual((OpenAction)new OpenAction.DesktopDeepLink("xyz"), a);
    }

    [Fact]
    public void Terminal_without_a_pid_falls_back_to_the_deep_link()
        => Assert.Equal(new OpenAction.DesktopDeepLink("s9"), Act("terminal", pid: 0, id: "s9"));

    [Fact]
    public void Unknown_with_a_pid_focuses_its_window()
        => Assert.Equal(new OpenAction.FocusProcessWindow(777, "/proj"), Act("unknown", pid: 777));

    [Fact]
    public void Unknown_without_a_pid_falls_back_to_the_deep_link()
        => Assert.Equal(new OpenAction.DesktopDeepLink("s0"), Act("unknown", pid: 0, id: "s0"));
}
