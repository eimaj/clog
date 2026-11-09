## Why

Mode B step 1 of clog-sweep resolves only today's clog log (`<log_root>/<log_subdir>/$(date +%Y%m%d).jsonl`), and Mode A reuses that step. A session that spans several days (observed 2026-11-06 to 2026-11-09) has state-changers whose matching entries sit in earlier days' logs, so the scout reports them as misses and backfills duplicates, or cannot see the earlier entries at all. Learning observed 2026-11-09. The golden scan (golden-skill-updater could not be invoked: it is reserved for explicit user invocation, so scan.json was the golden source) raised only notes (depends-on, age) and no defect.

## What Changes

- Mode B step 1 resolves the clog log of every day the session touched, not only today's.
- The scout prompts in Mode A and Mode B receive the list of log paths and match a state-changer against the log of the day it happened on.
- No other behavior changes; the SKILL.md itself is not edited by this review.

## Impact

- Spec: clog-sweep (MODIFIED requirement: Resolve clog logs).
- File: clog/skills/clog-sweep/SKILL.md (Mode A step 1 reference, Mode B step 1, both scout prompts, the "Today's clog log" input line).
- Risk: low; a single-day session resolves exactly the same one file as before.
