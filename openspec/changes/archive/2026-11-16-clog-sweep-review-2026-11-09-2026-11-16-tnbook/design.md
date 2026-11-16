## Context

The scout prompts in `skills/clog-sweep/SKILL.md` (Mode A and Mode B) and in `skills/clog-sweep-sessions/SKILL.md` list Edit/Write, MCP mutations and Task/Agent dispatches as state-changers and tell the scout to skip `git commit/push/gh pr create` as auto-logged. `~/.claude/hooks/post-action-log.sh` runs on Bash and logs a command only when its text matches `git[[:space:]]+commit` (COMMIT), `gh[[:space:]]+pr[[:space:]]+create` (PR) or `git[[:space:]]+push` (ACTION); every other Bash command exits 0 without a log. So `gh pr merge` is never logged, and `git -C <dir> commit` / `git -C <dir> push` do not match either regex, so they are not logged.

Step 1 of Mode B resolves `resolve.sh` and `logs-for.sh` from `<SKILL_DIR>/../clog-sweep-sessions/scripts`, where `<SKILL_DIR>` is the real directory behind the `~/.claude/skills/clog-sweep` symlink, and falls back to an inline scan when `$CLAUDE_SESSION_ID` is unset, the transcript is missing, or either script exits non-zero. Today `~/.claude/skills` has no `clog-sweep-sessions` symlink, but the real-directory path still resolves because both skills live in this repo. The fallback therefore fires only when the symlink is not followed (or the skill is copied, not linked), `$CLAUDE_SESSION_ID` is unset, the transcript is missing, or a script fails; it fires silently, so the user cannot tell that earlier days went unchecked.

## Goals / Non-Goals

**Goals:** the scout flags `gh pr merge` and other Bash mutations no hook logs; the skip list names only what `post-action-log.sh` logs; the fallback says it happened and which days were not checked.

**Non-Goals:** installing the `clog-sweep-sessions` symlink (environment step); extending `post-action-log.sh` to log merges (separate hooks change); changing how the transcript path or day list is resolved.

## Decisions

- **Edit both skills' scout prompts, not only `clog-sweep`.** The spec requirement names `clog-sweep` and `clog-sweep-sessions`, and the `clog-sweep-sessions` scout prompt carries the same skip line; leaving it would keep merges unflagged in cross-session sweeps. The proposal's "Affected code" lists only `clog-sweep`; the spec governs.
- **Skip only what the hook's regexes match.** The skip line becomes: skip a Bash command only when it is a single `git commit`, `git push` or `gh pr create`, which `post-action-log.sh` logs (one entry per command, first match wins); every part of a chained command is checked, so `gh pr merge 12 && git push` is not skipped; `git` with an option before the subcommand (`git -C <dir> commit|push`) is not matched by the hook, so it is checked against the log like any other state-changer. Alternative, keep the three names and add `gh pr merge` to the state-changer list: leaves `git -C` commits and pushes silently skipped, contradicting "skip only what the hook actually logs".
- **State-changer list gains "Bash-run mutations no hook logs", with `gh pr merge`, `gh pr close`, `gh issue create`, `git merge` and `git tag` as "e.g." examples, plus "any gh/git command that changes remote or repo state".** A closed list would go stale and a haiku scout reads a bare list as exhaustive; the rule plus examples lets it generalize. Mode A and Mode B scouts get the same sentence.
- **Announce the fallback when detected and repeat it in the sweep's own summary line.** Printing at detection survives a haiku scout forgetting a flag across the scan; Mode B step 4 already emits a one-line summary, and the fallback appends `inline fallback: only the current session was scanned, earlier session days were not checked` to it. The sentence does not claim which day was scanned, since with no session id the transcript's last day is unknown. Mode A step 4 already prints the report path and gap counts; it gets the same sentence. Alternative, a separate message before the scan: the user may not read it once the report prints.
- **Name the trigger, not a single cause.** The fallback line says it fired when `$CLAUDE_SESSION_ID` is unset, the transcript is missing, or `resolve.sh`/`logs-for.sh` is unresolvable or exits non-zero; the spec's scenario (helper script missing) is one of those.
- **Guard with content checks in `tests/cli/run.sh`**, the same `grep -c` pattern as `c_sweep__clog_sweep_resolves_every_session_day`.

## Risks / Trade-offs

- [The hook regexes change and the skip line drifts] → the skip line names `post-action-log.sh` so a reader knows where to look; a hooks change that adds merge logging must update it.
- [`git -C <dir> commit` now reported as missing, adding noise] → each is a true miss in the log today; the paired fix (hook regex) is a separate change.
- [The scout is a haiku run and may ignore the new clause] → the clause is one sentence in the existing state-changer list, next to the skip line it replaces.
