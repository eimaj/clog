## Why

The `clog-sweep-sessions` scan step dispatches one Explore scout per session and tells it to use only Read, Grep and Glob. In practice Explore subagents do not get Grep or Glob, and real transcripts are hundreds of thousands of tokens with lines too long for Read, so on 2026-11-20 all 15 scouts of a `/pa-eod` run either stopped "BLOCKED" with no records or never finished. An empty scout result also looks like a clean session. The candidates are tool calls with a name and a timestamp, so they can be extracted exactly with jq.

## What Changes

- New `scripts/extract.sh <transcript>` turns a transcript into candidate records with jq: Edit/Write/MultiEdit/NotebookEdit calls as `CODE`, Agent/Task dispatches and mutating MCP calls as `ACTION`, and Bash calls that mutate repo or remote state as `ACTION`, applying the existing hook-logged skip rules (single `git commit`, `git push`, `gh pr create`, `gh pr merge` without `--auto`; every part of a chain checked; `git -C`/`gh -R` never skipped).
- `SKILL.md` step 2 becomes `extract.sh | localize.sh | gaps.sh`; no scout is dispatched.
- A new review step: the sweeping agent reads the short gap list, drops read-only false positives, and rewrites `summary`/`why` in plain language before backfill. It may not add records or change their type, date or time.
- `clog-sweep` (current session) drops its two general-purpose scout prompts and uses the same pipeline and review on its own transcript: Mode A turns the reviewed list into proposed commands with `backfill-cmds.sh` and runs nothing; Mode B runs them through `run-backfill.sh`. It still sweeps only the current session.

## Impact

- Affected specs: session-sweep
- Affected code: `skills/clog-sweep-sessions/scripts/extract.sh` (new), `skills/clog-sweep-sessions/SKILL.md`, `skills/clog-sweep/SKILL.md`, `tests/cli/run.sh`
