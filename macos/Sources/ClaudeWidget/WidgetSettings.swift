import Foundation
import AppKit

/// Widget preferences, persisted in this app's own `UserDefaults` domain — separate from
/// the menu-bar app's, so the two run independently (mirrors the Windows port's
/// `HKCU\Software\ClaudeTrafficWidget`, distinct from the tray app's key).
enum WidgetSettings {
    static let bundleID = "com.mervepro.claudewidget"

    private static let d = UserDefaults.standard

    static var pinned: Bool {
        get { d.object(forKey: "pinned") as? Bool ?? true } // default: always-on-top
        set { d.set(newValue, forKey: "pinned") }
    }

    static var listExpanded: Bool {
        get { d.object(forKey: "listExpanded") as? Bool ?? true } // default: list open
        set { d.set(newValue, forKey: "listExpanded") }
    }

    static var collapsedHeight: CGFloat {
        get {
            let v = d.object(forKey: "collapsedHeight") as? Double ?? 140
            return CGFloat(v).clamped(to: VerticalTrafficLightView.minCollapsedH, VerticalTrafficLightView.maxCollapsedH)
        }
        set {
            d.set(Double(newValue.clamped(to: VerticalTrafficLightView.minCollapsedH, VerticalTrafficLightView.maxCollapsedH)), forKey: "collapsedHeight")
        }
    }

    /// Bottom-left origin, in screen coordinates (AppKit convention) — nil until the user
    /// moves the widget at least once (first launch uses a default bottom-right position).
    static var position: NSPoint? {
        get {
            guard let x = d.object(forKey: "posX") as? Double, let y = d.object(forKey: "posY") as? Double else { return nil }
            return NSPoint(x: x, y: y)
        }
        set {
            guard let p = newValue else { return }
            d.set(Double(p.x), forKey: "posX")
            d.set(Double(p.y), forKey: "posY")
        }
    }

    // MARK: - Autostart (LaunchAgent, mirrors the menu-bar app's Bootstrap)

    private static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(bundleID).plist")
    }

    static var autostart: Bool {
        get { FileManager.default.fileExists(atPath: agentPlistURL.path) }
        set { newValue ? installAutostart() : removeAutostart() }
    }

    private static func installAutostart() {
        guard let binary = Bundle.main.executableURL?.path else { return }
        let agents = agentPlistURL.deletingLastPathComponent()
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
            try contents.write(to: agentPlistURL, atomically: true, encoding: .utf8)
            let load = Process()
            load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            load.arguments = ["load", agentPlistURL.path]
            try? load.run()
        } catch {
            NSLog("WidgetSettings: failed to install LaunchAgent: \(error)")
        }
    }

    private static func removeAutostart() {
        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["unload", agentPlistURL.path]
        try? unload.run()
        try? FileManager.default.removeItem(at: agentPlistURL)
    }
}

private extension CGFloat {
    func clamped(to lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}
