---
name: clog-it
description: Backfill missing clog entries from the current session and capture LEARNINGs about why they were missed. Use when the user says "clog it", "/clog-it", "backfill clogs", "I missed some clogs", or at any pause where state-changing actions went unlogged.
---

# clog-it

> Canonical reference for `clog` syntax, types, and flag tables: [`clog`](../clog/SKILL.md). This skill is the retroactive-sweep wrapper.

## Trigger

**Use when:** the user says "clog it", "/clog-it", "backfill clogs", "I missed some clogs", or you notice mid-session that state-changing actions in this transcript were never logged.
**Do not use when:** logging a single named event the user just described — use [`clog`](../clog/SKILL.md) directly.
**Inputs expected:** session transcript JSONL and today's clog JSONL.
**Outputs produced:** one backfilled `clog` call per missed action, plus one paired `LEARNING` per miss naming the pattern.

## Why this exists

Inline checkpoint discipline fails under rapid-fire conditions: edit chains, MCP mutations, and subagent dispatches slip past the model's self-policing. This skill is the explicit pause that catches them.

It also drives the meta-improvement loop: each miss yields a `LEARNING` that names *why* the discipline failed (rapid-fire chain, MCP-not-recognized, subagent claim mistaken for parent log, etc.) so the signal lands in the JSONL for retros.

## How it works

This skill **delegates the scan to a subagent** so the parent context stays clean. The subagent reads the transcript and today's log directly, diffs them, and returns a tight punch list of `clog` commands. The parent sees only the final list, saving ~3–5K tokens per sweep on long sessions.

## Prerequisites — long sessions

> **If the session is longer than ~30 minutes, run `/compact` before invoking this skill.**

The scout subagent reads the full transcript. A long session transcript can push the subagent over its own context limit, producing:
```
Context limit reached · /compact or /clear to continue
```

Fix: run `/compact` in the parent session first, then re-invoke `/clog-it`. Compaction shrinks the visible transcript without losing log entries.

If `/compact` is not practical mid-task, use the `--since` workaround: narrow the scout prompt to only scan after a cutoff time (e.g. "scan only tool calls after 12:04"). Pass this as an explicit instruction in Step 2's prompt — the scout will skip the bulk of the transcript and return only the tail's misses.

## Steps

1. **Resolve paths.** Compute:
   - **Session transcript** (Claude Code): `$HOME/.claude/projects/$(pwd | sed 's|/|-|g')/${CLAUDE_SESSION_ID}.jsonl`. Other tools encode the path differently — see your tool's docs.
   - **Today's log**: read `log_root` and `log_subdir` from `~/.config/clog/config.yaml`, then `<log_root>/<log_subdir>/$(date +%Y%m%d).jsonl`.

   If `$CLAUDE_SESSION_ID` is unset or the transcript file is missing, fall back to inline scan (legacy behavior).

2. **Dispatch the scout subagent** via your tool's Agent / Task interface (in Claude Code: `subagent_type=general-purpose`). Pass this prompt, substituting the two paths:

   ````
   You are the clog-it scout. Read these two JSONL files and return a punch
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

## Patterns to name in the LEARNING

The retro loop reads these — vague signals get ignored. Name the *pattern*, not the symptom:

- "rapid-fire edit chain — checkpoint deferred at each pause until the chain ended"
- "MCP mutation not recognized as state-change at the moment of the call"
- "subagent reported 'Action logged' and parent treated it as own log"
- "proximity bias after a big log — follow-on edits felt like continuation"
- "tradeoff resolved silently in prose, never named as a DECISION"

## Notes

- Retroactive cleanup, not a substitute for inline logging. If discipline holds (Ledger persona + `post-edit-log-check.sh` hook), this sweep should find nothing.
- The subagent absorbs the per-candidate analysis. Parent context only sees the final bash block.
- For long sessions, the scout can scan only since the last `ACTION` / `DECISION` / `LEARNING` line in today's JSONL.

## Signal Keywords
<!-- Comma-separated terms the skills collector uses to attribute learnings to this skill -->
clog-it, backfill clog, missing clog, retroactive clog, clog sweep, pre-reply clog check, missed log, learning why missed
