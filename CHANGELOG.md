# Changelog

All notable changes to Claudy Usage. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow [semantic versioning](https://semver.org). The version of the app is in the [`VERSION`](VERSION) file.

Each release is a git tag (`vX.Y.Z`) with a GitHub Release; its notes are the entry below. For Homebrew, download and source installations, see [Updating](README.md#updating).

## [Unreleased]

### Fixed
- Energy: the sky and Clawd animation now run only while a window showing them is really on screen. It is tied to the window's visibility (shown and not covered), not to the view appearing, so a closed dropdown or a covered floating widget no longer keeps it going. A stop and start inside one tick can no longer leave two loops running.

## [0.6.2] - 2026-10-23

### Fixed
- 24 h chart: a few minutes of data cut off at the left edge by a long pause no longer draw a stray stub, and the 50%/100% labels are no longer crossed by the lines.

## [0.6.1] - 2026-10-23

### Fixed
- The menu bar label is drawn at 4x, so it is sharp on 4K and other external screens (it was soft and blocky there).

## [0.6.0] - 2026-10-23

The menu bar label, the sky and the limits chart get small options and polish.

### Added
- Settings → Menu bar → "Reset times on the label": the menu bar label can show when the 5-hour window (`18:39`) and the week (`Tue 05:59`) reset (#4).
- Settings → Menu bar → "Reduce motion": Clawd stands still, the sky moves once a minute and the alerts do not blink or throw confetti. It also follows the system's Reduce motion setting (#13, motion part).
- Two new skins: Halo and Headphones (#3).
- Settings → Menu bar → "Vivid sky": a bright, opaque sky behind Clawd instead of the translucent one (#5).

### Changed
- The limits chart shows faint guides at 50% and 100%, so its fixed 0–100% scale can be read.
- The limits chart leaves some air around the lines (above, below and at the sides), so they no longer touch the hour labels or the edges.

## [0.5.0] - 2026-10-19

The last piece of the observability list: the token stats window.

### Added
- "Token stats…" in the ⋯ menu and under the models in the details: a window with the tokens per day by model, for 7 days, 30 days or all time, read from Claude Code's own stats cache, with each model's share and, for all time, its input, output and cache totals.

## [0.4.0] - 2026-10-19

The observability release: eight more ways to see where your usage goes, all read-only and on the Mac.

### Added
- Service status in detail: when something is off, the line lists the open incidents and the affected components. Only the Claude API and Claude Code change the dot's colour; other services say "other services affected".
- "Export history…" in the ⋯ menu: the 5 h / weekly history and the usage by project and model, as two CSV files in a folder you pick.
- "When you use it": a heatmap of the last 7 days by hour, opened from the details.
- A MODELS section under the projects: the share of Opus, Sonnet, Haiku and others, for the same 24 hours / 7 days switch.
- Marks on the history chart: a ring where a limit reset, a red dot where it reached 100%, with the event named when you hover over it. The week view shows the weekly reset and the 100% marks only.
- A notification when the pace forecast says the 5-hour limit will be hit within the hour, before it resets. Once per window, on by default, with a switch in Settings → Alerts.
- The project ranking follows the 24 hours / 7 days switch, and a click on a project shows its model mix and its busiest hours of the day.
- A warning when the usage read keeps failing (two failures in a row, or 10 minutes without a good read): how long, why, and a "try now" button. The footer clock turns yellow too.

## [0.3.3] - 2026-10-19

### Added
- Pace forecast under the session reset ("at this pace: 100% at 16:07", or "fine until the reset") and under the week bar (from the week's average). Shown in the panel and the floating card.

### Fixed
- The bubble can be dragged again; it no longer springs back into the card.

## [0.3.2] - 2026-10-19

### Fixed

- The floating widget is readable over a light background: the Liquid Glass sits on a dark base, so it no longer turns grey and swallows the light text.

## [0.3.1] - 2026-10-19

### Changed

- Launch at login is now on by default, set once on first run; the toggle in the menu and settings still turns it off for good.
- The Homebrew cask opens the app right after install.
- Reorganized the README around installation and everyday use; moved detailed features, animation galleries and developer image tools to `docs/GUIDE.md`, clarified refresh intervals and update options, and highlighted the published v0.3.0 release.

## [0.3.0] - 2026-10-18

### Added

- A Homebrew tap: `brew install --cask juliobianco/tap/claudy-usage` ([homebrew-tap](https://github.com/juliobianco/homebrew-tap)). Bump `version` and `sha256` in its cask on each release.

### Fixed

- A `claude` probe that ignores the time limit is now killed (it could freeze the usage refresh); the settings backup is kept per file for the whole run; a `settings.json` with an invalid escape is no longer rewritten.

### Changed

- The usage is read every 20 s (instead of 60 s) once the session or the week reaches 90%, so the last points before a limit show up sooner.

## [0.2.0] - 2026-10-18

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
