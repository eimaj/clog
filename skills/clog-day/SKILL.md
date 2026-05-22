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
   jq -r '.' "${CLOG_LOG_ROOT}/${CLOG_LOG_SUBDIR}/$(date -d "$DATE" +%Y%m%d 2>/dev/null || date +%Y%m%d).jsonl" 2>/dev/null
   ```
   If the file doesn't exist, report: "No log entries for `<date>`."

3. **Group entries by type** using `jq`:
   ```bash
   jq -s 'group_by(.type) | map({type: .[0].type, entries: .})' <log_file>
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
