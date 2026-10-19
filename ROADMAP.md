# Roadmap

Where Claudy Usage is going. It is a small project made in the open: the list is short on purpose, and **every item with a link is an issue you can pick up**. Newest decisions are at the top of each section; what is already done is in the [CHANGELOG](CHANGELOG.md), the feature-by-feature comparison with the original is in [docs/PARITY.md](docs/PARITY.md).

**Now** — the app works and has a release ([0.1.0](https://github.com/juliobianco/claudy-usage-mac/releases/tag/v0.1.0)): limits, sessions by project and branch, the 7-day chart, Clawd and his sky, the floating Liquid Glass widget, settings in English and Portuguese.

## Next

Small, clear, and good for a first contribution.

- **Check it by hand on other setups** — macOS 14 and 15 (no Liquid Glass), Intel, a second display. The things not yet exercised by hand: dragging the floating widget, the click that folds it into a bubble, *Launch at login*, typing a fixed weather place. → [#1](https://github.com/juliobianco/claudy-usage-mac/issues/1)
- **More languages** — adding one is one table of text. Spanish, French, Russian (the original has the last two). → [#2](https://github.com/juliobianco/claudy-usage-mac/issues/2)
- **New skins** — hats, glasses, seasons. A skin is a text file; the [guide](docs/CREATING-ART.md) shows how. → [#3](https://github.com/juliobianco/claudy-usage-mac/issues/3)
- **Reset times on the menu bar label** — the original can show `5h: 36% (resets 03:20)`; here the label shows only the percentages. → [#4](https://github.com/juliobianco/claudy-usage-mac/issues/4)
- **A "vivid sky" option** — the sky is translucent like the original's, so daytime looks dark; some people will want it bright. → [#5](https://github.com/juliobianco/claudy-usage-mac/issues/5)
- **Weather fallback** — the original falls back to [met.no](https://api.met.no) where Open-Meteo is blocked. → [#6](https://github.com/juliobianco/claudy-usage-mac/issues/6)

## Observability

Decided 2026-10-19 and done **before** phase 5. Items 1 to 9 shipped in 0.3.3 and 0.4.0 (2026-10-19); item 10 is next. In the order we will build them, one per sitting; the thinking for each (data, design, open questions) is in [docs/OBSERVABILITY.md](docs/OBSERVABILITY.md). Everything is read-only and stays on the Mac.

1. **Pace and forecast** — "at this pace you hit 100% at 15:40, before the reset". → [#14](https://github.com/juliobianco/claudy-usage-mac/issues/14)
2. **Health of the usage read** — when it last worked, and why not when it did not. → [#15](https://github.com/juliobianco/claudy-usage-mac/issues/15)
3. **Usage by project, deeper** — period switch, drill-down, and the model dimension in the scanner (the week ranking already exists). → [#16](https://github.com/juliobianco/claudy-usage-mac/issues/16)
4. **Pace alert** — a notification when the forecast says the limit comes before the reset. → [#17](https://github.com/juliobianco/claudy-usage-mac/issues/17)
5. **Markers on the limits chart** — resets and the moments a limit reached 100%. → [#18](https://github.com/juliobianco/claudy-usage-mac/issues/18)
6. **Usage by model** — Opus, Sonnet, Haiku and cache share. → [#19](https://github.com/juliobianco/claudy-usage-mac/issues/19)
7. **Hour-of-week heatmap** — when the 5h windows are really used. → [#20](https://github.com/juliobianco/claudy-usage-mac/issues/20)
8. **Export the history** — two CSV files (limits, and projects with models). → [#21](https://github.com/juliobianco/claudy-usage-mac/issues/21)
9. **Status by service** — which component is degraded, recent incidents. → [#22](https://github.com/juliobianco/claudy-usage-mac/issues/22)
10. **Tokens per day by model, all time** — a chart from Claude Code's own stats cache, like `/stats` → Models but prettier. → [#23](https://github.com/juliobianco/claudy-usage-mac/issues/23)

## Phase 5: Clawd as an assistant

**After the observability list above.** Today the app only *shows* things. This phase makes it *do* things. The design is written down in [docs/PHASE5.md](docs/PHASE5.md); built in this order because the first two cost nothing and carry no risk.

1. **Reminders** — files with a time, notification cards with snooze, repeating ones, a date field that understands "tomorrow 10", "+20m", "amanhã 10", "seg 9:00". → [#7](https://github.com/juliobianco/claudy-usage-mac/issues/7)
2. **Lists** — shopping and any other, with checkboxes, as plain files.
3. **Chat with Clawd** — a read-only `claude -p` conversation about your Mac; changes come as a script you approve. It spends plan limits, so it comes with guard rails.
4. **Recurring tasks** — things Clawd does every so often, gated by the 5-hour and weekly limits.

## Later

Bigger, or waiting for something.

- **Credits and usage by product** — the cloud-session credit balance and the week's split between Claude Code, Chats and Cowork. They are only on claude.ai's usage page; we need an honest data source first (no scraping, no borrowed tokens). → [#8](https://github.com/juliobianco/claudy-usage-mac/issues/8)
- **A notarized download and a Homebrew cask** — needs an Apple Developer ID; until then the zip asks for "Open Anyway". → [#9](https://github.com/juliobianco/claudy-usage-mac/issues/9)
- **Other creatures** — a skin that brings its own body, so Clawd's silhouette can change (a cat, a ghost). → [#10](https://github.com/juliobianco/claudy-usage-mac/issues/10)
- **A global hotkey** to show and hide the floating widget. → [#11](https://github.com/juliobianco/claudy-usage-mac/issues/11)
- **Tips about your Mac** — disk space, login items, caches, uptime: a macOS version of the original's Windows-only tips.
- **Sessions from other machines** — the original can read sessions published by a server or a VM.
- **A check for new versions of the app itself** — notify and open the release page; never download and run code. → [#12](https://github.com/juliobianco/claudy-usage-mac/issues/12)
- **Accessibility** — VoiceOver labels for the card, the bubble and the settings, and a "reduce motion" switch for Clawd. → [#13](https://github.com/juliobianco/claudy-usage-mac/issues/13)

## Not planned

The original's self-update (it downloads and runs code), its lookup of your location by IP address, and Clawd's own Remote Control session. The reasons are in the README's [Privacy](README.md#privacy-and-security) section.

## How to help

Pick an issue marked **good first issue** or **help wanted**, or open one with an idea. [CONTRIBUTING.md](CONTRIBUTING.md) has the five-minute version: build, test, where the text lives, and what must never go into a picture.
