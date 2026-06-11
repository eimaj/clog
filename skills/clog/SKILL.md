---
name: clog
description: Log a meaningful action, decision, PR, or learning to the session JSONL log. Use when the user says "clog this", "log this", "log a decision", or when manually recording an event. Also the canonical reference for clog types and flags used by all action skills.
model: haiku
---

# clog

## Trigger

**Use when:** the user says "clog this", "log this", "log a decision/action/PR", or asks you to record an event manually.
**Also used as:** the canonical reference for `clog` types, flags, and usage guidance — other skills point here instead of duplicating the interface docs.
**Do not use when:** the user is asking about the log contents (use `cat ~/Code/logs/claude/YYYYMMDD.jsonl` directly), or doing a retroactive sweep for missed entries (use [`clog-sweep`](../clog-sweep/SKILL.md)).

## Type / flag reference

For type definitions (`ACTION`, `DECISION`, `CODE`, `PR`, `COMMIT`, `REPO`, `FOLLOWUP`, `LEARNING`, `LESSON`), `--family` values, `--kpi` values, when-to-log rules, and anti-patterns:

→ **[`config/rules.md`](../../config/rules.md)** — single source of truth.

## Command

```bash
clog <TYPE> "<summary>" [--agent NAME] [--repo NAME] [--session ID] \
     [--model NAME] [--file PATH] [--family FAMILY] [--kpi KPI] \
     [--date YYYY-MM-DD]
```

- `TYPE` and `<summary>` are required positional args.
- `--repo` is auto-detected from git if omitted; pass explicitly when not in a repo dir.
- `--date` is for backfill only — omit for current date.

**Finding the binary:** `clog` must be on PATH, or set `$CLOG_CLI_PATH`. Fallback:

```bash
CLOG="${CLOG_CLI_PATH:-~/.claude/hooks/clog.sh}"
"$CLOG" ACTION "did the thing"
```

## Examples

```bash
clog ACTION "Triggered Deploy Scripts: cmp → staging from Release-26.15.0" --repo textnow-web-mono
clog DECISION "Chose single bundled PR over split — refactor was cohesive" --repo textnow-web-mono
clog CODE "add session fallback chain in bin/clog" --file bin/clog
clog PR "Created PR: add clog skill — main https://github.com/Enflick/textnow-web-mono/pull/123"
clog FOLLOWUP "Deploy Scripts FAILED: cmp → staging run 24348499118" --repo textnow-web-mono
clog LEARNING "clog missing from all action skills — prompt_gap" --family skills --kpi prompt_gap
clog ACTION "Merged release branch" --repo textnow-web-mono --date 2026-04-10
```

## What gets logged

Each entry is a JSONL line written to `~/Code/logs/claude/YYYYMMDD.jsonl` and auto-committed to the `_notes` repo.

## Signal Keywords
<!-- Comma-separated terms the skills collector uses to attribute learnings to this skill -->
clog, clog.sh, log action, log decision, JSONL, session log, LEARNING, FOLLOWUP, ACTION, DECISION
