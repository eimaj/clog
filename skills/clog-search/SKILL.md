---
name: clog-search
description: Search historical clog JSONL files to answer "what did I do last week?". Use when the user wants to find past actions, decisions, code changes, or lessons from the session log by date range, keyword, repo, or type.
model: haiku
---

# clog-search

> For type definitions and logging rules, see [`config/rules.md`](../../config/rules.md).

## Trigger

**Use when:**
- "What did I do last week on X?"
- "Did I ever work on Y? When?"
- "Show me what I logged for repo Z in May"
- "What lessons did I log around the time I worked on everflow?"
- "I ran something last week — what was it and how did I do it?"

**Do NOT use when:**
- User wants today's summary → use `/clog-day` instead
- User wants a full week rollup → use `/clog-week` instead
- User is asking about future plans or open crrt tasks (no log entries exist yet)

**Inputs:**
- Date range (required — ask if missing)
- Keyword (optional but strongly recommended)
- Repo/project filter (optional)
- Entry type filter (optional — defaults to all types)

**Outputs:**
- A formatted markdown report at `${AI_NOTES_DIR:-$HOME/Code/_notes}/reports/clog-search/YYYY-MM-DD-<keyword-slug>.local.md`
- A clog ACTION entry recording the search

> Last Reviewed: 2026-06-11
> Refresh Rule: re-review if log schema gains new fields, or if config keys `log_root`/`log_subdir` in `~/.config/clog/config.yaml` are renamed.

## Steps

### Step 1 — Clarifying questions

Resolve the log directory from config first (run once; reuse `$LOG_DIR` in all subsequent steps):
```bash
_cfg="${CLOG_CONFIG:-$HOME/.config/clog/config.yaml}"
_root=$(grep '^log_root:' "$_cfg" 2>/dev/null | sed 's/log_root:[[:space:]]*//' | tr -d '"' | sed "s|\${HOME}|$HOME|;s|^~|$HOME|")
_sub=$(grep '^log_subdir:' "$_cfg" 2>/dev/null | sed 's/log_subdir:[[:space:]]*//' | tr -d '"')
LOG_DIR="${_root:-$HOME/Code/logs}/${_sub:-claude}"
```

Clog immediately upon skill invocation, before asking the user anything:
```bash
clog ACTION "clog-search: skill invoked — prompting user for date range, repo, keyword, and type filter"
```

Ask all four questions before running anything. Do not assume defaults.

```
a. Date range:   "What time period? (e.g. 'last week', 'May 20–27', 'yesterday', 'June 1–3')"
b. Scope:        "Any specific repo or project? (leave blank for all)"
c. Keyword:      "Any keywords you remember? (skill name, task name, tool, ticket ID)"
d. Type filter:  "Only certain entry types? (e.g. CODE, DECISION, LEARNING — or leave blank for all)"
```

Translate the date range to a list of `YYYYMMDD.jsonl` filenames:
```bash
ls $LOG_DIR/ | grep -E '^[0-9]{8}\.jsonl$' | sort
```

Clog immediately after collecting answers, filling in actual values — no placeholders. Do this BEFORE proceeding to Step 2:
```bash
clog ACTION "clog-search: scope confirmed — range=<range> repo=<repo|all> keyword='<keyword|none>' types=<types|all>"
# Example: "clog-search: scope confirmed — range=May20-27 repo=tn-mono keyword='everflow' types=CODE,DECISION"
```

### Step 2 — Translate to file glob + jq filter

Clog the decision to build the jq command before constructing it — fill in actual values:
```bash
clog DECISION "clog-search: building jq command — keyword='<keyword>' types=<types|all> repo=<repo|unscoped> files=<N files>"
# Example: "clog-search: building jq command — keyword='everflow' types=CODE,DECISION repo=tn-mono files=8 files"
```

Show the exact command to the user before running it. Example with keyword + type filter:

```bash
jq -c 'select(
  (.summary | test("everflow";"i")) and
  (.type == "CODE" or .type == "DECISION")
)' \
  $LOG_DIR/20260520.jsonl \
  $LOG_DIR/20260521.jsonl \
  $LOG_DIR/20260522.jsonl
```

Example with repo filter only (no keyword):

```bash
jq -c 'select(.repo == "tn-mono")' \
  $LOG_DIR/20260528.jsonl \
  $LOG_DIR/20260529.jsonl
```

Example with keyword only, all types, multi-week range:

```bash
jq -c 'select(.summary | test("playwright";"i"))' \
  $LOG_DIR/2026052*.jsonl \
  $LOG_DIR/2026060*.jsonl
```

Clog before showing the command to the user:
```bash
clog ACTION "clog-search: jq command ready — showing to user for confirmation before running"
```

Ask: "Does this look right? (y to run, or tell me how to adjust the filter)"

### Step 3 — Run the search

Execute the confirmed shell command. Count results:

```bash
<search_command> | wc -l
```

**If 0 results:**
- Clog the miss BEFORE suggesting the next attempt:
  ```bash
  clog ACTION "clog-search: 0 results for keyword=<keyword> in <range> — broadening filter to <next attempt>"
  ```
