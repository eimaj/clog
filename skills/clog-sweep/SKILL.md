---
name: clog-sweep
description: Sweep the current session for unlogged state-changes. Two modes — audit-only ("clog gaps"/"check my log"/"find missing entries") scans and flags gaps without backfilling; backfill ("clog it"/"backfill clogs") scans and backfills with paired LEARNINGs. Use when the user says "clog it", "backfill clogs", "clog gaps", "check my log", "find missing entries", "audit my log", or at any pause where state-changing actions may have gone unlogged.
model: haiku
---

# clog-sweep

> For type definitions, `--family`/`--kpi` tables, and when-to-log rules: [`config/rules.md`](../../config/rules.md). This skill is the retroactive-sweep wrapper — it does not redefine the interface.

## Trigger

**Use when:** the user says any of:
- "clog it", "/clog-it", "backfill clogs", "I missed some clogs" → **[backfill mode](#mode-b--backfill)**
- "clog gaps", "check my log", "find missing entries", "audit my log", or at EOD wrap start → **[audit-only mode](#mode-a--audit-only)**
- "clog it --approval-only", "check before backfilling", "show what you'd log first" → **[approval mode](#mode-b--backfill)** (scout runs, shows punch list, waits for confirmation before executing)
- You notice mid-session that state-changing actions were never logged → **backfill mode**

**Do not use when:** logging a single named event the user just described — use [`clog`](../clog/SKILL.md) directly.
**Inputs expected:** current session transcript and today's JSONL log.

## Why this exists

Inline checkpoint discipline fails under rapid-fire conditions: edit chains, MCP mutations, and subagent dispatches slip past the model's self-policing. This skill is the explicit pause that catches them.

It also drives the meta-improvement loop: each miss yields a `LEARNING` that names *why* the discipline failed so the signal lands in the JSONL for retros.

## How it works

This skill **delegates the scan to a subagent** so the parent context stays clean. The subagent reads the transcript and today's log directly, diffs them, and returns a tight punch list. The parent sees only the final result, saving ~3–5K tokens per sweep on long sessions.

## Prerequisites — long sessions

> **If the session is longer than ~30 minutes, run `/compact` before invoking this skill.**

The scout subagent reads the full transcript. A long session transcript can push the subagent over its own context limit. Fix: run `/compact` first, then re-invoke. If `/compact` is not practical mid-task, narrow the scout to scan only after a cutoff time (e.g. "scan only tool calls after 12:04").

---

## Mode A — Audit only

Use when: "clog gaps", "check my log", "find missing entries", "audit my log", or at EOD wrap start.

### Steps

1. **Resolve paths** — same as [Mode B Step 1](#steps-1).

2. **Dispatch the scout subagent** (in Claude Code: `subagent_type=general-purpose`) with this prompt, substituting the two paths:

   ````
   You are the clog-sweep auditor. Read these two JSONL files and return a gaps
   report. Do NOT emit clog commands or backfill anything — audit only.

   Session transcript: <TRANSCRIPT_PATH>
   Today's clog log:   <LOG_PATH>

   State-changers to look for: Edit / Write / MultiEdit / NotebookEdit calls,
   mutating MCP calls (createJiraIssue, editJiraIssue, createConfluencePage,
   updateConfluencePage, slack_send_message, etc.), Task/Agent dispatches that
   produced artifacts. Skip git commit/push/gh pr create (auto-logged).

   For each state-changer not matched in the log (±60s window, type + summary
   keywords), list it as a missing entry with a proposed clog command.

   Also flag quality issues in existing entries:
   - LEARNING entries missing --kpi
   - Summaries under 20 characters or containing vague patterns ("did stuff",
     "updated", "progress" alone)
   - DECISION entries with no tradeoff language; ACTION entries that look like DECISIONs

   Output format:
   ## Missing Entries (N)
   1. [ACTION] dispatch planner for phase 3
      `clog ACTION "dispatch planner for phase 3" --agent orchestrator`

   ## Quality Issues (N)
   1. LEARNING at HH:MM missing --kpi: "some summary"
      → Add: `--kpi prompt_gap`
   ````

3. **Write the report** to `<reports_root>/gaps/YYYY-MM-DD.md`.

4. **Print the report path** and gap counts to the user.

5. **Offer to switch to backfill mode** for immediate remediation.

---

## Mode B — Backfill

Use when: "clog it", "backfill clogs", "I missed some clogs", or you notice mid-session gaps.

### Steps

> **Approval mode:** if the trigger was "clog it --approval-only" or "check before backfilling",
> run Steps 1–2 as normal, then **stop and show the punch list to the user before executing**.
> Do not run the bash block until the user replies with "go", "yes", "apply", or similar.
> Once confirmed, continue with Step 3 as normal.

1. **Resolve paths.** Compute:
   - **Session transcript** (Claude Code): `$HOME/.claude/projects/$(pwd | sed 's|/|-|g')/${CLAUDE_SESSION_ID}.jsonl`. Other tools encode the path differently — see your tool's docs.
   - **Today's log**: read `log_root` and `log_subdir` from `~/.config/clog/config.yaml`, then `<log_root>/<log_subdir>/$(date +%Y%m%d).jsonl`.

   If `$CLAUDE_SESSION_ID` is unset or the transcript file is missing, fall back to inline scan (legacy behavior).

2. **Dispatch the scout subagent** (in Claude Code: `subagent_type=general-purpose`) with this prompt, substituting the two paths:

   ````
   You are the clog-sweep scout. Read these two JSONL files and return a punch
   list of missing clog entries.

   Session transcript: <TRANSCRIPT_PATH>
   Today's clog log:   <LOG_PATH>

   Rules:
   - State-changers in the transcript: Edit / Write / MultiEdit / NotebookEdit,
     mutating MCP calls (createJiraIssue, editJiraIssue, transitionJiraIssue,
     createConfluencePage, updateConfluencePage, slack_send_message,
     slack_schedule_message, addCommentToJiraIssue, etc.), Task/Agent
     dispatches that produced artifacts. Skip git commit/push/gh pr create
     (auto-logged by post-action-log.sh).
   - For each state-changer, check today's log for a matching entry within
     ±60s of the tool call using type + summary keywords. If no match within
     that window, it's a miss.
   - For each miss, pair the backfilled clog call with a LEARNING naming the
     pattern that defeated the discipline (rapid-fire chain, MCP not
     recognized as state-change, proximity bias after a big log, tradeoff
     resolved silently in prose, subagent log treated as parent log, etc.).

   Return ONLY a fenced bash block with one `clog` call per miss, each
   immediately followed by one paired `clog LEARNING --family interactive
   --kpi failure` (or --kpi prompt_gap if the gap looks like a skill issue).
   No prose. Max 200 lines.

   Example output shape:
   ```bash
   clog CODE "add validation field example to README" --file README.md
   clog LEARNING "doc-edit chain — checkpoint deferred to end of review" \
        --family interactive --kpi failure
   clog ACTION "merged feat branch to main via cherry-pick"
   clog LEARNING "merge step felt like git plumbing, not a state change" \
        --family interactive --kpi failure
   ```
   ````

3. **Execute the returned bash block as-is.** Auto-apply — do not pause for approval. The bash block is the entire artifact; running it backfills the misses and logs the paired LEARNINGs in one pass.

4. **Summarize** to the user in one line: `N backfilled, dominant pattern: <one short phrase>`.

---

## Patterns to name in the LEARNING

The retro loop reads these — vague signals get ignored. Name the *pattern*, not the symptom:

- "rapid-fire edit chain — checkpoint deferred at each pause until the chain ended"
- "MCP mutation not recognized as state-change at the moment of the call"
- "subagent reported 'Action logged' and parent treated it as own log"
- "proximity bias after a big log — follow-on edits felt like continuation"
- "tradeoff resolved silently in prose, never named as a DECISION"

## Notes

- Retroactive cleanup, not a substitute for inline logging. If discipline holds (Ledger persona + `post-edit-log-check.sh` hook), this sweep should find nothing.
- The subagent absorbs the per-candidate analysis. Parent context only sees the final list.
- For long sessions, the scout can scan only since the last `ACTION` / `DECISION` / `LEARNING` line in today's JSONL.

## Signal Keywords
<!-- Comma-separated terms the skills collector uses to attribute learnings to this skill -->
clog-sweep, clog-it, clog-gaps, backfill clog, missing clog, retroactive clog, clog sweep, pre-reply clog check, missed log, learning why missed, log gaps, missing entries, audit log, check my log, unlogged actions, log quality
