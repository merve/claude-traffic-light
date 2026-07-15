import AppKit
import QuartzCore
import ClaudeStatusCore

/// Owns the floating widget window: a persistent desktop panel showing live Claude Code
/// sessions. Reuses `StatusStore` + the same `~/.claude/status` contract as the menu-bar
/// app, but is a standalone, draggable, pinnable panel. Read-only viewer + click-to-jump —
/// it never writes hooks/settings, so it runs alongside the menu-bar app without affecting
/// it. Mirrors the Windows port's `WidgetForm`.
final class WidgetController: NSObject, NSWindowDelegate {

    // Spacing system (8px rhythm) — mirrors `WidgetLayout` (the tested, pure geometry) exactly.
    private let W = WidgetSessionRowView.width // 300 (list column)
    private let railW = CGFloat(WidgetLayout.railW)            // left traffic-light rail
    private let pad = CGFloat(WidgetLayout.pad)                // outer padding (top / bottom)
    private let titleH = CGFloat(WidgetLayout.titleH)
    private var dividerY: CGFloat { CGFloat(WidgetLayout.dividerY) }
    private var contentTop: CGFloat { CGFloat(WidgetLayout.contentTop) }

    private(set) var window: WidgetWindow!
    private var theme: WidgetTheme
    private let content: WidgetContentView
    private let titleBar: WidgetTitleBarView
    private let light: VerticalTrafficLightView
    private let emptyLabel = NSTextField(labelWithString: "")
    private var rows: [WidgetSessionRowView] = []

    private let store = StatusStore()
    private var pollTimer: Timer?
    private var animTimer: Timer?
    private var animationPhase: CGFloat = 0

    private var sessions: [SessionStatus] = []
    private var aggregate: State?
    private var sig = "\0"
    private var expanded: Bool
    private var positionRestored = false

