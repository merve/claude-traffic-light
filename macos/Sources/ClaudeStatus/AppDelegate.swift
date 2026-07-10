import AppKit
import UserNotifications
import ClaudeStatusCore

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let store = StatusStore()

    private var refreshTimer: Timer?
    private var animationTimer: Timer?
    private var animationPhase: CGFloat = 0

    // Last read state (so drawing an animation frame doesn't re-read the disk).
    private var sessions: [SessionStatus] = []
    private var activeLight: State? = nil // nil = no sessions (light off)

    // Persistent menu + open-state tracking (for live updates while open and to
    // avoid reassigning statusItem.menu while it is open).
    private let menu = NSMenu()
    private var menuOpen = false
    // Menu session rows (for in-place updates while the menu is open).
    private var sessionItems: [(SessionStatus, NSMenuItem)] = []
    private var headerView: MenuHeaderView?

    // Tracks sessions newly turning red (waiting on you) for notifications.
    private let redTracker = RedTransitionTracker()
    private var notificationsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
    }

    private let l10n = L10n.current

    private lazy var relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: l10n.localeID)
        f.unitsStyle = .short
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First-launch self-setup (hook, settings, status dir, autostart) so a
        // drag-and-drop DMG install works without running install.sh. Idempotent.
        Bootstrap.run()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading

        // Attach the persistent menu once. Its contents are rebuilt right before
        // it opens (via menuNeedsUpdate); statusItem.menu is NEVER reassigned while
        // it is open (that would dismiss/break the open menu).
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        // Request notification permission (to alert on red regardless of platform).
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        refresh() // initial state

        // Poll the disk periodically. `.common` mode is REQUIRED: otherwise the
        // timer won't fire while the menu is open (event-tracking mode) and the
        // light/pulse would freeze.
        let rt = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(rt, forMode: .common)
        refreshTimer = rt

        // Animation frame (pulse). ~15 fps is enough. Also in `.common` mode.
        let at = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in self?.tickAnimation() }
        RunLoop.main.add(at, forMode: .common)
        animationTimer = at
    }

    // MARK: - State reading

    /// Reloads sessions from disk and recomputes the aggregate light.
    private func reload() {
        sessions = store.load()
        activeLight = sessions.isEmpty ? nil : store.aggregate(sessions)
    }

    private func refresh() {
        reload()
        notifyRedTransitions()
        renderIcon()

        // When the menu is closed there's nothing to touch: menuNeedsUpdate rebuilds
        // it fresh right before it opens. When the menu is OPEN, update rows in place
        // (so timestamps tick live) WITHOUT reassigning statusItem.menu, so the open
        // menu isn't dismissed.
        if menuOpen { updateOpenMenu() }
    }

    // MARK: - Notifications (red transition)

    /// Posts a notification for sessions that turned red since the previous scan.
    /// Once per transition — not on every poll. (Tracking logic lives in the
    /// testable `RedTransitionTracker`.)
    private func notifyRedTransitions() {
        let currentRed = Set(sessions.filter { $0.state == .red }.map { $0.sessionID })
        let newlyRed = redTracker.newlyRed(currentRed) // first scan → empty (seed)
        guard notificationsEnabled else { return }
        for id in newlyRed {
            guard let s = sessions.first(where: { $0.sessionID == id }) else { continue }
            postRedNotification(for: s)
        }
    }

    private func postRedNotification(for s: SessionStatus) {
        let content = UNMutableNotificationContent()
        content.title = l10n.notifyTitle
        content.body = "\(s.project) · \(PlatformLabel.label(s.platform))"
        content.sound = .default
        content.userInfo = ["sessionID": s.sessionID, "platform": s.platform,
                            "cwd": s.cwd, "appPath": s.appPath, "pid": s.pid]
        // identifier = session → re-entering red for the same session replaces
        // rather than stacking notifications.
        let req = UNNotificationRequest(identifier: "red-\(s.sessionID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // Clicking a notification opens the corresponding session.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let id = info["sessionID"] as? String {
            let platform = info["platform"] as? String ?? "unknown"
            let cwd = info["cwd"] as? String ?? ""
            let appPath = info["appPath"] as? String ?? ""
            let pid = info["pid"] as? Int32 ?? 0
            // Delegate callbacks aren't guaranteed on the main thread; NSWorkspace
            // must be called on main.
            DispatchQueue.main.async { [weak self] in
                self?.route(sessionID: id, platform: platform, cwd: cwd, appPath: appPath, pid: pid)
            }
        }
        completionHandler()
    }

    // Present the banner even if the app is considered foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    @objc private func toggleNotifications() {
        notificationsEnabled.toggle()
        populateMenu()
    }

    // MARK: - Menu delegate

    // Right before the menu opens: rebuild contents with the freshest data.
    func menuNeedsUpdate(_ menu: NSMenu) {
        reload()
        renderIcon()
        populateMenu()
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    private var shouldAnimate: Bool {
        activeLight == .red || activeLight == .yellow
    }

    private func tickAnimation() {
        guard shouldAnimate else { return }
        animationPhase += 1.0 / 15.0 / 1.2 // ~1.2s cycle
        if animationPhase > 1 { animationPhase -= 1 }
        renderIcon()
    }

    // MARK: - Icon

    private func renderIcon() {
        guard let button = statusItem.button else { return }
        button.image = TrafficLightIcon.image(
            active: activeLight,
            phase: animationPhase,
            animate: shouldAnimate,
            height: NSStatusBar.system.thickness
        )

        // If more than one session is waiting (red), show the count as a badge.
        let waiting = sessions.filter { $0.state == .red }.count
        if waiting > 1 {
            button.title = " \(waiting)"
        } else {
            button.title = ""
        }
    }

    // MARK: - Menu

    /// Rebuilds the persistent `menu` from scratch (statusItem.menu is NOT
    /// reassigned). Keeps references to session rows for in-place updates while open.
    private func populateMenu() {
        menu.removeAllItems()
        sessionItems.removeAll()

        // Styled header (matches the website popover): title + colored count summary.
        let hView = MenuHeaderView()
        if sessions.isEmpty {
            hView.configure(title: l10n.noSessions, summary: NSAttributedString(string: ""))
        } else {
            hView.configure(title: l10n.activeSessions, summary: summaryAttributed())
        }
        let header = NSMenuItem()
        header.view = hView
        header.isEnabled = false
        menu.addItem(header)
        headerView = hView

        if !sessions.isEmpty {
            menu.addItem(.separator())
            for s in sessions {
                let row = SessionRowView()
                row.configure(project: s.project, detail: detail(for: s), state: s.state,
                              platform: PlatformLabel.label(s.platform), showPlatform: true, pid: s.pid)
                row.onClose = { [weak self] pid, name in self?.endSession(pid: pid, name: name) }
                let item = NSMenuItem()
                item.view = row
                item.target = self
                item.action = #selector(openSession(_:))
                item.representedObject = s // open the session on click
                menu.addItem(item)
                sessionItems.append((s, item))
            }

            // Quiet footer hint.
            let hintItem = NSMenuItem()
            let hintView = MenuHintView()
            hintView.configure(l10n.hint)
            hintItem.view = hintView
            hintItem.isEnabled = false
            menu.addItem(hintItem)
        }

        menu.addItem(.separator())

        let notifyItem = NSMenuItem(title: l10n.notifyMenu, action: #selector(toggleNotifications), keyEquivalent: "")
        notifyItem.target = self
        notifyItem.state = notificationsEnabled ? .on : .off
        menu.addItem(notifyItem)

        let refreshItem = NSMenuItem(title: l10n.refresh, action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quit = NSMenuItem(title: l10n.quit, action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Called while the menu is OPEN: if the structure is unchanged, only update
    /// titles (so highlight isn't lost); otherwise do a full rebuild.
    private func updateOpenMenu() {
        let sameStructure = sessionItems.count == sessions.count
            && zip(sessionItems, sessions).allSatisfy { $0.0.sessionID == $1.sessionID }
        guard sameStructure else { populateMenu(); return }

        headerView?.configure(title: l10n.activeSessions, summary: summaryAttributed())
        for (i, s) in sessions.enumerated() {
            let (_, item) = sessionItems[i]
            (item.view as? SessionRowView)?.configure(
                project: s.project, detail: detail(for: s), state: s.state,
                platform: PlatformLabel.label(s.platform), showPlatform: true, pid: s.pid)
            item.representedObject = s
            sessionItems[i] = (s, item)
        }
    }

    /// Colored count summary for the header ("2 waiting · 1 working · 3 done").
    /// Only the "waiting" count is emphasized (red + semibold), like the website.
    private func summaryAttributed() -> NSAttributedString {
        let waiting = sessions.filter { $0.state == .red }.count
        let working = sessions.filter { $0.state == .yellow }.count
        let done = sessions.filter { $0.state == .green }.count

        let result = NSMutableAttributedString()
        let sep = NSAttributedString(string: "  ·  ", attributes: [
            .foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.systemFont(ofSize: 11)])
        func part(_ n: Int, _ word: String, color: NSColor, weight: NSFont.Weight) {
            guard n > 0 else { return }
            if result.length > 0 { result.append(sep) }
            result.append(NSAttributedString(string: "\(n) \(word)", attributes: [
                .foregroundColor: color, .font: NSFont.systemFont(ofSize: 11, weight: weight)]))
        }
        part(waiting, l10n.waitingWord, color: MenuPalette.red, weight: .semibold)
        part(working, l10n.workingWord, color: .secondaryLabelColor, weight: .regular)
        // Show the "done" count only when nothing is waiting/working (keeps the
        // header short and the waiting count prominent when it matters).
        if waiting == 0 && working == 0 {
            part(done, l10n.doneWord, color: .secondaryLabelColor, weight: .regular)
        }
        return result
    }

    private func detail(for s: SessionStatus) -> String {
        switch s.state {
        case .yellow:
            return l10n.label(for: s.state)
        case .red, .green:
            let ago = relativeFormatter.localizedString(for: s.ts, relativeTo: Date())
            return "\(l10n.label(for: s.state)) · \(ago)"
        }
    }

    // MARK: - Actions

    /// Ends a session by sending SIGTERM to its `claude` process. Most exit gracefully; the
    /// status file is then cleaned up on the next reload (its liveness check drops dead
    /// PIDs), so the row disappears from the menu. Some CLIs (esp. interactive/terminal-
    /// hosted ones) don't exit on SIGTERM, so if it's still alive after a beat we escalate
    /// to SIGKILL — the ✕ button should reliably end the session either way.
    private func endSession(pid: Int32, name: String) {
        guard pid > 0 else { return }
        kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if StatusStore.isProcessAlive(pid) {
                kill(pid, SIGKILL)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.refresh() }
            } else {
                self.refresh()
            }
        }
    }

    @objc private func openSession(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? SessionStatus else { return }

        // With Option (⌥) held: always open the project folder in an editor (override).
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            openProjectFolder(s.cwd)
            return
        }

        // Normal click: route by whatever platform the session runs in.
        route(sessionID: s.sessionID, platform: s.platform, cwd: s.cwd, appPath: s.appPath, pid: s.pid)
    }

    /// Opens the session in the right place (shared by menu clicks and notification
    /// clicks). The decision lives in the testable `SessionRouter`; this just executes.
    private func route(sessionID: String, platform: String, cwd: String, appPath: String, pid: Int32) {
        switch SessionRouter.action(platform: platform, appPath: appPath, cwd: cwd, sessionID: sessionID) {
        case .desktopDeepLink(let id):
            openChatInDesktop(sessionID: id)
        case .activateApp(let path):
            // If the hosting app no longer exists on this machine, fall back to the
            // desktop deep link instead of doing nothing.
            if !activateApp(path, pid: pid) { openChatInDesktop(sessionID: sessionID) }
        case .openInEditor(let app, let folder):
            openInApp(app, folder: folder)
        }
    }

    /// Launches/activates a .app (e.g. a terminal). Returns false if the app path
    /// does not exist so the caller can fall back.
    ///
    /// Activating an app by path alone just raises whichever window macOS last used for
    /// it — wrong when several Claude sessions run in separate windows/tabs of the same
    /// terminal app. For Terminal.app we instead find the specific tab running `pid`
    /// (matched by tty) and select it; anything else falls back to plain activation.
    @discardableResult
    private func activateApp(_ path: String, pid: Int32) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        if path.hasSuffix("/Terminal.app"), focusTerminalTab(forPid: pid) { return true }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: cfg, completionHandler: nil)
        return true
    }

    private func focusTerminalTab(forPid pid: Int32) -> Bool {
        guard pid > 0, let tty = ttyDevice(forPid: pid) else { return false }
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set frontmost of w to true
                        set selected of t to true
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("focusTerminalTab: AppleScript error: \(errorInfo)")
            return false
        }
        return result.booleanValue
    }

    private func ttyDevice(forPid pid: Int32) -> String? {
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
            return TTYDevice.parse(psOutput: out)
        } catch {
            return nil
        }
    }

    /// Opens the session in the Claude desktop app (claude://resume deep link).
    private func openChatInDesktop(sessionID: String) {
        guard let url = URL(string: "claude://resume?session=\(sessionID)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens/focuses the project in a specific app (VS Code/Cursor); falls back to
    /// the generic folder opener if that app is missing.
    private func openInApp(_ appPath: String, folder: String) {
        guard FileManager.default.fileExists(atPath: appPath), !folder.isEmpty else {
            openProjectFolder(folder)
            return
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)],
                                withApplicationAt: URL(fileURLWithPath: appPath),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// Opens the project folder in the first installed editor (VS Code → Cursor → Terminal).
    private func openProjectFolder(_ path: String) {
        guard !path.isEmpty else { return }
        let folder = URL(fileURLWithPath: path)
        let editors = ["/Applications/Visual Studio Code.app", "/Applications/Cursor.app"]
        for appPath in editors where FileManager.default.fileExists(atPath: appPath) {
            NSWorkspace.shared.open([folder], withApplicationAt: URL(fileURLWithPath: appPath),
                                    configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([folder], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func refreshNow() {
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
