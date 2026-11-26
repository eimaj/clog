## Context

`skills/clog-sweep/SKILL.md` Mode B step 1 resolves one log, `<log_root>/<log_subdir>/$(date +%Y%m%d).jsonl`, and Mode A step 1 reuses it. Both scout prompts take a single `Today's clog log: <LOG_PATH>` line. A current session that runs over several days is compared only with today's log. `skills/clog-sweep-sessions/scripts/` already holds two tested helpers that do the day math: `resolve.sh <sid>` prints the local dates from a transcript's first to last timestamp, and `logs-for.sh <date>…` prints each date's log path from clog config. Installed `~/.claude/skills/clog-sweep` is a symlink into this repo, so the sibling skill's scripts are on disk next to it.

## Goals / Non-Goals

**Goals:** resolve every existing day log from the transcript's first day through today; give the scout all of them; match each state-changer against the log of its own day; leave a single-day session resolving exactly today's log.

**Non-Goals:** cross-session sweeping (stays in `clog-sweep-sessions`, per session-sweep "clog-sweep unchanged"); changing how the transcript path is found; adding `--date`/`--time` to backfilled commands; any other Mode A or Mode B behavior.

## Decisions

- **Reuse `resolve.sh` and `logs-for.sh` instead of new day math in SKILL.md.** They are tested in `tests/cli/run.sh`, handle local timezone and midnight, and read clog config the same way `bin/clog` does. Alternative, inline `date` arithmetic in the skill text: untested and easy for a haiku-run skill to get wrong.
- **Use `resolve.sh` for `dates` only; keep the transcript path rule unchanged.** The proposal limits the change to log resolution. Through-today: if today is not the last date, append it, since the current session is running today.
- **Skip non-existent day files in step 1, and tell the scout that a state-changer on a day with no log is a miss.** Matches the "A touched day has no log" scenario.
- **Scout input becomes `Clog logs (one JSONL file per day, named YYYYMMDD.jsonl):` followed by one path per line**, and the matching rule says to use the log of the day the tool call happened on (local date of its timestamp). The day is readable from the file name, so no extra mapping is passed.
- **Delta uses ADDED, not MODIFIED.** No `openspec/specs/clog-sweep/` baseline exists, so archive refuses MODIFIED. Requirement text is unchanged; Jamie chose this on 2026-11-12.
- **Guard with content checks in `tests/cli/run.sh`**, the same `grep -c` pattern used for `clog-sweep-sessions/SKILL.md`.

## Risks / Trade-offs

- [Cross-skill dependency on `clog-sweep-sessions/scripts`] → both skills ship in this repo; step 1 keeps the existing fallback to inline scan when resolution fails.
- [Long multi-day sessions give the scout more log lines] → the existing "scan only since the last ACTION/DECISION/LEARNING" note still applies.
- [Backfilled commands still have no `--date`, so a miss from an earlier day lands in today's log and a re-run may report it again] → out of scope by the proposal; recorded as a follow-up.
