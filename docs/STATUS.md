# Status

Plan: `~/.claude/plans/async-sparking-reddy.md` (outside the repo). Updated 2026-10-18. The public plan is `ROADMAP.md`; this file is the working log.

## Done
- **Documentation refresh** (2026-10-18): README focused on installation, getting started and feature overview; detailed reference and media galleries moved to `docs/GUIDE.md`. Updated contributor links, refresh intervals and update instructions; checked the published v0.3.0 assets and matching Homebrew cask checksum.
- **Releases 0.2.0 and 0.3.0** (2026-10-18): `v0.2.0` published (alerts, pictures). `v0.3.0` published with the Homebrew tap, usage read every 20 s near a limit, and fixes from a Codex review (probe killed with SIGKILL after the time limit, settings backup kept per file, invalid JSON escape rejected). Not done, on purpose: concurrent writes to settings.json (tiny window), scanner marker with spaces (Claude Code writes compact JSON), projects with the same folder name are merged (would need a path key). Phase 5 (issue #7) waits: the direction is in doubt.
- **Published** (2026-10-17/18): repository https://github.com/juliobianco/claudy-usage-mac (public), releases up to `v0.3.0` with the universal ad-hoc-signed zip + SHA-256 (not notarized), README, CHANGELOG, `ROADMAP.md`, `CONTRIBUTING.md`, 13 labelled issues, the cover image uploaded as the repo's social preview.
- **Pictures** (2026-10-18): GIFs of Clawd and of the floating widget, real-use screenshots with names redacted, the cover; all made by the app (`--gifs`, `--float-gif`, `--readme`, `--float-test`, `--banner`, `--alerts`, with `CLAUDY_DEMO` / `CLAUDY_REDACT`).
- **Alerts** (2026-10-18): a blinking ? on the menu bar label, a pulsing pill on the card and a pulsing rim on the bubble while a session waits; confetti on the label and the bubble when a limit starts over (`ResetDetector`, also for a reset ahead of time); optional notifications; previews in Settings → Menu bar. The chart's 5-hour line is coloured by level.
- **Phase 1**: `/usage` probe and parser (tested), sessions with project / branch / worktree, Claude status, Claude Code version, panel card, two mini bars (`5h`, `W`) in the menu bar.
- **Polish pass 1** (2026-10-17): account line, sky tooltip, version changelog + `claude update`, "⋯" menu (Refresh, Launch at login, Quit), single instance, app icon (`scripts/make-icon.sh`), developer menu (right-click the scene).
- **Polish pass 2** (2026-10-17): window follows the content height (no empty frame after collapsing), details redesigned: 24h / 7d switch, big numbers, share bars, rankings on demand with readable names.
- **Floating widget** (2026-10-17): the compact card (sky, Clawd, 5h, week, sessions, status) in its own always-on-top window, draggable, position remembered, that folds into a bubble with two rings (5h outside, week inside) and unfolds again. Liquid Glass on macOS 26+ (switchable, theme background otherwise), opacity, always-on-top. It inflates out of the dropdown (pin button in the header, "Floating widget" in the ⋯ menu and in Settings → Menu bar) and shrinks back into the bar. Reopens at launch if it was open.
- **Fixes after first use** (2026-10-17): skin changes at once; bar colours explained with a live scale and a reset; Opus Plan model; Claude Code presets (3 slots) and "revert to how it was when Settings opened"; log in local time and a note when the probe recovers; refresh after wake; probe timeout 45 s.
- **Cleanup** (2026-10-17, ponytail audit): removed the dead stat shortening, `Format.plural`, the legacy weather defaults keys, five unused palette colours, the old `--floating` snapshot and the probe script; the limit row / bar and the glass-or-solid surface are now shared code.
- **Phase 4** (2026-10-17): Settings window (gear in "⋯" menu → Settings…): Look (language en / pt-BR, 7 themes incl. Halloween wallpaper, accent colour, skin cards with live preview), Menu bar (label style: bars / bars + numbers / numbers, what the panel shows, yellow / red thresholds), System (launch at login, weather place, clear history, open log / data), Claude Code tab (25 settings (26 keys) of `~/.claude/settings.json`, order kept, `.clawd-bak` backup). All UI text is in `Strings.swift` (en + pt-BR). The 7-day chart follows the 24h / 7d switch: week view is the quota cycle (day 1 = the reset day, "now" marked, rest of the week shaded). (i) next to "Usage profile".
- **Phase 3** (2026-10-17): "Limits · 7 days" chart (5h green, week blue, day marks, hover with time / percentages / busiest project) and "Projects · 7 days" from the transcripts (worktrees count for their repo). The history starts when the app first runs and is kept in `~/Library/Application Support/ClaudyUsage/usage-history.json`.
- **Phase 2**: Clawd (all moods, click animations, hearts, confetti, burrow, soul), sky (sun, moon phase, stars, clouds, rain, snow, fog, storm), Open-Meteo weather, CoreLocation, 11 built-in skins.

## In progress
- Nothing open.

## Next (in order)
Full comparison with the original: `docs/PARITY.md`.
1. **Check by hand** (issue #1): the alerts and the previews, dragging the floating widget, the bubble click, Launch at login, a fixed weather place, macOS 14/15 and Intel. **Polish pass 3**: confirm on the real dropdown that the window now fits the content; sessions block may still be busy. The "⋯" menu, hover texts and the window fit were only checked in code (offscreen renders cannot show them).
2. **Phase 5** (chat, reminders, lists, recurring tasks): written up in `docs/PHASE5.md`, to be done later. Reminders and lists first (issue #7).
3. Everything else open is in `ROADMAP.md` and in the issues.

## Pushed back / ideas
- **Credits ("Cloud session credits: $48 of $100 left, expires Nov 5") and "This week's usage by product" (Claude Code 95%, Chats 1%, Cowork 4%, Other 0%)**: both are on claude.ai/settings/usage only. `claude -p /usage` does not print them (checked, text and json) and no `claude` subcommand exposes them. The only automatic source would be Anthropic's OAuth usage endpoint called with the Claude subscription login. On this Mac the Keychain item `Claude Code-credentials` holds only MCP logins (no `claudeAiOauth`), so that login is somewhere else; not searched further. Left for later. If taken up: show each as its own switch in Settings → Menu bar, like the Fable one. Simpler fallbacks: an "Open usage on claude.ai" button, and a hand-typed credit balance. A read-only probe script was written and then removed (the item held only MCP logins); if rewritten, it must use `claudeAiOauth.accessToken` and nothing else.
- Floating widget: dragging and the click that folds the bubble were not exercised by hand (the capture shows the render and the animation frames only). A global hotkey to show / hide it.
- Settings never seen live yet (offscreen renders only): check that the window opens in front, the fields (weather lat / lon) accept typing, and Launch at login works from `~/Applications`.
- Language: the dev menu, the Dock-less window title and Claude's own text (changelog, incidents) stay in English.
- More languages: one more table in `Strings.swift` (+ `StringsClaude.swift`).
- **Custom characters**: let a skin file carry its own body map (see `docs/CREATING-ART.md`, "Other creatures").
- Closed menu bar label: maybe a mini Clawd next to the bars.
- Weather fallback to met.no (original has it; only Open-Meteo here).
- Sessions from other machines (`remoteSessions` in the original).
- macOS version of the original's tips (disk space, Login Items, caches, uptime).
- Sky colours are translucent like the original, so daytime looks dark; add a "vivid sky" option if it bothers.
- Release builds are universal and ad-hoc signed, without notarization. Browser downloads need first-open approval; the Homebrew cask clears quarantine. Cross-Mac validation is still pending (issue #1).
- Left out on purpose: self-update, IP geolocation, Windows admin mode, Clawd's phone session (Remote Control).

## Making your own art
Full guide: `docs/CREATING-ART.md` (skins, animations, sky sprites, limits).

- **Skin** (accessory or recolour): a text file in `~/Library/Application Support/ClaudyUsage/skins/<name>.txt`.
  Header between `---` lines: `name:`, optional `body:` / `eyes:` colours, optional `top:` (first art row relative to Clawd's top row),
  and one `letter: #RRGGBB` per colour. Then the art, 18 pixels wide, `.` is empty. See `Sources/ClaudyUsage/skins/crown.txt`.
  Pick it with `defaults write dev.julio.claudy-usage skin <name>` (a picker comes in phase 4).
- **Animation**: add an entry to `Clawd.seqs` in `Sources/ClaudyCore/Clawd.swift` (frames of 60 ms: eyes/arms/feet, offset, shift).
- **New creature or sky sprite**: pixel art in code (`rows([...])` in `Scene.swift`), same technique as the sun and clouds.
