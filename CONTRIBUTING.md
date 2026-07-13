# Contributing to Claude Traffic Light

Thanks for taking the time to contribute! 🎉 This project is a small, dependency-free
status indicator for Claude Code, with two native implementations that share one
behavior contract.

By participating, you're expected to follow our [Code of
Conduct](CODE_OF_CONDUCT.md). Found a security issue instead of a regular bug?
See [SECURITY.md](SECURITY.md) — please don't open a public issue for those.

## Ground rules

- **Keep both platforms in sync.** The macOS (Swift) and Windows (.NET) apps read the
  same `~/.claude/status/*.json` files and must behave identically. If you change the
  status contract on one side, update the other and
  [`windows/WINDOWS-PORT-SPEC.md`](windows/WINDOWS-PORT-SPEC.md).
- **No new runtime dependencies.** macOS uses only the Swift stdlib + AppKit; Windows
  uses only .NET + WinForms. No network calls, ever.
- **Put logic in the testable core.** Platform-agnostic behavior lives in
  `macos/Sources/ClaudeStatusCore/` and `windows/ClaudeTrafficLight/Core/` and should
  come with tests. The widget's own pure geometry (aspect-locked collapsed resize)
  follows the same rule: `WidgetLayout.swift`/`WidgetResize.swift` (macOS, also under
  `ClaudeStatusCore/`) and `WidgetResize.cs` (Windows, under
  `windows/ClaudeTrafficWidget/`).

## Development

### macOS

```bash
cd macos
swift build            # build (both the menu-bar app and the widget targets)
swift test              # run unit tests
./build-app.sh           # package + ad-hoc sign Claude Traffic Light.app
./build-widget-app.sh    # package + ad-hoc sign Claude Traffic Widget.app
```

### Windows

```powershell
cd windows\ClaudeTrafficLight
dotnet build -c Release
dotnet test ..\ClaudeTrafficLight.Tests    # run unit tests

cd ..\ClaudeTrafficWidget
dotnet build -c Release
dotnet test ..\ClaudeTrafficWidget.Tests   # run widget unit tests
```

## Pull requests

1. Fork and create a branch: `feature/<short-description>` or `bugfix/<short-description>`.
2. Keep PRs small and focused; link the related issue.
3. Make sure tests pass on the platform(s) you touched.
4. Write clear, English commit messages describing **what** and **why**.

## Reporting bugs

Open an [issue](https://github.com/merve/claude-traffic-light/issues) with your OS
version, how you installed, what you expected, and what happened. Screenshots of the
tray/menu-bar icon help a lot.

## Building distributables

Release binaries are **not committed** to the repo (`.dmg` / `.exe` are gitignored) —
they are attached to [GitHub Releases](https://github.com/merve/claude-traffic-light/releases).

- macOS DMG: `cd macos && ./build-dmg.sh` (menu bar) / `./build-widget-dmg.sh` (widget)
- Windows self-contained exe: from `windows\ClaudeTrafficLight` or
  `windows\ClaudeTrafficWidget`, run
  `dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true`

### Automated releases

Merging a PR into `main` runs [`.github/workflows/release.yml`](.github/workflows/release.yml),
which only publishes a new GitHub Release if the root `VERSION` file was bumped in that PR
(no matching git tag yet). When it does, it rebuilds all four distributables (both macOS DMGs
and both Windows exes) fresh and attaches them together to a single `vX.Y.Z` release/tag, so a
release is never a mix of old and new binaries — even if only one platform actually changed.
Each app's own internal version (Info.plist / `.csproj`) is independent and only needs bumping
for the platform you actually changed; bump `VERSION` whenever a PR should ship a release.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
