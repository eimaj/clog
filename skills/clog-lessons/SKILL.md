---
name: clog-lessons
description: Read LEARNING entries since last lessons report, cluster by family+kpi, and propose skill edits as inline diffs. Use when the user says "clog lessons", "review learnings", or "what should I improve".
model: haiku
---

# clog-lessons

> For type definitions and logging rules, see [`config/rules.md`](../../config/rules.md).

## Trigger

**Use when:** the user says "clog lessons", "review my learnings", "what should I fix in my skills", or at end-of-week retro time.
**Inputs:** LEARNING entries in JSONL since the last lessons report.
**Outputs:** `<reports_root>/lessons/YYYY-MM-DD.md` with clustered findings and **proposed** skill edits as inline diffs. Never auto-applies edits.

## Command

```bash
clog-lessons
```

## Steps

1. **Find the last lessons report date**:
   ```bash
   ls -1 <reports_root>/lessons/*.md 2>/dev/null | sort | tail -1
   ```
   If no prior report exists, use 30 days ago as the lookback window.

2. **Collect LEARNING entries** since that date across all JSONL files in the log directory:
   ```bash
   jq -rs '[.[] | select(.type == "LEARNING")]' <log_dir>/YYYYMMDD.jsonl ...
   ```

3. **Cluster by `family` + `kpi`**. Entries with no `family` or `kpi` go in an "Uncategorized" cluster.

4. **For each cluster**:
   - Count entries
   - Identify the dominant pattern from summary text
   - If the cluster implies a skill fix (e.g., `kpi: prompt_gap` with `family: skills`), identify the relevant skill file and propose an edit

5. **Write the report** to `<reports_root>/lessons/YYYY-MM-DD.md`.

   Report structure:
   ```markdown
   # Lessons Report — YYYY-MM-DD
   *Covering YYYY-MM-DD through YYYY-MM-DD — N LEARNING entries*

   ## interactive / failure (N entries)
   Pattern: rapid-fire edit chains skipping checkpoints
   Entries:
   - HH:MM YYYY-MM-DD — summary

   Proposed skill edit — `skills/clog/SKILL.md`:
   \`\`\`diff
   - ## Signal Keywords
   + ## Pre-reply Checkpoint
   + Before every reply after a state-changing tool call, name the action and log it.
   +
   + ## Signal Keywords
   \`\`\`

   ## skills / prompt_gap (N entries)
   ...
   ```

6. **End with a review note**:
   > Review each proposed diff above and apply manually to your skill files. Do not auto-apply.

7. **Print the report path** and cluster summary to the user.

## Notes

- Proposed diffs are illustrative, not syntactically precise. Review before applying.
- The report is not a commit or a skill change — it is a proposal only.
- If no LEARNING entries exist since the last report, print: "No new LEARNING entries since `<date>`. Nothing to cluster."

## Signal Keywords

clog-lessons, review learnings, skill improvements, lessons report, what to improve, learning retro, skill retro
