# Phase 5: Clawd as an assistant (planned, not started)

Chosen to be done later (2026-10-17). Source of the design: the original's README ("Clawd's panel: tips and chat", "Reminders and lists", "Recurring tasks") and `lib/chat.ps1`, `reminders.ps1`, `lists.ps1`, `tasks.ps1`, `remind-popup.ps1`, `panel-pages.ps1`.

Today the app only **shows** information. Phase 5 makes it **do** things. It has four parts that can be built and shipped one at a time.

## Order I would build them in

| # | Part | Uses a model? | Costs plan limit? | Risk |
|---|---|---|---|---|
| 1 | Reminders | only to read a loose date ("next Friday evening") | no (rarely a Haiku call) | none |
| 2 | Lists | no | no | none |
| 3 | Chat | yes, `claude -p` per message | yes | read-only tools, scripts need a click |
| 4 | Recurring tasks | yes, `claude -p` per run | yes, gated by the limits | needs per-task tool rules |

Ship 1 and 2 first: useful, free, harmless. 3 and 4 spend the very limit the app measures, so they come with guard rails.

## Clawd's home

A folder of plain files, so that the chat, a task, the user or any other tool can make one by hand. Default `~/Documents/Clawd/` (a setting).

```
~/Documents/Clawd/
  reminders/2026-11/2026-11-16 10-00 Pay the taxes.md     at: line, optional repeat: line
  reminders/done/                                         fired ones move here
  lists/shopping.md                                       "- [ ] milk" / "- [x] eggs"
  tasks/Mail.md                                           every: 10m | at: 09:00, 18:00 ; tools: ; hours: ; paused:
  tips.md  chat-log.md                                    written by the app, readable by any Claude session
  skins/                                                  (already in Application Support today)
```

## 1. Reminders

- A file per reminder: `at: 2026-11-16T10:00`, optional `repeat: daily | weekly | monthly | yearly`, then the text. When a repeating one fires, the app writes the file for its next time.
- When due: a notification card (macOS `UserNotifications`, plus a small card window like the original's bottom-right popup) with **+15m, +1h, +3h, tomorrow 9:00, any time**, and **done**. It waits until answered (the user may be away); several stack up. A bell in the panel header and a hop from Clawd, even with the panel closed.
- A tab in the panel (or a window): what is coming (Change, +1 hour, Delete), recently fired, and a form to add one.
- The "when" field understands without any model: `18:30`, `tomorrow 10`, `+20m`, `in a week`, `mon 9:00`, `19.10 14:00`, and shows what it understood. Anything else goes to a small model (`quickModel`, Haiku) and only what it cannot place is an error. Portuguese forms (`amanhã 10`, `seg 9:00`, `daqui a 20 min`) must be added for pt-BR.
- Checks every tick; works with the panel closed.

## 2. Lists

- Markdown files with checkboxes, shopping and any other. The tab shows and edits them: several items at once with commas, tick, remove the ticked, new list with "+".
- Lines that are not items (a heading, notes) are kept as they are.
- The chat can change them ("add milk to shopping").

## 3. Chat

- Each message is one headless `claude -p --output-format json --permission-mode default` call, in a conversation of its own (`--session-id`, then `--resume`), working in Clawd's home. The user's sessions are not touched.
- **Read-only by default**: `--disallowedTools Write Edit NotebookEdit`, MCP servers off, and an allowlist of read-only shell commands for macOS (`ls cat df du ps stat date pmset system_profiler uptime sw_vers`) instead of the original's PowerShell cmdlets.
- A change comes as a **script shown in full** with **Run**, **Refine** (the script is replaced) and **Not now**. An AUTO switch (off by default) runs scripts without the click, up to three in a row; Clawd is told, and asks in words before anything destructive.
- Gets as context: the time, the reminders, the lists, and the tips (if any).
- Model `chatModel` (Sonnet), timeout 300 s, `chat-log.md` kept for other sessions to read.
- Prompts: adapt the original's `chat-prompt.md` (review every line before use: it tells Claude how to emit `run` / `remind` / `list-*` blocks).

## 4. Recurring tasks

- A file per task: `every: 10m` or `at: 09:00, 18:00`, `tools:` (what it may use besides reading: an MCP server as `mcp__<server>`, a command rule like `Bash(gh issue list:*)`, `WebFetch(domain:github.com)`), `hours: 8-23`, `paused: yes`, `limit: 60`, `model:`, then the instructions.
- Runs a due one as a background `claude -p` in Clawd's home with the usual context and its own last reports, answering with `--json-schema` fields (tell / message / summary). Most runs end with nothing to say.
- **Gated by the limits**: tasks wait while the 5-hour session or the week is at `tasksMaxPercent` (80%) or more (a task can set its own `limit:`).
- A run that is refused a tool shows a card with the missing rules and **Allow**; that adds them to the task file and runs it again. A script a task proposes always waits for a click.
- The tab lists tasks with Run now, Pause, Open, Delete; clicking one shows a line per recent run.

## Security rules for the whole phase

- Never write, send or run anything without a click, unless the user switched AUTO on or gave a task that exact tool rule.
- Chat and tasks get no write tools; shell is an allowlist of read-only commands.
- Tool rules in task files are the user's; the app never adds one without the Allow click.
- Keep `claude` calls as argv arrays (never a shell string), with the same environment fix as the usage probe (`USER` set).

## Not part of this phase (left out on purpose)

- The original's "tips about the computer" (Windows-specific: autostart, Prefetch, Windows Update). A macOS version (disk space, Login Items, caches, uptime) is an idea in the backlog.
- Clawd's own interactive session with Remote Control, to talk from the phone.

## Work list

1. `Clawd's home` helper (path setting, folders, atomic file writes) and tests.
2. Reminders: file format + repeat rules, due check, `UserNotifications`, card window, tab, date parser (en + pt-BR) with tests.
3. Lists: file format, tab, tests.
4. Chat: `claude -p` runner (reuse `ClaudeCLI.exec`), prompt files adapted, block parser (`run`, `remind`, `list-*`), Run / Refine / Not now, AUTO, tests of the parser and of the allowlist.
5. Tasks: file format, scheduler with the limit gate, `--json-schema` answer, Allow card, tab, tests.
6. Settings: switches for each part (they are off until the user turns them on), models, AUTO, Clawd's home.
