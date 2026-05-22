---
name: clog-week
description: Aggregate 7 daily JSONL files into a weekly markdown report. Use when the user says "clog week", "weekly report", or "summarize this week's log".
model: haiku
---

# clog-week

> For type definitions and logging rules, see [`config/rules.md`](../../config/rules.md).

## Trigger

**Use when:** the user says "clog week", "weekly report", "what did I log this week", or names a specific week.
**Accepts:** optional date argument (any date within the target week). Default = current week.

## Command

```bash
# Current week
clog-week

# Week containing a specific date
clog-week 2026-05-19
```

Output: `<reports_root>/week/YYYY-W##.md` (ISO week number)

## Steps

1. **Identify the week's 7 files** (Monday through Sunday of the week containing the target date):
   ```bash
   # Get Monday of the week
   WEEK_START=$(date -d "last monday" +%Y-%m-%d 2>/dev/null || date -v-monday +%Y-%m-%d)
   ```
   Collect files: `<log_dir>/YYYYMMDD.jsonl` for each day Mon–Sun. Skip missing files silently.

2. **Aggregate across all available files**:
   ```bash
   jq -rs '[.[] | select(type == "object")]' <file1> <file2> ... <fileN>
   ```

3. **Compute the ISO week number**:
   ```bash
   date +%G-W%V  # e.g. 2026-W21
   ```

4. **Write the report** to `<reports_root>/week/YYYY-W##.md`.

   Report structure:
   ```markdown
   # Weekly Log — YYYY-W## (Mon DD – Sun DD)

   ## Velocity
   | Type | Count |
   |------|-------|
   | ACTION | N |
   ...
   | **Total** | **N** |

   ## Top Decisions
   *(top 5–10 DECISION entries by recency)*

   - YYYY-MM-DD HH:MM — summary [repo if present]

   ## Learnings Rollup
   *(LEARNING entries grouped by family + kpi)*

   ### interactive / failure
   - ...

   ### skills / prompt_gap
   - ...

   ## Open Followups
   *(all FOLLOWUP entries from the week)*

   - YYYY-MM-DD HH:MM — summary
   ```

5. **Print the report path**, total entry count, and day coverage (e.g. "5 of 7 days had entries").

## Signal Keywords

clog-week, weekly report, this week's log, week summary, log week, weekly summary
