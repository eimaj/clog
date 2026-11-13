# Tasks

## 1. Delta

- [ ] 1.1 Change the delta header in `specs/clog-sweep/spec.md` from `## MODIFIED Requirements` to `## ADDED Requirements`; `openspec validate clog-sweep-review-2026-11-09-tnbook --strict` passes with no archive warning.

## 2. Skill

- [ ] 2.1 Rewrite Mode B step 1 in `skills/clog-sweep/SKILL.md`: keep the transcript rule; get `dates` from `../clog-sweep-sessions/scripts/resolve.sh "$CLAUDE_SESSION_ID"`, append today if it is not the last date, pass them to `../clog-sweep-sessions/scripts/logs-for.sh`, keep only paths that exist, and keep the inline-scan fallback.
- [ ] 2.2 Mode A step 1 reference and both scout prompts take the list of log paths (`Clog logs (one JSONL file per day, named YYYYMMDD.jsonl):`), match each state-changer against the log of the day it happened on, and treat a day with no log as misses; update the "Inputs expected" line and the "How it works" sentence that say "today's log".

## 3. Tests

- [ ] 3.1 Add content checks for `skills/clog-sweep/SKILL.md` to `tests/cli/run.sh`: no `$(date +%Y%m%d).jsonl` single-log resolution, no `Today's clog log:` scout line, both prompts carry the multi-log input line, step 1 names `resolve.sh` and `logs-for.sh`.
- [ ] 3.2 `npm run check` passes.

## Workflow follow-up

- Backfilled commands for a miss on an earlier day still carry no `--date`/`--time`, so they land in today's log; a later change can add them as `clog-sweep-sessions` does.
- Archive this change.