- Suggest removing the type filter first
- Then suggest broadening the keyword (e.g. partial match, different casing)
- Then suggest expanding the date range by ±2 days
- Print: "No results. Suggested next try: `<revised command>`"

**If >100 results:**
- Suggest adding a type filter (e.g. `and (.type == "CODE" or .type == "DECISION")`)
- Or narrowing the date range
- Print: "N results — consider narrowing. Suggested filter: `<revised command>`"
- Clog the volume warning with the specific count and narrowing suggestion:
  ```bash
  clog ACTION "clog-search: N results for '<keyword>' — too broad, suggesting add type filter [CODE,DECISION] or narrow date to <suggestion>"
  # Example: "clog-search: 143 results for 'playwright' — too broad, suggesting add type filter [CODE,DECISION] or narrow date to May20-24"
  ```

**If 1–100 results:** proceed to Step 4. Clog immediately, naming types seen:
```bash
clog ACTION "clog-search: N entries found for '<keyword>' in <range> — types: X CODE / Y DECISION / Z LEARNING — proceeding to format"
# Example: "clog-search: 14 entries found for 'everflow' in May20-27 — types: 6 CODE / 3 DECISION / 2 LEARNING — proceeding to format"
```

### Step 4 — Format the report

**If fewer than 30 entries:** clog before formatting, then format inline:
```bash
clog ACTION "clog-search: formatting N entries inline — no subagent needed"
```

**If 30 or more entries:** clog before dispatching, then pass raw jq output to a subagent:

Clog the dispatch before calling the subagent — name the sections:
```bash
clog ACTION "clog-search: N entries — dispatching subagent to format report sections (What Was Done / How / Lessons / Followups)"
# Example: "clog-search: 47 entries — dispatching subagent to format report sections (What Was Done / How / Lessons / Followups)"
```

```
Agent({
  subagent_type: "general-purpose",
  prompt: `You are a log analyst. Format these clog entries into a structured markdown report.

Sections required:
1. **What Was Done** — bullet list of CODE, PR, DECISION, COMMIT entries sorted chronologically.
   Format each line: \`[DATE HH:MM] [TYPE] [repo if present] summary\`
   Date comes from the filename context provided, not the entry itself.
2. **How It Was Done** — deduplicated list of unique \`agent\` field values seen in the results.
   If no agent field, note "no agent recorded".
3. **Lessons Learned** — all LEARNING entries. Group by \`family\` field if present.
4. **Open Followups** — all FOLLOWUP entries.

Raw entries (one JSON object per line):
${RAW_JQ_OUTPUT}

Date context (filenames searched): ${FILE_LIST}

Return only the formatted markdown. No preamble.`
})
```

Report format (used for both inline and subagent output):

```markdown
# clog-search Report
**Searched:** <date range> | **Keyword:** <keyword or "none"> | **Repo:** <repo or "all"> | **Types:** <types or "all">
**Results:** N entries across M days

---

## What Was Done
- [2026-05-21 09:14] CODE [tn-mono] added everflow webhook handler
- [2026-05-21 14:02] DECISION [tn-mono] chose idempotency key over dedup table — simpler rollback
- ...

## How It Was Done
- **Agents used:** orchestrate, dev-sa
- **Skills invoked:** (inferred from summary text if explicit)

## Lessons Learned
*(grouped by family if present)*
- [2026-05-22 11:30] [family: testing] Playwright flake root-caused to network timeout, not selector

## Open Followups
- [2026-05-23 16:45] follow up on AD-4831 offer rate edge case after merge
```

### Step 5 — Write report and log

1. Determine the report slug from the keyword (lowercase, hyphens, max 30 chars). If no keyword, use the repo name. If neither, use the date range (e.g. `may-20-27`).

2. Ensure the report directory exists and write the file. Clog BEFORE writing:
```bash
clog ACTION "clog-search: writing report to ${AI_NOTES_DIR:-$HOME/Code/_notes}/reports/clog-search/<slug>.local.md — N entries, keyword='<keyword>'"
# Example: "clog-search: writing report to ${AI_NOTES_DIR:-$HOME/Code/_notes}/reports/clog-search/2026-06-04-everflow.local.md — 14 entries, keyword='everflow'"
```

```bash
mkdir -p ${AI_NOTES_DIR:-$HOME/Code/_notes}/reports/clog-search
```

3. Print the path and open it:
```bash
code "$REPORT_PATH"
```

4. Clog completion — be specific about what was found, not just that a search ran:
```bash
clog ACTION "clog-search: report written — <keyword> in <range>, N entries, <X CODE / Y DECISION / Z LEARNING>, agents: <list or none>"
# Example: "clog-search: report written — everflow in May20-27, 14 entries, 6 CODE / 3 DECISION / 2 LEARNING, agents: orchestrate dev-sa"

clog FOLLOWUP "clog-search: <any unresolved question surfaced — e.g. 'AD-4831 followup still open as of May23'>"
# Only emit FOLLOWUP if the search surfaces an open thread worth tracking
```

---

## Signal Keywords

clog search, what did I do, find in logs, search my log, last week log, what did I work on, log history, past actions, when did I, how did I, find that thing I did, session history, log lookup, what was that skill, search clog
