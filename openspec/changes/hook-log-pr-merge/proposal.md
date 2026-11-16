## Why

`post-action-log.sh` logs `git commit`, `gh pr create` and `git push`, but a merge made with `gh pr merge` leaves no entry, so the `clog-sweep` scouts have to flag every merge as a gap. Logging it in the hook closes the gap at the source.

## What Changes

- `post-action-log.sh` writes an `ACTION` entry `merged PR #<n> (<repo>)` for a `gh pr merge` command, with the number when one directly follows `merge` and the repo suffix when the repository resolves.
- The `clog-sweep` and `clog-sweep-sessions` scouts skip a single `gh pr merge` as auto-logged and drop it from the unlogged-mutation examples.
- Out of scope: logging `git -C <dir> commit|push`. The hooks spec says those SHALL NOT trigger on their own, and that requirement is unchanged.

## Impact

- Affected specs: hooks, session-sweep
- Affected code: `hooks/post-action-log.sh`, `skills/clog-sweep/SKILL.md`, `skills/clog-sweep-sessions/SKILL.md`, `tests/cli/run.sh`
- Depends on change `clog-sweep-review-2026-11-09-2026-11-16-tnbook` (its scout wording is edited here), so this branch is stacked on it.
