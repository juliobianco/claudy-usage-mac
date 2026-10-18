# Claudy Usage (macOS)

Menu bar app that shows Claude plan limits (5h session, week, Fable) with Clawd the crab and a live sky.
A Swift port of [Enhed/clawd-usage-winwidget](https://github.com/Enhed/clawd-usage-winwidget) (PowerShell/WPF, MIT).
Reference clone of the original (read-only, may be gone): the session scratchpad `repo/src`; its `docs/PORTING.md` is the spec.

Status and backlog: `docs/STATUS.md`. Keep it current: move items when they are done or pushed back.
Original vs ours, feature by feature: `docs/PARITY.md`. Making skins, moves and sky sprites: `docs/CREATING-ART.md`.

## Layout
- `Sources/ClaudyCore`: no UI, testable. `Usage.swift` (probe + parser), `Sessions.swift` (+ git/worktree), `Status.swift`, `Format.swift`, `Clawd.swift` (pixel map, sequences, skins), `Mascot.swift` (mood/walk state machine), `History.swift` (5h/week samples + project scan of the transcripts), `Sky.swift` (weather, sun, moon, sim), `ClaudeSettings.swift` (order-keeping JSON editor for `~/.claude/settings.json`).
- `Sources/ClaudyUsage`: SwiftUI. `App.swift` (MenuBarExtra + bar label), `PanelView.swift`, `Scene.swift` (sky/Clawd canvas), `Model.swift` (polling), `Location.swift`, `HistoryView.swift` (24h / week chart), `Prefs.swift` (every user choice + themes), `Strings.swift` / `StringsClaude.swift` (all text, en + pt), `SettingsView.swift` / `SettingsUI.swift` / `ClaudeSettingsView.swift` (settings window), `FloatingWidget.swift` (the floating card / bubble in its own NSPanel), `Snapshot.swift` (dev aid).
- `Sources/ClaudyUsage/skins/*.txt`: built-in skins (copied from the original, MIT). Own skins: `~/Library/Application Support/ClaudyUsage/skins`.
- Mascot/sky code keeps the original's units (Px 2.0, Py 2.2); the view scales by `SceneModel.scale`.

## Commands
```
S=$HOME/Library/Caches/claudy-build
swift build --scratch-path $S
swift test  --scratch-path $S
./scripts/bundle.sh                     # builds and signs ~/Applications/ClaudyUsage.app
$S/debug/ClaudyUsage --snapshot DIR     # panel.png with live data, no screen-recording permission needed
$S/debug/ClaudyUsage --settings DIR     # settings-<tab>.png (env CLAUDY_LANG=pt for Portuguese)
$S/debug/ClaudyUsage --float-test DIR   # opens the REAL floating window and writes float-*.png of the screen around it (own windows only: no permission needed)
$S/debug/ClaudyUsage --scenes DIR       # sheet.png: Clawd + sky in 8 situations
                                        # env CLAUDY_SKIN=<id> and CLAUDY_SKINS_DIR=<folder> preview a skin
```
`--snapshot` accepts env `CLAUDY_LAT`, `CLAUDY_LON`, `CLAUDY_TICKS`, `CLAUDY_DETAILS`, `CLAUDY_MORE`, `CLAUDY_PERIOD=week`, `CLAUDY_FAKE_HISTORY` (a made-up week for the chart). Both modes quit by themselves; on a build error the old binary
may run instead, so check the build output first.

## Gotchas (each one cost time)
- `screencapture` shows no windows (no screen-recording permission), but the app can capture **its own** windows: `--float-test` calls `CGWindowListCreateImage` through `dlsym` (the symbol is marked unavailable in the SDK). Use it to check real windows, glass included. `ImageRenderer` cannot draw AppKit-backed views (Menu, DragHandle show as a yellow "prohibited" sign) nor a ScrollView.
- **Build outside `~/Documents`.** Its file provider adds xattrs and `codesign` fails with "detritus not allowed". Hence `--scratch-path` and the app in `~/Applications`.
- **`claude` needs `USER` in the environment.** From Finder the env is nearly empty and `claude -p /usage` then prints a cost summary, not the limits. `ClaudeCLI.exec` sets HOME/USER/LOGNAME/PATH.
- **`/usage` text differs from PORTING.md**: `resets Oct 17 at 6:59pm` (no comma). The Fable line can be missing. No `resets` means the window has not started (0%). Parser tolerates all of it; see tests.
- **Sessions `procStart` is UTC** (`Sat Oct 17 17:05:28 2026`), not local. Compared with `sysctl` start time, 5 s drift.
- Never run `/usage` through a shell that rewrites paths (Git Bash): it spends tokens. We spawn with an argv array.
- `MenuBarExtra` label drops custom shapes: the two mini bars are rendered with `ImageRenderer` to a bitmap.
- SwiftPM resources: `bundle.sh` must copy `ClaudyUsage_ClaudyUsage.bundle` into `Contents/Resources`, or `Bundle.module` crashes on launch.
- Failures of the usage probe go to `~/Library/Logs/ClaudyUsage.log`.

## Release
1. Put the new number in `VERSION`; move the `[Unreleased]` notes of `CHANGELOG.md` under a new `## [x.y.z] - date` heading.
2. `swift test`, `./scripts/bundle.sh`, look at the app.
3. Commit, `git tag vX.Y.Z`, push with the tag, and create the GitHub Release with that changelog entry as its notes.
Screenshots for the README come from `--readme` / `--float-test` with `CLAUDY_DEMO=1` (made-up data only): see "Development" in the README. Never put real session names, e-mails or paths in a picture.

## Text
Never hard-code a user-facing string: add the key to `Strings.swift` in both languages (`L.t("key", args)`). The core returns keys and data, the UI words them.
Snapshots must not write to the real files (`AppModel.persist = false`); a fake week once leaked into the real history.

## Decisions
- No login in the app: it reuses the Claude Code login through `claude -p /usage`.
- Not ported on purpose: the original's self-update (downloads and runs code), IP geolocation (`ipwho.is`, replaced by CoreLocation), the Windows "advisor".
- Chat/tasks (phase 5) must stay read-only by default; actions run only after a click.
- Code style: match the existing files; comments say why, in English; one file per domain.
