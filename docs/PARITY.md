# Parity with the original

Checked on 2026-10-17 against clawd-usage-winwidget v1.11.x (README, `config.json` keys, every `lib/*.ps1` header, CHANGELOG).
Legend: ✅ done · 🟡 partly · ⬜ planned (phase) · 🆕 not in the plan until now, added · ✖ left out on purpose · ➖ not applicable on macOS.

## Numbers and data

| Original | Here |
|---|---|
| Session %, bar colours at 60 / 85, "resets in…" | ✅ |
| Week and Fable weekly (Fable hidden when absent) | ✅ |
| Stale marking when `/usage` fails | ✅ + 🆕 retry in 10 s, error text in the panel and `~/Library/Logs/ClaudyUsage.log` |
| Sessions: count, working, waiting, hover list | ✅ (and better: project, branch, worktree, session name) |
| Sessions from other machines (`remoteSessions`) | 🆕 backlog, low value for a single Mac |
| Service status, incident and components, click opens the page | ✅ |
| Account line (plan, email, red "not logged in") via `claude auth status` | ✅ |
| 24h / 7d stats | 🟡 shown, still to be polished (asked) |
| Limits · 7 days chart with hover, Projects · 7 days | ✅ no backfill: the original rebuilt the first week from its own old probe transcripts, which we never left behind, so the chart starts the day the app first runs |
| Claude Code version, yellow when newer | ✅ (numeric compare, shown even when details are collapsed) |
| Hover: changelog between your version and the latest; click runs `claude update` | ✅ (runs in the background, then rechecks; not tested against a real update) |
| Widget self-update (download, replace, roll back) | ✖ runs downloaded code; rebuild from source instead |
| `CLAUDE_CONFIG_DIR` honoured | ✅ sessions and transcripts |

## Clawd and the sky

| Original | Here |
|---|---|
| Pixel map, moods, hearts, health tiers, click moves, confetti, soul, burrow | ✅ |
| Skins (11 built in, own folder) | ✅ files and loading; ⬜ picker in phase 4 |
| Developer menu (right-click Clawd: force a mood, play any move, set hearts, time of day, weather) | ✅ (no "demo" loop) |
| Sky: arc, moon phase, stars, clouds, rain, snow, fog, storm | ✅ |
| Sky tooltip: city, temperature, weather, wind, sunrise/sunset, moon phase | ✅ |
| Weather fallback to met.no | 🆕 backlog (only matters if Open-Meteo is blocked) |
| Weather location by IP | ✖ replaced by CoreLocation, or a fixed place typed in Settings → System |

## Window, menu and settings

| Original | Here |
|---|---|
| Floating window: drag, position saved, scale, opacity, always on top | ✅ as a separate floating widget (card that folds into a bubble, Liquid Glass); scale not ported |
| Tray icon with the % as a coloured number, tooltip with week and Fable | ✅ different: two mini bars `5h` / `W` in the menu bar |
| Tooltip with reset as clock time (`trayResetClock`) | 🟡 label style has numbers; reset clock times not shown |
| Tray menu: show/hide, refresh now, settings, exit | 🟡 a "⋯" menu in the panel header: Refresh now, Launch at login, Quit. Settings… arrives with phase 4 |
| Collapsible details, remembered | ✅ |
| Settings window, tab Look: language, theme, skin cards with live preview | ✅ + accent colour |
| Settings, tab Window: size, opacity, topmost, which blocks show, tray clock, admin | ✅ as "Menu bar": label style, blocks, thresholds. Size / opacity / topmost belong to the floating widget (later); admin ➖ |
| Settings, tab Clawd: tips, chat, auto-run, tasks, Remote Control session | ⬜ phase 5 toggles |
| Settings, tab Claude Code: ~30 keys of `~/.claude/settings.json` with hints, backup | ✅ 25 settings, same list |
| Languages en / ru / fr | ✅ en + **pt-BR** (ru / fr not ported) |
| Themes: classic, oled, midnight, mocha, forest, halloween (seasonal wallpaper), `accent` colour | ✅ (default Classic; "By season" is a choice) |
| `config.json` with live reload and ~60 keys | ✖ we use macOS `defaults` (UserDefaults); the keys that matter are exposed in settings |
| Polling intervals as settings | ✖ fixed (60 s usage, 5 s sessions, 2 min status); rarely worth a switch |
| Single instance (mutex) | ✅ |
| Autostart (scheduled task) | ✅ `SMAppService` (not tested from `~/Applications` yet) |
| Error corner label + `widget-error.log` | 🟡 log only for the usage probe |

