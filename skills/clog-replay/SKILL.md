---
name: clog-replay
description: Reconstruct a natural-language prompt approximating what was done in a past session, using the JSONL clog logs as a source. Use when the user says "replay a past session", "what did I do last week on X", "help me redo what I did around date Y", "reconstruct a prompt for Z", or "what was the prompt for that task".
model: sonnet
---

# clog-replay

> For log schema and type definitions: [`config/rules.md`](../../config/rules.md). This skill searches the daily JSONL logs, clusters context around a target entry, and reconstructs a reusable prompt — it does not create new log entries.

## Trigger

**Use when:**
- "replay a past session" / "reconstruct what I did on X"
- "what did I do around [date] for [project/repo]"
- "help me redo the [skill/task] I ran last [week/month]"
- "what was the prompt for that task" / "draft a prompt based on past work"
- User wants a ready-to-paste prompt that approximates a prior action

**Do NOT use when:**
- The user wants to audit or backfill *current* session logs → use [`clog-sweep`](../clog-sweep/SKILL.md)
- The user wants to create a new log entry → use [`clog`](../clog/SKILL.md)
- The user wants a summary of what happened today → use [`clog-day`](../clog-day/SKILL.md)

**Inputs expected:** User's memory of what happened (date, repo, keywords). Nothing else is required — the skill fills gaps interactively.

**Outputs:**
- A fenced `## Replay Prompt` block in Persona + Context + Task structure, ready to paste into Claude Code
- Optionally: the name of the target skill to invoke it against

> **Last Reviewed:** 2026-06-04
> **Refresh Rule:** Re-review if log schema gains new required fields, or if the daily log path changes from `~/Code/_notes/logs/claude/YYYYMMDD.jsonl`.

---

## Steps

### Step 1 — Gather search hints

Before asking, log that the skill has been invoked:

```bash
~/.claude/hooks/clog.sh ACTION "clog-replay: skill invoked — prompting user for date range, repo, and keyword hints"
```

Ask the user the following questions (all in one message — do not split into separate turns):

1. **Date range** — "What date or range are you thinking? (e.g. 'last week', 'around May 20th', 'yesterday', 'sometime in April')"
2. **Repo or project** — "Do you remember which repo or project this was in? (optional but helps narrow results)"
3. **Keywords** — "Any words you remember from what was done? Skill name, task description, agent used, file touched — anything."

Wait for all three answers before proceeding.

After collecting all three answers, log the collected hints (substitute actual values):

```bash
~/.claude/hooks/clog.sh ACTION "clog-replay: hints collected — range=<range> repo=<repo|unspecified> keyword=<keywords>"
```

---

### Step 2 — Build and run the jq search

From the user's answers:

1. **Resolve the file glob.** Daily logs live at `~/Code/_notes/logs/claude/YYYYMMDD.jsonl`. Map the date range to a shell glob:
   - "yesterday" → `$(date -v-1d +%Y%m%d).jsonl`
   - "last week" → `202506*.jsonl` (or a tighter range if you can infer it)
   - "around May 20th" → `20250518.jsonl 20250519.jsonl 20250520.jsonl 20250521.jsonl 20250522.jsonl`
   - Specific date → `YYYYMMDD.jsonl`

2. **Build the jq filter.** Before building, log the filter decision:

   ```bash
   ~/.claude/hooks/clog.sh DECISION "clog-replay: building jq filter — keyword='<keyword>' repo=<repo|unscoped> date-files=<file-glob>"
   ```

   Always filter on `.summary` prose. Optionally add `.repo` and `.agent` if the user provided them. Use case-insensitive regex:

   ```bash
   jq -c 'select(.summary | test("KEYWORD"; "i"))' \
     ~/Code/_notes/logs/claude/YYYYMMDD*.jsonl \
     | head -30
   ```

   Multi-keyword example (AND):
   ```bash
   jq -c 'select((.summary | test("cmp"; "i")) and (.summary | test("playwright"; "i")))' \
     ~/Code/_notes/logs/claude/202505*.jsonl \
     | head -30
   ```

   With repo filter:
   ```bash
   jq -c 'select((.repo == "tn-mono") and (.summary | test("migration"; "i")))' \
     ~/Code/_notes/logs/claude/202506*.jsonl \
     | head -30
   ```

