import Foundation

/// State of a single Claude session (traffic-light color).
public enum State: String {
    case red    // asking a question / waiting for permission — waiting on you
    case yellow // working
    case green  // finished, your turn

    /// Priority: higher = needs more attention. Used when aggregating.
    public var priority: Int {
        switch self {
        case .red: return 3
        case .yellow: return 2
        case .green: return 1
        }
    }

    public var emoji: String {
        switch self {
        case .red: return "🔴"
        case .yellow: return "🟡"
        case .green: return "🟢"
        }
    }
}

/// Status record of a single Claude session (maps to one status file).
public struct SessionStatus {
    public let sessionID: String
    public let state: State
    public let project: String
    public let cwd: String
    public let ts: Date
    public let platform: String // "desktop" | "vscode" | "cursor" | "terminal" | "unknown"
    public let appPath: String  // path of the hosting .app (if any) — used to focus it on click
    public let pid: Int32       // the running `claude` process (0 if unknown) — used to end the session

    public init(sessionID: String, state: State, project: String,
                cwd: String, ts: Date, platform: String, appPath: String = "", pid: Int32 = 0) {
        self.sessionID = sessionID
        self.state = state
        self.project = project
        self.cwd = cwd
        self.ts = ts
        self.platform = platform
        self.appPath = appPath
        self.pid = pid
    }
}

/// Reads and aggregates the `~/.claude/status/*.json` files.
public final class StatusStore {

    /// Records older than this are considered stale (stuck session) and hidden.
    public static let staleAfter: TimeInterval = 30 * 60 // 30 min

    public let statusDir: URL

    /// When `statusDir` is nil, `~/.claude/status` is used. Parameterized so tests
    /// can inject a temporary directory.
    public init(statusDir: URL? = nil) {
        if let dir = statusDir {
            self.statusDir = dir
        } else {
            self.statusDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("status", isDirectory: true)
        }
    }

    /// Reads all valid (non-stale) sessions in the directory.
    public func load() -> [SessionStatus] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: statusDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let now = Date()
        var results: [SessionStatus] = []

        for url in entries where url.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: url),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let stateRaw = obj["state"] as? String,
                let state = State(rawValue: stateRaw)
            else { continue }

            let tsNumber = (obj["ts"] as? NSNumber)?.doubleValue
                ?? Double(obj["ts"] as? String ?? "")
                ?? 0
            let ts = Date(timeIntervalSince1970: tsNumber)

            // Liveness: if the session's claude process is gone (chat closed), drop
            // it and delete the now-useless file (keep disk clean).
            let pid = (obj["session_pid"] as? NSNumber)?.int32Value ?? 0
            if pid > 0 {
                if !StatusStore.isProcessAlive(pid) {
                    try? fm.removeItem(at: url)
                    continue
                }
            } else {
                // Old format (no pid) → fall back to time-based staleness check.
                if now.timeIntervalSince(ts) > StatusStore.staleAfter {
                    try? fm.removeItem(at: url)
                    continue
                }
            }

            let cwd = obj["cwd"] as? String ?? ""
            let project = (obj["project"] as? String)
                ?? (cwd.isEmpty ? "?" : (cwd as NSString).lastPathComponent)
            let sessionID = url.deletingPathExtension().lastPathComponent

            let platform = (obj["platform"] as? String) ?? "unknown"
            let appPath = (obj["app_path"] as? String) ?? ""

            results.append(SessionStatus(
                sessionID: sessionID,
                state: state,
                project: project,
                cwd: cwd,
                ts: ts,
                platform: platform,
                appPath: appPath,
                pid: pid
            ))
        }

        // Sort by priority (red on top); ties broken by newest first.
        results.sort { a, b in
            if a.state.priority != b.state.priority {
                return a.state.priority > b.state.priority
            }
            return a.ts > b.ts
        }
        return results
    }

    /// Aggregate state shown on the bar icon. Green (idle) when there are no sessions.
    public func aggregate(_ sessions: [SessionStatus]) -> State {
        sessions.map { $0.state }.max { $0.priority < $1.priority } ?? .green
    }

    /// Checks whether the given PID is alive (POSIX `kill(pid, 0)`).
    public static func isProcessAlive(_ pid: Int32) -> Bool {
        if pid <= 0 { return true }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM // process exists but we lack permission to signal it → alive
    }
}