## Clawd's panel: tips, chat, reminders, lists, tasks

| Original | Here |
|---|---|
| Tips about the computer (disk, autostart, unused apps, restart, hogs) | ✖ the checks are Windows-only. 🆕 idea: a macOS version (disk space, Login Items, caches, uptime) |
| Chat (`claude -p`, read-only tools, AUTO toggle, scripts with Run / Refine / Not now) | ⬜ phase 5 |
| Reminders as files with `at:` and `repeat:`, popup card with snooze (+15m, +1h, +3h, tomorrow), bell in the header | ⬜ phase 5 (notifications via `UserNotifications`) |
| "When" field parser (`18:30`, `tomorrow 10`, `+20m`, `mon 9:00`) and a Haiku fallback (`quickModel`) | 🆕 phase 5 detail |
| Lists with checkboxes | ⬜ phase 5 |
| Recurring tasks (`every:` / `at:`, `tools:`, `hours:`, Allow card, `tasksMaxPercent` gate) | ⬜ phase 5; 🆕 keep the limit gate (tasks wait while the 5h or week is ≥ 80%) |
| Clawd's home folder (`tips.md`, `chat-log.md`, `reminders/`, `lists/`, `tasks/`) | ⬜ phase 5 (`~/Documents/Clawd/`) |
| Clawd's own Claude Code session with Remote Control, to talk from the phone | ✖ out of scope for now |

## Added beyond the original

Floating Liquid Glass widget that folds into a bubble; alerts (a blinking ? while a session waits, confetti when a limit starts over, including one given ahead of time, optional notifications); the chart's 5-hour line coloured by level; the quota-cycle week view; label styles for the menu bar; Portuguese; Claude Code tab revert and presets; GIF / cover / redacted-screenshot tooling. See the README's "What is new compared with the original".

## Phase 4 settings, concretely (macOS)

Opened from a gear in the panel header and from the right-click menu, as its own window (a menu bar panel closes when it loses focus).

- **Look**: language (English, Português), theme with swatches (classic, OLED, midnight, mocha, forest, halloween, by season), accent colour, Clawd's skin as cards with live preview, "Your own" opens `~/Library/Application Support/ClaudyUsage/skins`.
- **Menu bar**: label style (two bars / bars with numbers / clock times of the resets), which blocks the panel shows (Clawd, sky, status, sessions, account, stats, history), warn and critical thresholds.
- **System**: launch at login, weather place (automatic via CoreLocation / manual lat-lon), polling intervals, open the log, open config folder.
- **Clawd** (phase 5): chat, tasks and tips toggles, AUTO, models.
- **Claude Code**: the original's key list over `~/.claude/settings.json` (`CLAUDE_CONFIG_DIR` aware), writing only the changed key, with `settings.json.clawd-bak`.

## Order proposed

1. ~~Polish~~ done, except the sessions / stats look that still needs your eyes on the real dropdown. Also done: app icon.
2. ~~Developer menu for Clawd~~ done.
3. ~~Phase 3: chart and projects~~ done.
4. Phase 4: settings (the list above), pt-BR strings, themes.
5. Phase 5: chat, reminders, lists, tasks.
6. Floating widget; macOS tips; custom body maps for new characters.
