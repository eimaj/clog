# Tasks

## 1. Extract

- [ ] 1.1 Add `skills/clog-sweep-sessions/scripts/extract.sh` per the delta spec.
- [ ] 1.2 Add `tests/cli/run.sh` cases: edit, agent, MCP mutating vs read, Bash single hook-logged command skipped, `git -C` commit flagged, chained merge and tag flagged, read-only Bash ignored, unparseable lines and non-assistant records ignored.

## 2. Skill

- [ ] 2.1 Replace the scout step in `skills/clog-sweep-sessions/SKILL.md` with the extract pipeline and the review step, and update its content checks in `tests/cli/run.sh`.

## 3. Verify

- [ ] 3.1 `npm run check` passes (run with `CLOG_DEFAULT_TAGS` unset).
- [ ] 3.2 `openspec validate sweep-jq-extract --strict` passes.

## Workflow follow-up

- Archive this change after merge (not in this PR).
