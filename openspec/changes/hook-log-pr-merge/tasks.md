# Tasks

## 1. Hook

- [ ] 1.1 In `hooks/post-action-log.sh`, add a `gh pr merge` branch between `gh pr create` and `git push` that writes an `ACTION` entry `merged PR #<n> (<repo>)` per the delta spec.
- [ ] 1.2 Add hook tests to `tests/cli/run.sh`: merge with a number, merge without a number, merge chained with a push.

## 2. Scouts

- [ ] 2.1 In both scout prompts of `skills/clog-sweep/SKILL.md` and the one in `skills/clog-sweep-sessions/SKILL.md`, move `gh pr merge` from the unlogged examples to the single-command skip list, and update the content checks in `tests/cli/run.sh`.

## 3. Verify

- [ ] 3.1 `npm run check` passes (run with `CLOG_DEFAULT_TAGS` unset).
- [ ] 3.2 `openspec validate hook-log-pr-merge --strict` passes.

## Workflow follow-up

- Archive this change after merge (not in this PR).
