# Proposal

## Why

`clog-sweep` only checks the current session: it finds the transcript from the current folder and `CLAUDE_SESSION_ID`, and compares it with today's log. conductor's `/pm-end` and `/pa-eod` need to check every session that worked on a project or for an assistant, including panes that have already closed and days that have already ended, before they roll up what was done.

## What Changes

- New skill `clog-sweep-sessions <sid> [<sid>…] [--date YYYY-MM-DD]…` that runs the existing sweep scan once per target session.
- It finds each transcript by session id under `~/.claude/projects/*/<sid>.jsonl`, independent of the current folder.
- It compares each transcript with the log file(s) for the dates the session ran, not only today.
- New CLI flag `--time HH:MM:SS`, validated like `--date`. Entries written with it also carry `logged_at` (the real write time), so backfills stay visible as backfills.
- `clog-day` and `clog-replay` sort entries by `time` before presenting them; log files stay append-only.
- It backfills every miss with `--session <sid>`, `--date <day>` and `--time <action time>` so the entry lands on the right session, day and time, each paired with a LEARNING as `clog-sweep` does today.
- It returns one JSON object per session (`sid`, `transcript`, `dates`, `gaps`, `backfilled`, `learnings`, `status`) plus the human punch list, so callers can report without re-reading logs.
- `clog-sweep` is unchanged and stays current-session only.

## Capabilities

### New Capabilities

- `session-sweep`: sweeping named sessions' transcripts against the log for unlogged actions, backfilling them on the right session and date, and reporting per session.

### Modified Capabilities

- `cli`: adds `--time`; `--date` no longer implies wall-clock `time` when `--time` is given.
- `log-entry`: `time` may come from `--time`; new optional `logged_at` field after `tags`.

## Impact

- New `skills/clog-sweep-sessions/` in this repo; linked into `~/.claude/skills` by the existing install.
- `bin/clog` gains `--time` and `logged_at`; help text and `tests/cli/run.sh` cover them. Hooks and config are unchanged.
- `clog-day` and `clog-replay` sort by `time`; other readers are unaffected.
- Consumers: conductor's `/pm-end` and `/pa-eod` (they fall back to current-session sweeping until this ships).
