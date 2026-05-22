---
name: clog-it
description: Backfill missing clog entries from the current session and capture LEARNINGs about why they were missed. Use when the user says "clog it", "/clog-it", "backfill clogs", or at any pause where state-changing actions went unlogged.
model: haiku
---

# clog-it

> Canonical reference for `clog` syntax, types, and flag tables: [`clog`](../clog/SKILL.md). This skill is the retroactive-sweep wrapper.

## Trigger

**Use when:** the user says "clog it", "/clog-it", "backfill clogs", "I missed some clogs", or you notice mid-session that state-changing actions in this transcript were never logged.
**Do not use when:** logging a single named event the user just described — use [`clog`](../clog/SKILL.md) directly.
**Inputs expected:** current session transcript and today's JSONL log.
**Outputs produced:** one backfilled `clog` call per missed action, plus one paired `LEARNING` per miss naming the pattern.

## Why this exists

In practice, rapid-fire edits, MCP mutations, and subagent dispatches slip past inline checkpoints. This skill is the explicit pause that catches them. It also drives the meta-improvement loop: each miss yields a `LEARNING` that names *why* the discipline failed, so the signal lands in the JSONL for retros.

## Steps

1. **List today's existing entries** — read the configured log path today's JSONL file:
   ```bash
   jq -r '[.time, .type, .summary] | @tsv' <log_root>/<log_subdir>/$(date +%Y%m%d).jsonl 2>/dev/null | tail -40
   ```

2. **Scan this session's tool calls** for state-changers:
   - `Edit` / `Write` / `NotebookEdit` → `CODE` (or `ACTION` if it triggered a workflow)
   - MCP mutations (Jira create/edit, Slack send, Confluence create/update, etc.) → `ACTION`
   - Subagent dispatches that produced artifacts → `ACTION` at the orchestration level
   - Tradeoffs resolved during planning → `DECISION`
   - grep/Read findings that changed the approach → `LEARNING --kpi effective`
   - Corrections to a previously-logged claim → `LEARNING`
   - **Skip:** `git commit` / `git push` / `gh pr create` — auto-logged by `post-action-log.sh`. Missing entries here are hook issues, not clog misses.

3. **Diff candidates against existing entries.** Drop any already present.

4. **Present the misses** as a compact list — one line each with proposed `TYPE` + summary. Get approval before backfilling unless the user said "just do it".

5. **Backfill each miss** with `clog` (syntax in [`clog`](../clog/SKILL.md)). Pass `--repo` explicitly when not in the repo dir. Omit `--date` when the action was earlier today.

6. **Pair every miss with a LEARNING** explaining why it was missed. Use `--family interactive` (or `--family skills` if the gap is a skill prompt issue). For `--kpi` selection see [`clog`](../clog/SKILL.md).

7. **Summarize** to the user: N backfilled, N LEARNINGs captured, one sentence on the dominant pattern.

## Patterns to name in the LEARNING

- "rapid-fire edit chain — checkpoint deferred at each pause until the chain ended"
- "MCP mutation not recognized as state-change at the moment of the call"
- "subagent reported 'Action logged' and parent treated it as own log"
- "proximity bias after a big log — follow-on edits felt like continuation"
- "tradeoff resolved silently in prose, never named as a DECISION"

## Notes

- Retroactive cleanup, not a substitute for inline logging. If discipline holds, this should find nothing.
- For long sessions, scan only since the last `ACTION`/`DECISION`/`LEARNING` line in today's JSONL.

## Signal Keywords

clog-it, backfill clog, missing clog, retroactive clog, clog sweep, pre-reply clog check, missed log, learning why missed
