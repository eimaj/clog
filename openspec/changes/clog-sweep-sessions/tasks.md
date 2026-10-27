# Tasks

## 1. CLI time override

- [x] 1.1 Add `--time HH:MM:SS` to `bin/clog` (validation, empty = no override, value-flag rejection rules, help text); add cases to `tests/cli/run.sh` for valid, invalid, short form, missing value, and with/without `--date`.
- [ ] 1.2 Write `logged_at` (`YYYY-MM-DDTHH:MM:SS`) after `tags` only when `--time` is used; test key order and absence on normal entries.
- [ ] 1.3 Make `clog-day` and `clog-replay` sort a day's entries by `time` before use; verify with a fixture file containing an out-of-order backfill.

## 2. Scripted lookup

- [ ] 2.1 Add `skills/clog-sweep-sessions/scripts/resolve.sh <sid>…`: prints one JSON line per sid with `transcript` (found under `~/.claude/projects/*/<sid>.jsonl`, overridable via `CLOG_CC_PROJECTS`) and `dates` (from the transcript's first and last timestamps) or `status: "no_transcript"`; test with fixture transcripts incl. one spanning midnight and one missing, in `tests/cli/run.sh`.
- [ ] 2.2 Add `scripts/logs-for.sh <date>…`: prints the log file path per date from clog config; test with a scratch `CLOG_CONFIG`.

## 3. Skill

- [ ] 3.1 Write `skills/clog-sweep-sessions/SKILL.md`: triggers (called by `/pm-end`, `/pa-eod`, or "sweep sessions <ids>"), runs `resolve.sh`, dispatches the existing `clog-sweep` scout prompt once per session with that session's transcript and log files, and requires every backfill line to carry `--session <sid> --date <day> --time <action time>`; verify by dry-running on two real past sessions and checking the emitted commands.
- [ ] 3.2 Skip actions that already have a matching entry within ±60s on that session (including earlier backfills); verify by running twice on the same session and seeing zero gaps the second time.
- [ ] 3.3 Return the per-session JSON (`sid`, `transcript`, `dates`, `gaps`, `backfilled`, `learnings`, `status`) and the punch list; verify the JSON parses with `jq`.
- [ ] 3.4 Every run logs one clog ACTION summarising sessions swept and entries backfilled; verify in the day's log.
- [ ] 3.5 Add the skill and `--time` to the README and confirm `clog-sweep/SKILL.md` is unchanged (`git diff --quiet -- skills/clog-sweep`).

## 4. Integration

- [ ] 4.1 `openspec validate clog-sweep-sessions --strict` and `tests/cli/run.sh` pass.

## Workflow follow-up

- conductor's `/pm-end` and `/pa-eod` switch from current-session fallback to this skill once it is installed.
- Archive this change.