    private lazy var relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: L10n.current.localeID)
        f.unitsStyle = .short
        return f
    }()

    override init() {
        expanded = WidgetSettings.listExpanded
        theme = WidgetTheme.current(for: NSApp.effectiveAppearance)
        content = WidgetContentView(theme: theme)
        titleBar = WidgetTitleBarView(theme: theme, pinned: WidgetSettings.pinned)
        light = VerticalTrafficLightView(theme: theme)
        super.init()

        window = WidgetWindow()
        window.delegate = self
        window.level = WidgetSettings.pinned ? .floating : .normal
        window.contentView = content

        style(emptyLabel, .systemFont(ofSize: 12, weight: .regular).withItalicTrait(), theme.subText, align: .center)
        emptyLabel.isHidden = true
        content.addSubview(emptyLabel)

        titleBar.onClose = { [weak self] in self?.window.orderOut(nil) }
        titleBar.onPinToggled = { [weak self] pinned in
            guard let self else { return }
            WidgetSettings.pinned = pinned
            self.window.level = pinned ? .floating : .normal
        }
        titleBar.onToggleList = { [weak self] in self?.setExpanded(!(self?.expanded ?? true)) }
        content.addSubview(titleBar)

        light.onToggle = { [weak self] in self?.setExpanded(!(self?.expanded ?? true)) }
        content.addSubview(light)

        content.menuProvider = { [weak self] in self?.buildContextMenu() ?? NSMenu() }

        poll()
        restorePosition()
        window.orderFrontRegardless()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in self?.animate() }
        RunLoop.main.add(pollTimer!, forMode: .common)
        RunLoop.main.add(animTimer!, forMode: .common)
    }

    private func style(_ l: NSTextField, _ font: NSFont, _ color: NSColor, align: NSTextAlignment) {
        l.font = font; l.textColor = color; l.alignment = align
        l.drawsBackground = false; l.isBezeled = false; l.isEditable = false
        l.cell?.usesSingleLineMode = true
    }

    // MARK: - Position / sizing

    private func restorePosition() {
        guard !positionRestored else { return }
        positionRestored = true
        let primary = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let p = WidgetSettings.position {
            let scr = (NSScreen.screens.first { $0.frame.contains(p) })?.visibleFrame ?? primary
            let x = min(max(p.x, scr.minX), scr.maxX - window.frame.width)
            let y = min(max(p.y, scr.minY), scr.maxY - window.frame.height)
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.setFrameOrigin(NSPoint(x: primary.maxX - window.frame.width - 24, y: primary.minY + 24))
        }
    }

    private func clampToScreen() {
        let scr = (NSScreen.screens.first { $0.frame.intersects(window.frame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? window.frame
        var origin = window.frame.origin
        origin.x = min(max(origin.x, scr.minX), scr.maxX - window.frame.width)
        origin.y = min(max(origin.y, scr.minY), scr.maxY - window.frame.height)
        if origin != window.frame.origin { window.setFrameOrigin(origin) }
    }

    /// Resizes the window while keeping its visual top-left corner fixed (matches WinForms'
    /// `ClientSize` setter, which preserves `Location`).
    private func applyWindowSize(width: CGFloat, height: CGFloat) {
        let old = window.frame
        let r = WidgetWindowResize.preservingTopLeft(
            oldOriginX: Double(old.origin.x), oldOriginY: Double(old.origin.y), oldHeight: Double(old.height),
            newWidth: Double(width), newHeight: Double(height))
        window.setFrame(NSRect(x: r.x, y: r.y, width: r.width, height: r.height), display: true)
        if positionRestored { clampToScreen() }
    }

    // MARK: - Polling / animation

    private func poll() {
        sessions = store.load()
        aggregate = sessions.isEmpty ? nil : store.aggregate(sessions)
        light.setState(aggregate)

        let newSig = sessions.map { "\($0.sessionID):\($0.state.rawValue)" }.joined(separator: "|")
        if newSig != sig {
            sig = newSig
            rebuild()
        } else {
            // Structure unchanged — just refresh row text so relative times tick live.
            for (row, s) in zip(rows, sessions) {
                row.configure(session: s, detail: detail(for: s), platform: PlatformLabel.label(s.platform))
            }
        }
    }

    private func animate() {
        guard aggregate == .red || aggregate == .yellow else { return }
        animationPhase += (1.0 / 15.0) / 1.2
        if animationPhase > 1 { animationPhase -= 1 }
        light.setPhase(animationPhase)
    }

    private func detail(for s: SessionStatus) -> String {
        let l = L10n.current
        switch s.state {
        case .yellow:
            return l.label(for: s.state)
        case .red, .green:
            let ago = relativeFormatter.localizedString(for: s.ts, relativeTo: Date())
            return "\(l.label(for: s.state)) · \(ago)"
        }
    }

    // MARK: - Layout

    private func rebuild() {
        for r in rows { r.removeFromSuperview() }
        rows.removeAll()

        // Layer-backed subviews (content, light) implicitly animate frame/bounds changes;
        // without disabling that, resizing here would visibly slide/interpolate rather than
        // snap, which read as the widget "jumping" for a moment.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let count = sessions.count

        let totalW: CGFloat, totalH: CGFloat
        if expanded {
            let size = WidgetLayout.expandedSize(sessionCount: count)
            (totalW, totalH) = (CGFloat(size.width), CGFloat(size.height))
        } else {
            let size = WidgetLayout.collapsedSize(height: Double(WidgetSettings.collapsedHeight))
            (totalW, totalH) = (CGFloat(size.width), CGFloat(size.height))
        }

        // Resize the window (and hence the content view) to its FINAL size first, then
        // place subviews against that final size. Doing it the other way around — placing
        // `light` at its small collapsed frame while the content view was still its old,
        // much larger expanded size — made the autoresizing-mask math (needed for live
        // collapsed-resize drags) recompute `light`'s frame against the stale parent bounds,
        // producing a wildly wrong transient frame (the reported "jumps to the top-left").
        applyWindowSize(width: totalW, height: totalH)

        if expanded {
            light.fill = false
            light.resizable = false
            light.autoresizingMask = []
            titleBar.isHidden = false
            titleBar.frame = NSRect(x: 0, y: pad, width: railW + W, height: titleH)

            let layout = WidgetLayout.rowsLayout(sessionCount: count, totalHeight: Double(totalH))
            let contentH = CGFloat(layout.contentHeight)
            let rowsTop = CGFloat(layout.rowsTop)
            let listH = CGFloat(WidgetLayout.listHeight(sessionCount: count))

            if count == 0 {
                emptyLabel.stringValue = L10n.current.noSessions
                emptyLabel.frame = NSRect(x: railW, y: rowsTop, width: W, height: listH)
                emptyLabel.isHidden = false
            } else {
                emptyLabel.isHidden = true
                var y = rowsTop
                for s in sessions {
                    let row = WidgetSessionRowView(theme: theme)
                    row.configure(session: s, detail: detail(for: s), platform: PlatformLabel.label(s.platform))
                    row.frame = NSRect(x: railW, y: y, width: WidgetSessionRowView.width, height: WidgetSessionRowView.height)
                    row.onClicked = { [weak self] in self?.route(s) }
                    row.onClose = { [weak self] pid in self?.endSession(pid: pid) }
                    content.addSubview(row)
                    rows.append(row)
                    y += WidgetSessionRowView.height
                }
            }

            light.frame = NSRect(x: 0, y: contentTop, width: railW, height: contentH)
            content.expanded = true
            content.dividerY = dividerY
        } else {
            // Collapsed: the traffic light fills the widget — no side/edge gap, resizable.
            titleBar.isHidden = true
            emptyLabel.isHidden = true
            light.fill = true
            light.resizable = true
            light.frame = NSRect(x: 0, y: 0, width: totalW, height: totalH)
            light.autoresizingMask = [.width, .height] // live-follows the window during drag-resize
            content.expanded = false
        }

        content.needsDisplay = true
    }

    private func setExpanded(_ v: Bool) {
        guard v != expanded else { return }
        expanded = v
        WidgetSettings.listExpanded = v
        rebuild()
    }

    // MARK: - Actions

    private func route(_ s: SessionStatus) {
        switch SessionRouter.action(platform: s.platform, appPath: s.appPath, cwd: s.cwd, sessionID: s.sessionID,
                                    isValidBundle: Self.isValidBundle) {
        case .desktopDeepLink(let id):
            openChatInDesktop(sessionID: id)
        case .activateApp(let path):
            if !activateApp(path, pid: s.pid) { openChatInDesktop(sessionID: s.sessionID) }
        case .openInEditor(let app, let folder):
            openInApp(app, folder: folder)
        }
    }

    private func endSession(pid: Int32) {
        guard pid > 0 else { return }
        kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if StatusStore.isProcessAlive(pid) {
                // Some CLIs (esp. interactive/terminal-hosted ones) don't exit on SIGTERM;
                // force it so the ✕ button reliably ends the session either way.
                kill(pid, SIGKILL)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.poll() }
            } else {
                self.poll()
            }
        }
    }

    // TWIN FILE (C6): the executor block below (activateApp / focusTerminalSession /
    // openChatInDesktop / openInApp / openProjectFolder) is intentionally duplicated in
    // ClaudeStatus/AppDelegate.swift — SwiftPM can't share one source file between two
    // targets. Any change here MUST be mirrored there (and vice versa); the pure decision
    // logic itself lives in ClaudeStatusCore and is not duplicated.

    /// Activating an app by path alone just raises whichever window macOS last used for it —
    /// wrong when several Claude sessions run in separate windows/tabs of the same terminal
    /// app. For scriptable terminals (Terminal.app, iTerm2) we instead find the specific tab
    /// running `pid` (matched by tty) and select it; anything else (or if that lookup fails)
    /// falls back to plain activation.
    @discardableResult
    private func activateApp(_ path: String, pid: Int32) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        if focusTerminalSession(appPath: path, pid: pid) { return true }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: cfg, completionHandler: nil)
        return true
    }

    private func focusTerminalSession(appPath: String, pid: Int32) -> Bool {
        guard pid > 0, let tty = TTYDevice.device(forPid: pid),
              let source = TerminalFocus.script(appPath: appPath, ttyDevice: tty),
              let appleScript = NSAppleScript(source: source) else { return false }
        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("focusTerminalSession: AppleScript error: \(errorInfo)")
            return false
        }
        return result.booleanValue
    }

    private func openChatInDesktop(sessionID: String) {
        guard let url = URL(string: "claude://resume?session=\(sessionID)") else { return }
        // No handler for claude:// (desktop app not installed) → audible feedback
        // instead of a silent no-op (the widget has no notification pipeline).
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Prefers the editor's URL scheme (vscode://file/…) over a file-URL open: the
    /// file route makes TCC ask "access files in your Desktop folder" — repeatedly,
    /// since an ad-hoc signed app loses its grants on every update.
    private func openInApp(_ appPath: String, folder: String) {
        if let link = SessionRouter.editorDeepLink(appPath: appPath, folder: folder),
           NSWorkspace.shared.urlForApplication(toOpen: link) != nil {
            NSWorkspace.shared.open(link)
            return
        }
        guard FileManager.default.fileExists(atPath: appPath), !folder.isEmpty else {
            openProjectFolder(folder)
            return
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: URL(fileURLWithPath: appPath),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    private func openProjectFolder(_ path: String) {
        guard !path.isEmpty else { return }
        let folder = URL(fileURLWithPath: path)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for appPath in SessionRouter.editorCandidates(home: home)
        where FileManager.default.fileExists(atPath: appPath) {
            NSWorkspace.shared.open([folder], withApplicationAt: URL(fileURLWithPath: appPath),
                                    configuration: NSWorkspace.OpenConfiguration())
            return
        }
        NSWorkspace.shared.open(folder)
    }

    /// F10 — confirms a `.app`-suffixed path segment from `SessionRouter.mainAppBundle`
    /// is an actual bundle (has an Info.plist), not just a folder that happens to be
    /// named "*.app" sitting above the real one.
    private static func isValidBundle(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/Contents/Info.plist")
    }

    // MARK: - Context menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        let showList = NSMenuItem(title: "Show list", action: #selector(toggleShowList), keyEquivalent: "")
        showList.target = self
        showList.state = expanded ? .on : .off
        let pin = NSMenuItem(title: "Always on top", action: #selector(togglePin), keyEquivalent: "")
        pin.target = self
        pin.state = WidgetSettings.pinned ? .on : .off
        let auto = NSMenuItem(title: "Open at Login", action: #selector(toggleAutostart), keyEquivalent: "")
        auto.target = self
        auto.state = WidgetSettings.autostart ? .on : .off
        let close = NSMenuItem(title: "Close widget", action: #selector(closeWidget), keyEquivalent: "")
        close.target = self
        menu.addItem(showList)
        menu.addItem(pin)
        menu.addItem(auto)
        menu.addItem(.separator())
        menu.addItem(close)
        return menu
    }

    @objc private func toggleShowList() { setExpanded(!expanded) }

    @objc private func togglePin() {
        let pinned = !WidgetSettings.pinned
        WidgetSettings.pinned = pinned
        window.level = pinned ? .floating : .normal
        titleBar.setPinned(pinned)
    }

    @objc private func toggleAutostart() { WidgetSettings.autostart.toggle() }

    @objc private func closeWidget() { NSApp.terminate(nil) }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard positionRestored else { return }
        WidgetSettings.position = window.frame.origin
    }

    func windowDidResize(_ notification: Notification) {
        guard positionRestored, !expanded else { return }
        WidgetSettings.collapsedHeight = window.frame.height
    }

    func windowDidChangeScreen(_ notification: Notification) {
        if positionRestored { clampToScreen() }
    }
}

private extension NSFont {
    /// Adds an italic trait for the "no sessions" placeholder (matches the menu-bar app's style).
    func withItalicTrait() -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
    }
}
