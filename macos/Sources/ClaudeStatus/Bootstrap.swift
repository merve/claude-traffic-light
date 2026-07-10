import Foundation

/// First-launch self-setup so the app works from a drag-and-drop DMG install
/// (no separate install.sh needed). Everything here is idempotent: it only writes
/// when something is actually missing or out of date.
///
/// The hook script and settings snippet are bundled inside the .app's Resources
/// by build-app.sh. When running via `swift run` (no bundled resources) these
/// lookups return nil and bootstrap simply skips — dev uses install.sh instead.
enum Bootstrap {

    private static let bundleID = "com.mervepro.claudelight"

    static func run() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
        ensureStatusDir(claudeDir)
        installHookIfNeeded(claudeDir)
        mergeSettingsIfNeeded(claudeDir)
        installAutostartIfInApplications()
    }

    // MARK: - Steps

    private static func ensureStatusDir(_ claudeDir: URL) {
        let dir = claudeDir.appendingPathComponent("status", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Copies the bundled hook into ~/.claude/hooks/ when missing or changed, and
    /// makes it executable.
    private static func installHookIfNeeded(_ claudeDir: URL) {
        guard let src = Bundle.main.url(forResource: "claude-status-hook", withExtension: "sh"),
              let bundled = try? Data(contentsOf: src) else { return }

        let hooksDir = claudeDir.appendingPathComponent("hooks", isDirectory: true)
        let dst = hooksDir.appendingPathComponent("claude-status-hook.sh")

        let installed = try? Data(contentsOf: dst)
        if installed == bundled, isExecutable(dst) { return } // already up to date

        try? FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        do {
            try bundled.write(to: dst)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst.path)
        } catch {
            NSLog("Bootstrap: failed to install hook: \(error)")
        }
    }

    /// Merges the bundled settings snippet into ~/.claude/settings.json, deduping by
    /// command (same semantics as install.sh). Writes only when something changes,
    /// and backs up the original first.
    private static func mergeSettingsIfNeeded(_ claudeDir: URL) {
        guard let snipURL = Bundle.main.url(forResource: "settings-snippet", withExtension: "json"),
              let snipData = try? Data(contentsOf: snipURL),
              let snippet = try? JSONSerialization.jsonObject(with: snipData) as? [String: Any],
              let snippetHooks = snippet["hooks"] as? [String: Any] else { return }

        let settingsURL = claudeDir.appendingPathComponent("settings.json")
        var settings = (try? Data(contentsOf: settingsURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for (event, value) in snippetHooks {
            guard let groups = value as? [[String: Any]] else { continue }
            var existing = hooks[event] as? [[String: Any]] ?? []
            let present = commands(in: existing)
            for group in groups where commands(in: [group]).isDisjoint(with: present) {
                existing.append(group)
                changed = true
            }
            hooks[event] = existing
        }

        guard changed else { return }
        settings["hooks"] = hooks

        // Back up the original before overwriting.
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("bak.claudelight")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: settingsURL, to: backup)
        } else {
            try? FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        }

        if let out = try? JSONSerialization.data(withJSONObject: settings,
                                                 options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: settingsURL)
        }
    }

    /// Registers launch-at-login only when running from /Applications (so we never
    /// point the LaunchAgent at a DMG mount or a temp path). No-op if already set.
    private static func installAutostartIfInApplications() {
        let appPath = Bundle.main.bundlePath
        guard appPath.hasPrefix("/Applications/"),
              let binary = Bundle.main.executableURL?.path else { return }

        let agents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plist = agents.appendingPathComponent("\(bundleID).plist")
        guard !FileManager.default.fileExists(atPath: plist.path) else { return }

        let contents = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(bundleID)</string>
            <key>ProgramArguments</key>
            <array><string>\(binary)</string></array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """
        do {
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
            try contents.write(to: plist, atomically: true, encoding: .utf8)
            let load = Process()
            load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            load.arguments = ["load", plist.path]
            try? load.run()
        } catch {
            NSLog("Bootstrap: failed to install LaunchAgent: \(error)")
        }
    }

    // MARK: - Helpers

    /// Collects every hook `command` string across the given groups.
    private static func commands(in groups: [[String: Any]]) -> Set<String> {
        var result: Set<String> = []
        for group in groups {
            for hook in (group["hooks"] as? [[String: Any]] ?? []) {
                if let cmd = hook["command"] as? String { result.insert(cmd) }
            }
        }
        return result
    }

    private static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}
