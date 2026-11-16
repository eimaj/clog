# Tasks

## 1. Scout prompts

- [x] 1.1 In `skills/clog-sweep/SKILL.md` Mode A and Mode B scout prompts, add "Bash-run mutations no hook logs (`gh pr merge`, `gh pr close`, `gh issue create`, `git merge`, `git tag`)" to the state-changer list and and "any gh/git command that changes remote or repo state", and replace the skip line with: skip a Bash command only when it is a single `git commit`, `git push` or `gh pr create` (logged by `post-action-log.sh`); check every part of a chained command; `git -C <dir> commit|push` is not matched by the hook, so check it against the log.
- [x] 1.2 Make the same two edits in the scout prompt of `skills/clog-sweep-sessions/SKILL.md`.

## 2. Fallback announcement

- [x] 2.1 In `skills/clog-sweep/SKILL.md` Mode B step 1, state the fallback conditions (`$CLAUDE_SESSION_ID` unset, transcript missing, helper unresolvable or non-zero exit) and require the sweep to say it fell back; print `inline fallback: only the current session was scanned, earlier session days were not checked` at detection and append it to the Mode B step 4 summary line and to the Mode A step 4 printout.

## 3. Tests

- [x] 3.1 Add content checks to `tests/cli/run.sh` for both SKILL.md files: `gh pr merge` in the state-changer list, no bare `Skip git commit/push/gh pr create` line, the `git -C <dir> commit|push` clause, and for `clog-sweep` the fallback sentence in both modes.
- [x] 3.2 `npm run check` passes (run with `CLOG_DEFAULT_TAGS` unset).
- [x] 3.3 `openspec validate clog-sweep-review-2026-11-09-2026-11-16-tnbook --strict` passes.

## Workflow follow-up

- `post-action-log.sh` still does not log `gh pr merge` or `git -C <dir> commit|push`; a separate hooks change can add them and shrink the scout's list.
- Install the `clog-sweep-sessions` symlink under `~/.claude/skills` (environment step).
- Archive this change after merge (not in this PR).
