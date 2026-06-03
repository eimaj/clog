---
name: clog
description: Log a meaningful action, decision, PR, or learning to the session JSONL log. Use when the user says "clog this", "log this", "log a decision/action/PR".
model: haiku
---

# clog

## Trigger

**Use when:** the user says "clog this", "log this", "log a decision", "log an action", "log a PR".
**Also used as:** canonical interface reference for clog types, flags, and usage.
**Do not use when:** reading log contents or backfilling retroactively — use [`clog-sweep`](../clog-sweep/SKILL.md) for sweeps.

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

## Type / flag reference

For type definitions (`ACTION`, `DECISION`, `CODE`, `PR`, `COMMIT`, `REPO`, `FOLLOWUP`, `LEARNING`, `LESSON`), `--family` values, `--kpi` values, when-to-log rules, and anti-patterns:

→ **[`config/rules.md`](../../config/rules.md)** — single source of truth.

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
