---
name: clog-day
description: Generate a daily markdown report from today's JSONL log. Use when the user says "clog day", "daily report", or "summarize today's log".
model: haiku
---

# clog-day

> For type definitions and logging rules, see [`config/rules.md`](../../config/rules.md).

## Trigger

**Use when:** the user says "clog day", "daily report", "what did I log today", or names a specific date.
**Accepts:** optional date argument in `YYYY-MM-DD` format. Default = today.

## Command

```bash
# Today
clog-day

# Specific date
clog-day 2026-05-22
```

Output: `<reports_root>/day/YYYY-MM-DD.md`

## Steps

1. **Resolve the target date** — use the argument if provided, else today's date.

2. **Read the JSONL file** for that date:
   ```bash
   jq -cnR '[inputs | . as $l | try fromjson catch ("clog: skipped unparseable line: " + $l + "\n" | stderr | empty)] | sort_by(.time)[]' "${CLOG_LOG_ROOT}/${CLOG_LOG_SUBDIR}/$(date -d "$DATE" +%Y%m%d 2>/dev/null || date +%Y%m%d).jsonl"
   ```
   If the file doesn't exist, report: "No log entries for `<date>`." A truncated line is skipped with a `clog: skipped unparseable line` message on stderr; the other entries still print, so mention the skipped line in the report.

   Entries are in write order, not time order: a backfilled entry (`--time`) lands at the end of the file with an earlier `time`. Every command below sorts by `time` first; `sort_by` is stable, so equal times keep file order.

3. **Group entries by type** using `jq`:
   ```bash
   jq -cnR '[inputs | . as $l | try fromjson catch ("clog: skipped unparseable line: " + $l + "\n" | stderr | empty)] | sort_by(.time) | group_by(.type) | map({type: .[0].type, entries: .})' <log_file>
   ```

4. **Write the report** to `<reports_root>/day/YYYY-MM-DD.md`. Create parent directories if needed.

   Report structure:
   ```markdown
   # Daily Log — YYYY-MM-DD

   ## Summary
   | Type | Count |
   |------|-------|
   | ACTION | N |
   | DECISION | N |
   ...

   ## Actions
   - HH:MM — summary [repo, agent if present]

   ## Decisions
   - HH:MM — summary

   ## Code Changes
   - HH:MM — summary [file if present]

   ## Learnings
   - HH:MM — summary [family, kpi if present]

   ## Commits
   - HH:MM — summary [repo, commit SHA if present]

   ## Pull Requests
   - HH:MM — summary

   ## Followups
   - HH:MM — summary
   ```

5. **Print the report path** and the entry count to the user.

## Signal Keywords

clog-day, daily report, today's log, log summary, what did I log, day report
