# Changelog

All notable changes to Claudy Usage. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow [semantic versioning](https://semver.org). The version of the app is in the [`VERSION`](VERSION) file.

Each release is a git tag (`v0.1.0`) with a GitHub Release; its notes are the entry below. To update: `git pull`, then `./scripts/bundle.sh`.

## [Unreleased]

### Fixed

- The menu bar label cut "100%" to "10…" in the bars-and-numbers style; the number column now fits.

### Added

- **Alerts**: a blinking yellow ? on the menu bar label, a pulsing pill on the card and a pulsing rim on the bubble while a session waits for you; confetti on the label and the bubble (and Clawd's celebration) when a limit starts over, including a reset that comes ahead of time; optional notifications; previews in Settings → Menu bar.
- `ROADMAP.md`, `CONTRIBUTING.md` and a set of labelled issues (good first issue / help wanted).
- Pictures from the app itself: animated GIFs of Clawd (tour, sleep, clicks, limit, reset, hearts, weather) and of the floating widget, real-use screenshots with names redacted (`CLAUDY_REDACT`), and a cover image (`docs/images/social-preview.png`).
- The limits chart's 5-hour line takes the colour of the level it is in (green, yellow, red) and the area under it is shaded by zone; it follows the levels set in Settings → Menu bar.

Planned, not started: reminders, lists, chat and recurring tasks ([docs/PHASE5.md](docs/PHASE5.md)); credits and usage by product, if a data source turns up ([docs/STATUS.md](docs/STATUS.md)).

## [0.1.0] - 2026-10-17

First version: a macOS port of [Enhed/clawd-usage-winwidget](https://github.com/Enhed/clawd-usage-winwidget), with changes of its own.

### From the original, for the Mac

- Plan limits from `claude -p /usage` (no tokens spent): the 5-hour session, the week and the Fable week, with the time to reset, stale marking and a retry when the probe fails.
- Running Claude Code sessions from `~/.claude/sessions`, only live processes; Anthropic's service status; the Claude Code version and its changelog; the account line.
- The 24-hour and 7-day stats, the 7-day limits chart with hover, and the projects that spent the most (from the transcripts, tokens weighted by the model's price).
- Clawd with every mood, the health hearts, click animations, confetti, the burrow and the soul; the sky with the real sun, the moon phase, stars, clouds, rain, snow, fog and storms from Open-Meteo.
- The 11 skins and the skin file format; the six themes; the "Claude Code" settings tab with its backup file.

### New in this port

- **Menu bar app** with a label of two mini bars (`5h`, `W`); label styles: bars, bars and numbers, numbers.
- **Floating widget**: the compact card in its own always-on-top window that can be placed anywhere, folds into a two-ring bubble and unfolds; Liquid Glass on macOS 26+ with a solid fallback; inflates out of the dropdown and shrinks back into the bar; opacity and always-on-top options.
- **Sessions show the project, git branch and worktree**; worktrees count for their repository in the projects list.
- **Quota-cycle chart**: the 7-day view runs from the weekly reset to the next, with "now" marked; the 24-hour view zooms to the data while the history is young.
- **Redesigned details**: one period at a time, big numbers, bars, readable skill and MCP names, an (i) that explains why the usage profile does not add up to 100%.
- **Settings window** (Look, Menu bar, System, Claude Code): language, themes and accent colour, skin cards with preview, what the panel shows, bar-colour levels with a live scale, launch at login, a fixed weather place, history clearing.
- **Claude Code tab**: 25 settings, **revert** to how they were when Settings opened, **three presets**, **Opus Plan** as a model choice; the file's key order is preserved.
- **Portuguese (Brasil)** next to English; every text is in one table.
- **Weather without an IP lookup**: the system's location with your permission, or a fixed place.
- **Developer menu** on the sky (force a mood, a move, the hearts, the time of day, the weather).
- Hover texts: the sky (place, weather, wind, sun, moon), the Claude Code changelog on the version line, and a one-click `claude update`.
- Tools for art: [docs/CREATING-ART.md](docs/CREATING-ART.md), an example skin, command-line previews.
- A unit-tested core and offscreen screenshot tools that need no permission, with demo data.
- A prebuilt universal (Apple silicon + Intel) zip with its SHA-256 on the release, from `scripts/package.sh`. It is ad-hoc signed and **not notarized**, so macOS asks to allow it the first time (see the README).

### Fixed along the way (problems the original's notes did not mention)

- `/usage` on macOS words the reset as `Oct 17 at 6:59pm` (no comma); the parser accepts both forms, and the Fable line may be absent.
- A session file's `procStart` is in UTC, not local time.
- Launched from Finder, `claude` needs `USER` in its environment, or it prints a cost summary instead of the limits.
- The menu bar window kept its largest size after the details were collapsed; it now follows the content.

### Left out on purpose

Self-update (it downloads and runs code), the IP-address location lookup, the Windows-only tips and administrator mode, and Clawd's phone session.