3. **Show the command to the user before running.** Say: "Here's the search command — let me know if you want to adjust anything before I run it." Log before running:

   ```bash
   ~/.claude/hooks/clog.sh ACTION "clog-replay: running search — command shown to user, awaiting confirmation"
   ```

   Then run it. After results return, log the outcome (substitute actual count):

   ```bash
   ~/.claude/hooks/clog.sh ACTION "clog-replay: search returned N entries — proceeding to candidate list"
   ```

4. If the search returns 0 results, log before broadening:

   ```bash
   ~/.claude/hooks/clog.sh ACTION "clog-replay: 0 results for '<keyword>' in <range> — broadening: <what change was made>"
   ```

   Then broaden by: removing the repo filter, widening the date range by ±3 days, or splitting compound keywords. Tell the user what you're doing.

---

### Step 3 — Present candidates

Before presenting, log the candidate count and provenance:

```bash
~/.claude/hooks/clog.sh ACTION "clog-replay: presenting N candidates to user — [TYPE] entries from <date> in <repo>"
```

Show the filtered entries as a numbered list. Format each line as:

```
N. [TYPE] [HH:MM] [repo] summary
```

Example:
```
1. [ACTION] [14:22] [tn-mono] dispatch cmp-audit agent for phase 2
2. [CODE]   [14:35] [tn-mono] add PlaywrightFixtures base class to cmp package
3. [COMMIT] [14:51] [tn-mono] chore(cmp): scaffold playwright fixture layer
```

Then ask: "Which of these looks like what you want to replay? Pick a number, or say 'none' if none match."

After the user picks, log the selection before proceeding:

```bash
~/.claude/hooks/clog.sh DECISION "clog-replay: user selected entry N — [TYPE HH:MM repo] '<summary excerpt>'"
```

---

### Step 4 — Cluster context

Once the user picks an entry:

1. Note the chosen entry's `time` field (HH:MM:SS) and its source file (YYYYMMDD.jsonl).
2. Before fetching context, log the operation:

   ```bash
   ~/.claude/hooks/clog.sh ACTION "clog-replay: fetching ±5 context entries around <HH:MM:SS> in <YYYYMMDD>.jsonl"
   ```

3. Fetch ±5 entries by time proximity from the same file:

   ```bash
   jq -c '.' ~/Code/_notes/logs/claude/YYYYMMDD.jsonl \
     | awk -v target="HH:MM:SS" '
         { lines[NR] = $0 }
         $0 ~ target { center = NR }
         END {
           start = (center - 5 > 0) ? center - 5 : 1
           end   = (center + 5 <= NR) ? center + 5 : NR
           for (i = start; i <= end; i++) print lines[i]
         }
       '
   ```

   Alternatively, use `jq` to select entries within a 10-minute window around the target time.

4. After the cluster is built, log its shape:

   ```bash
   ~/.claude/hooks/clog.sh ACTION "clog-replay: cluster built — N entries, <HH:MM>–<HH:MM>, types: <list>"
   ```

5. Display the cluster as a numbered list in the same `[TYPE] [HH:MM] [repo] summary` format, with the chosen entry highlighted (e.g. `→ 3. [CODE] ...`).

6. Ask: "Is this the right context? Is anything missing from the cluster, or does a different entry look more relevant?"

   Wait for confirmation before proceeding.

   After user confirms, log the decision to proceed:

   ```bash
   ~/.claude/hooks/clog.sh DECISION "clog-replay: cluster confirmed by user — proceeding to prompt reconstruction"
   ```

---

### Step 5 — Reconstruct the prompt

Before extracting fields, log the reconstruction start:

```bash
~/.claude/hooks/clog.sh ACTION "clog-replay: reconstructing prompt from cluster — extracting skill/agent, repo, what-was-done, artifacts"
```

From the confirmed cluster, extract the following fields:

| Field | Source |
|---|---|
| **Skill / agent** | `.agent` field if present; otherwise infer from summary prose (e.g. "dispatch cmp-audit" → agent = cmp-audit) |
| **Repo** | `.repo` field from any entry in the cluster |
| **What was done** | Summary prose from ACTION, CODE, COMMIT, and DECISION entries |
| **Output artifacts** | Filenames or PR numbers from CODE / COMMIT / PR entries |
| **Decision rationale** | Summary prose from DECISION entries |

