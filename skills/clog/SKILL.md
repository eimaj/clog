---
name: clog
description: Log a meaningful action, decision, PR, or learning to the session JSONL log. Use when the user says "clog this", "log this", "log a decision/action/PR".
model: haiku
---

# clog

## Trigger

**Use when:** the user says "clog this", "log this", "log a decision", "log an action", "log a PR".
**Also used as:** canonical interface reference for clog types, flags, and usage.
**Do not use when:** reading log contents or backfilling retroactively — use `clog-it` for sweeps.

## Command

```bash
clog <TYPE> "<summary>" [--agent NAME] [--repo NAME] [--session ID] \
     [--model NAME] [--file PATH] [--family FAMILY] [--kpi KPI] \
     [--date YYYY-MM-DD]
```

**Finding the binary:** `clog` must be on PATH, or set `$CLOG_CLI_PATH` (written to `~/.config/clog/config.yaml` by `setup.sh`). Use whichever resolves:

```bash
CLOG="${CLOG_CLI_PATH:-clog}"
"$CLOG" ACTION "did the thing"
```

Log file location: `<log_root>/<log_subdir>/YYYYMMDD.jsonl` as configured in `~/.config/clog/config.yaml`.

## Types

| Type | When to use |
|------|-------------|
| `ACTION` | Non-code state change: agent dispatched, tool called, file moved, API call made |
| `DECISION` | A tradeoff resolved: approach chosen, naming decided, scope set |
| `CODE` | File edited or created that changes runtime behavior |
| `PR` | Pull request opened, updated, or merged |
| `COMMIT` | Git commit landed (auto-logged by `post-action-log.sh`) |
| `REPO` | Repo-level event: git init, clone, archive |
| `FOLLOWUP` | Something to revisit: anomaly noticed, deferred decision, open question |
| `LEARNING` | Finding that changes future behavior: prompt gap, pattern named, correction (agent meta-feedback) |
| `LESSON` | Concept the user learned through deliberate study: idiom understood, pattern recognized. Use during structured learning. |

## `--family` values (LEARNING only)

| Family | When |
|--------|------|
| `general` | Cross-cutting finding |
| `skills` | Finding about a skill file |
| `tooling` | Finding about a tool API or hook |
| `interactive` | Finding about live session discipline |

Custom families defined in your `~/.config/clog/config.yaml` are also valid.

## `--kpi` values (LEARNING only)

| KPI | When |
|-----|------|
| `token_waste` | Large context consumed for something discarded |
| `failure` | Discipline known but not followed |
| `prompt_gap` | Skill didn't remind agent of a needed rule |
| `effective` | Pattern worked especially well |
| `format_issue` | Output format wrong, causing parse failures |

## `--agent` values

Use the name of the agent role producing the entry: `orchestrator`, `writer`, `reviewer`, `retro`, `planner`, or any agent name you've configured in `~/.config/clog/config.yaml`. Omit when logging from the base interactive session.

## Examples

```bash
clog ACTION "dispatch clog-keeper after planning burst" --agent orchestrator
clog DECISION "use yq with grep/sed fallback — avoids mandatory dep"
clog CODE "add session fallback chain in bin/clog" --file bin/clog
clog LEARNING "rapid-fire edit chain — checkpoint deferred until end" \
     --family interactive --kpi failure
clog LESSON "Go interfaces are structural — implementation is implicit, no 'implements' keyword"
clog FOLLOWUP "investigate whether Cursor exposes hooks API"
```

## Signal Keywords

clog, log this, log a decision, log an action, log a PR, clog entry, JSONL log, session log
