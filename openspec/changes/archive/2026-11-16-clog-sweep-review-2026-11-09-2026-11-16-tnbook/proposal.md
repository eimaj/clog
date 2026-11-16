## Why

Two gaps in `clog-sweep` leave real work unlogged without anyone noticing. First, the scout's state-changer list names only Edit/Write and MCP mutations and says to skip `git commit/push/gh pr create` as auto-logged, but `gh pr merge` is not auto-logged and is not on the list either, so merges are never flagged. Second, Step 1 resolves its day and log helpers from the sibling `clog-sweep-sessions` skill; when that skill is not installed under `~/.claude/skills` (as this week, so /pm-end and /pa-eod swept only the current session) the skill falls back to a single-session inline scan without telling the user, so multi-day gaps are silently missed.

## What Changes

- Add `gh pr merge` (and other Bash-run mutations that no hook logs) to the scout's state-changer list in both modes, and narrow the "auto-logged" skip list to what `post-action-log.sh` really covers.
- When `clog-sweep-sessions` helpers cannot be resolved, `clog-sweep` states that it fell back and which days it could not check, instead of falling back silently.
- Out of scope: installing the `clog-sweep-sessions` symlink (an environment step for Jamie) and extending the `post-action-log.sh` hook to log merges (a separate hooks change).

## Impact

- Affected specs: session-sweep
- Affected code: `skills/clog-sweep/SKILL.md` (scout prompts in Mode A and Mode B, Step 1 fallback line)
