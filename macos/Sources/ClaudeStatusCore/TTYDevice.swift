import Foundation

/// Parses `ps -o tty=` output into the `/dev/...` path Terminal.app/iTerm2 report for their
/// tabs/sessions — the only reliable way to tell WHICH window is running a given session's
/// process, since activating an app by path alone just raises whatever window macOS last
/// used (wrong when several Claude sessions run in separate windows of the same terminal app).
public enum TTYDevice {
    /// - Parameter psOutput: raw stdout of `ps -o tty= -p <pid>` (e.g. `"ttys000"`, or `"??"`
    ///   when the process has no controlling terminal, e.g. a detached/background process).
    /// - Returns: `"/dev/ttys000"`, or `nil` if there's no real tty to match against.
    public static func parse(psOutput: String) -> String? {
        let trimmed = psOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "??" else { return nil }
        return trimmed.hasPrefix("/dev/") ? trimmed : "/dev/" + trimmed
    }

    /// Runs `ps -o tty= -p <pid>` and parses the result. Foundation-only (no AppKit), so
    /// it's shared between the tray app and the widget (they were previously identical
    /// private copies in `AppDelegate` and `WidgetController`).
    public static func device(forPid pid: Int32) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let out = String(data: data, encoding: .utf8) else { return nil }
            return parse(psOutput: out)
        } catch {
            return nil
        }
    }
}
