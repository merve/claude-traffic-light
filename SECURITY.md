# Security Policy

Claude Traffic Light is a small, offline status indicator: it makes **no network
calls** and only reads/writes local files under `~/.claude/` (or
`%USERPROFILE%\.claude\` on Windows). That keeps the attack surface small, but a
few areas are still worth reporting on if you find something:

- The **Claude Code hook** (`macos/hooks/claude-status-hook.sh`, or
  `ClaudeTrafficLight.exe --hook` on Windows) — parses JSON from stdin and writes
  status files.
- **Process-ancestry inspection** used for platform detection and click-routing
  (`ps` on macOS, `CreateToolhelp32Snapshot` on Windows).
- The **AppleScript** used to match a session to its Terminal.app tab
  (`TTYDevice.swift` / `AppDelegate.swift`).
- The **`claude://resume?session=<id>` deep link** handling.
- The **install/uninstall scripts** (`install.sh`, `uninstall.sh`, `Bootstrap.cs`),
  which write to `~/.claude/settings.json`, the registry (Windows), and
  autostart/LaunchAgent entries.

## Supported versions

This project doesn't maintain multiple release branches — only the **latest
release** (and the current `main` branch) receive security fixes. Please update
to the latest version before reporting.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security reports.

- Preferred: use GitHub's [private vulnerability
  reporting](https://github.com/merve/claude-traffic-light/security/advisories/new)
  for this repository.
- Alternative: email **xmerveagca@gmail.com** with a description of the issue,
  steps to reproduce, and its potential impact.

I'll acknowledge reports within a few days and aim to ship a fix (or explain why
something isn't a vulnerability) before any public disclosure. Please give me
reasonable time to address the issue before disclosing it publicly.

## Out of scope

- Vulnerabilities that require the attacker to already have arbitrary code
  execution as the local user (the app has no elevated/admin privileges and
  doesn't cross a privilege boundary).
- Issues in third-party dependencies with no reachable code path from this
  project (it has no runtime dependencies beyond the platform SDKs).