Draft a prompt in the following structure:

````
## Replay Prompt

```
**Persona:** You are a [staff engineer / senior engineer / PA agent / etc.] working on [repo/project].

**Context:**
- Repo: [repo]
- Relevant prior work: [what was done, 2–4 bullet points extracted from cluster summaries]
- Artifacts produced: [files, PRs, migrations, etc. — or "unknown, see gaps below"]
- Decision made: [any DECISION entry summary — or omit if none]

**Task:**
[Imperative instruction reconstructing the original ask, written as if giving it fresh.
 Use "…" markers where inputs are unknown and must be filled in by the user.]
```
````

After extracting, log what was found and what is missing (substitute actual values):

```bash
~/.claude/hooks/clog.sh ACTION "clog-replay: extracted — agent=<value|unknown> repo=<value|unknown> artifacts=<list|none> gaps=<N missing fields>"
```

Mark any unknowns explicitly with `[FILL IN: ...]` rather than inventing values.

---

### Step 6 — Fill gaps with user

For each `[FILL IN: ...]` marker in the reconstructed prompt, ask the user ONE question at a time. Do not ask multiple gap questions in a single turn.

Before asking each gap question, log that the gap has been surfaced:

```bash
~/.claude/hooks/clog.sh DECISION "clog-replay: gap surfaced — missing '<field>' — asking user"
```

Examples:
- "The cluster shows a Playwright test was run, but I don't have the specific test path. Do you remember which test file or suite was targeted?"
- "The COMMIT entry shows a migration was applied, but the specific table name wasn't logged. Do you recall which table or schema was involved?"
- "The agent field is missing — do you remember which skill or agent you invoked? (e.g. `/dev-sa`, `/orchestrate`, a named subagent)"

After each user answer, log the resolved value immediately before updating the draft:

```bash
~/.claude/hooks/clog.sh ACTION "clog-replay: gap resolved — '<field>' = '<user answer>'"
```

Then update the draft prompt and check for remaining gaps. Repeat until all `[FILL IN: ...]` markers are resolved or the user says to proceed anyway.

---

### Step 7 — Deliver

Before outputting the final prompt, log that reconstruction is complete:

```bash
~/.claude/hooks/clog.sh ACTION "clog-replay: prompt reconstruction complete — N gaps filled, skill=<name|unknown>, delivering replay prompt"
```

Output the final prompt as a fenced code block under the heading `## Replay Prompt`.

Follow the heading with a one-line note:

> **Where to use this:** Paste into Claude Code and invoke with `/[skill-name]` (if determinable), or paste directly as a prompt.

If the skill or agent is determinable from the cluster, name it explicitly:
> **Where to use this:** Paste into Claude Code and invoke with `/dev-sa`.

If not determinable, say:
> **Where to use this:** Paste into Claude Code. Skill unclear from logs — check if the task matches a known skill (e.g. `/orchestrate`, `/dev-sa`, `/clog-sweep`).

---

## Notes

- **Inputs are never stored.** The JSONL schema has no `inputs` or `args` field. Every input reconstruction is approximate — the user must validate and fill gaps.
- **`session` field is unreliable.** It appears in only ~22% of entries and uses manual slugs. Do not use it as a primary filter — it can narrow results once a candidate is found.
- **`agent` field is present ~43% of the time.** When absent, infer from summary prose (e.g. "dispatch X agent", "subagent returned", "X skill invoked").
- **Date comes from the filename, not per-entry fields.** When presenting candidates, annotate with the source filename date if the user's range spans multiple files.
- **Cluster size is a judgment call.** ±5 entries covers ~10 minutes of typical session activity. For dense sessions (many rapid edits), widen to ±10. For sparse sessions, the cluster may already show the full task.

## Signal Keywords
<!-- Comma-separated terms the skills collector uses to attribute learnings to this skill -->
clog-replay, replay session, reconstruct prompt, what did I do, redo past work, replay past session, prompt reconstruction, clog search, log replay, past session prompt, what was the prompt, approximate prompt, find old work, session recovery, log-driven prompt
