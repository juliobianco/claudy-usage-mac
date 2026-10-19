# Observability: what we measure next

Decided 2026-10-19. Phase 5 (Clawd as an assistant) comes **after** all of this. One item per sitting is fine: each is written to stand alone, and says what it touches so two items never overlap.

How to use this file: when we start an item, we talk it through, write the decisions under **Decided**, and move its line in the table to *done*. Nothing here is built yet.

## Order

| # | Item | Issue | Touches | Needs | Status |
|---|---|---|---|---|---|
| 1 | Pace and forecast | [#14](https://github.com/juliobianco/claudy-usage-mac/issues/14) | `History.swift` (a pure function), panel, floating card | nothing | done (0.3.3) |
| 2 | Health of the usage read | [#15](https://github.com/juliobianco/claudy-usage-mac/issues/15) | `Model.swift`, panel | nothing | to discuss |
| 3 | Usage by project, deeper | [#16](https://github.com/juliobianco/claudy-usage-mac/issues/16) | scanner (adds the model dimension), `PanelView` | nothing | to discuss |
| 4 | Pace alert | [#17](https://github.com/juliobianco/claudy-usage-mac/issues/17) | alerts in `Model.swift`, `AlertsUI`, settings | 1 | to discuss |
| 5 | Markers on the chart | [#18](https://github.com/juliobianco/claudy-usage-mac/issues/18) | `HistoryView.swift` | maybe 1 | to discuss |
| 6 | Usage by model | [#19](https://github.com/juliobianco/claudy-usage-mac/issues/19) | UI only | the model dimension from 3 | to discuss |
| 7 | Hour-of-week heatmap | [#20](https://github.com/juliobianco/claudy-usage-mac/issues/20) | UI over `ProjectUsage.hours` | 3 (period) | to discuss |
| 8 | Export | [#21](https://github.com/juliobianco/claudy-usage-mac/issues/21) | a small writer in the core | nothing | to discuss |
| 9 | Status by service | [#22](https://github.com/juliobianco/claudy-usage-mac/issues/22) | `Status.swift` | nothing | to discuss |

Why this order: 1 is the most useful and needs no new data; 2 is cheap and removes a confusing case (the panel looks frozen); 3 changes the scanner, so 6 and 7 become UI only. 4 waits for 1 because it is the same forecast with a notification on top. 8 and 9 are independent and can move up or down.

What already exists (so we do not rebuild it): the week ranking "PROJECTS · 7 DAYS" (`ProjectUsage.ranked`, weight = tokens × model price, cache and output weighted), the busiest project of the hour in the chart hover, and the hour-by-project map `ProjectUsage.hours` kept for the 7 days.

## 1. Pace and forecast

**Idea.** "At this pace you reach 100% at 15:40, before the reset at 17:00." For the 5h session and for the week.

**Data.** `UsageHistory` samples (minute, session %, week %), one every 5 min when unchanged, more often when it moves. The reset time comes from the usage read.

**Thinking.**
- A pure function in the core, `Pace.forecast(samples, now, resetsAt) -> hitsAt / safe / unknown`, with tests (the project already tests the core). No UI code in it.
- Slope: from the samples of the current window only (stop at a drop, which is a reset), over the last N minutes (try 30 for the session, a day for the week). Linear is enough; no regression library.
- Say nothing when there is too little data (window just started, fewer than 3 samples, flat line): "unknown" is shown as nothing, never as a guess.
- The week is slow and bursty (nights, weekends): a naive slope lies. Probably use the average since the week began instead of the last hours, and say "at the weekly average".
- Text via `L.t`, both languages. Where: one line under the bar in the panel and the floating card; the bubble is too small.

**Open questions.** Which window for the session slope? Show a time or a time-left ("in 1h 20m")? Show the line when safe ("fine until the reset")? In the menu bar label or only inside?

**Decided.** (2026-10-19)
- Session slope over the last 30 minutes of the current window; needs 10+ minutes of line, else shows nothing.
- A time ("at 16:07"), not a time-left: the reset line above already says how long is left.
- Always shown when there is a forecast, also when safe ("fine until the reset").
- Week: the average since the week began (needs 6 h of week), worded "at the week's average".
- Only inside the panel and the floating card, as a small line under the reset (session) and under the week bar. Not in the menu bar label or the bubble. Placement to be revisited after living with it.
- Built: `Sources/ClaudyCore/Pace.swift` (pure, tested in `PaceTests`), `AppModel.sessionPaceText` / `weekPaceText`.

## 2. Health of the usage read

**Idea.** Show when the last `claude -p /usage` worked, and why not when it did not (not logged in, `claude` missing, timeout, text not understood), instead of old numbers that look current.

**Data.** What `Model.swift` already knows when a probe fails; failures already go to `~/Library/Logs/ClaudyUsage.log`.

**Thinking.**
- Keep the last good time and the last error as a key plus data; the UI words it.
- Quiet when fine: a small "updated 2 min ago" in the footer, a visible warning only after a number of failed reads or when the data is older than a limit.
- A button to open the log. No new log format.
- Do not retry faster on failure (the probe can spend tokens when the environment is wrong).

**Open questions.** Is there already a "last updated" in the panel to reuse? How old before it is a warning? Does the floating card get an indicator or only the panel?

**Decided.** (empty)

## 3. Usage by project, deeper

**Idea.** The week ranking exists. Add: a period switch (today / 7 days), a drill-down on a project (its days, its models), and the **model dimension** in the scanner.

**Data.** `ProjectScanner.scan`. Today it folds everything into `hours[hour][project] = weight`. To split by model, the key becomes (project, model family) while the totals stay the same.

**Thinking.**
- Change the scanner **once**, here, so 6 and 7 are only UI. Keep the file cache format working (the cache holds `w[hour]`; it becomes `w[hour][family]`).
- Model family: Opus, Sonnet, Haiku, other. Taken from the same price table, so the two cannot disagree.
- The weight is an estimate (tokens × price), not the plan's real accounting; the tooltip already says so. Keep saying so.
- The sessions list already shows projects live; the ranking is history. Do not merge them.

**Open questions.** Do we keep only 7 days of hours, or more? Drill-down as an expandable row or a small popover? Is "today" local midnight or the last 24 h?

**Decided.** (empty)

## 4. Pace alert

**Idea.** A notification when the forecast says the limit will be hit before the reset, once per window, with a "pace" wording different from the "you reached it" alert.

**Thinking.**
- Reuse item 1's function and the existing alerts (`alertsNotify…` prefs, `Notifier`, the preview button in settings). Only new: the rule and one switch.
- Once per window and with hysteresis, or it nags every 5 minutes. Re-arm after the reset.
- Do not fire on "unknown".
- Interaction with the 20-second polling near a limit: no change.

**Open questions.** Threshold: only if it is hit at least 30 min before the reset? Session only, or the week too?

**Decided.** (empty)

## 5. Markers on the chart

**Idea.** Small marks on the 24h and week charts: resets, the moments a limit reached 100%, maybe the forecast as a dotted line.

**Thinking.** The drop to zero and the red peak are already visible; markers add a label and a time on hover. Keep the gaps as they are (decided: the line breaks where the app was off, no invented data). Do after 1 so the forecast can share the drawing.

**Open questions.** Which events are worth a mark? Is it clutter on the 24h view?

**Decided.** (empty)

## 6. Usage by model

**Idea.** Opus / Sonnet / Haiku share of the week, and how much is cache. UI only, using item 3's dimension.

**Open questions.** A bar under the project list or a separate heading? Cache share needs the token kinds kept apart in the scan; decide in item 3 whether to keep them.

**Decided.** (empty)

## 7. Hour-of-week heatmap

**Idea.** Weekday by hour, intensity by weight, to see when the 5h windows are really used.

**Thinking.** `ProjectUsage.hours` already has it for the last 7 days: one week is a thin sample (one cell per slot). Maybe keep more history on disk (like `UsageHistory`, which keeps 8 days) so it fills over time. That is the real decision here.

**Open questions.** Keep longer history? Where does it live: a section in the panel or in the settings window?

**Decided.** (empty)

## 8. Export

**Idea.** "Export history…" writes CSV (minute, session %, week %) and the project weights, to a place the user picks. Read-only, nothing leaves the Mac.

**Thinking.** A tiny writer in the core with a test; a menu item and a save panel in the UI. Names of projects are real names: say so in the dialog (the README rule about pictures does not apply to the user's own file, but it should not surprise them).

**Decided.** (empty)

## 9. Status by service

**Idea.** The "All Claude systems operational" line becomes detail when something is wrong: which component, and the latest incident.

**Thinking.** `Status.swift` already reads the public status page; check whether the data we fetch already has components before adding a request. Keep the one-line form when everything is fine.

**Open questions.** Does the status endpoint we use expose components and incidents? Click to open the status page?

**Decided.** (empty)
