---
name: clog-gaps
description: Scan session transcript and JSONL for unlogged state-changes, missing --kpi on LEARNINGs, and type/summary mismatches. Use when the user says "clog gaps", "check my log", or "find missing entries".
model: haiku
---

# clog-gaps

> For type definitions and logging rules, see [`config/rules.md`](../../config/rules.md).

## Trigger

**Use when:** the user says "clog gaps", "check my log", "find missing entries", "audit my log", or at the start of an EOD wrap.
**Accepts:** optional date argument. Default = today.

## Command

```bash
# Today
clog-gaps

# Specific date
clog-gaps 2026-05-22
```

Output: `<reports_root>/gaps/YYYY-MM-DD.md`

## Steps

1. **Load today's JSONL** — read all entries from the configured log path.

2. **Scan the current session transcript** for state-changers not already in the log:
   - `Edit` / `Write` / `NotebookEdit` calls → `CODE` candidates
   - MCP mutations (Jira, Slack, Confluence, etc.) → `ACTION` candidates
   - Subagent dispatches that produced artifacts → `ACTION` candidates
   - Planning tradeoffs visible in prose → `DECISION` candidates

3. **Diff candidates against existing entries** — drop entries that already exist (match by type + rough summary).

4. **Flag quality issues in existing entries**:
   - `LEARNING` entries missing `--kpi` flag
   - Entries with summaries under 20 characters or containing vague patterns ("did stuff", "updated", "progress" alone)
   - `DECISION` entries that look like `ACTION` (no tradeoff language) or vice versa

5. **Write the report** to `<reports_root>/gaps/YYYY-MM-DD.md`.

   Report structure:
   ```markdown
   # Log Gaps — YYYY-MM-DD

   ## Missing Entries (N)
   1. [ACTION] dispatch planner for phase 3
      `clog ACTION "dispatch planner for phase 3" --agent orchestrator`

   2. [CODE] add session fallback chain in bin/clog
      `clog CODE "add session fallback chain in bin/clog" --file bin/clog`

   ## Quality Issues (N)
   1. LEARNING at HH:MM missing --kpi: "some summary"
      → Add: `--kpi prompt_gap` (or choose from rules.md)

   2. Vague summary at HH:MM: "updated file"
      → Proposed: "update config loader to handle missing yq gracefully"
   ```

6. **If in-session**: offer to run `clog-it` for immediate backfill of missing entries.

7. **Print the report path** and gap counts to the user.

## Notes

- This skill identifies gaps; `clog-it` backfills them. Both are often used together.
- The report is advisory. No entries are logged or changed automatically.

## Signal Keywords

clog-gaps, log gaps, missing entries, audit log, check my log, unlogged actions, log quality
