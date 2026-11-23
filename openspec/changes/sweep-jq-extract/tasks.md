# Tasks

## 1. Extract

- [x] 1.1 Add `skills/clog-sweep-sessions/scripts/extract.sh` per the delta spec.
- [x] 1.2 Add `tests/cli/run.sh` cases: edit, agent, MCP mutating vs read, Bash single hook-logged command skipped, `git -C` commit flagged, chained merge and tag flagged, read-only Bash ignored, unparseable lines and non-assistant records ignored.

## 2. Skill

- [x] 2.1 Replace the scout step in `skills/clog-sweep-sessions/SKILL.md` with the extract pipeline and the review step, and update its content checks in `tests/cli/run.sh`.

## 3. Verify

- [x] 3.1 `npm run check` passes (run with `CLOG_DEFAULT_TAGS` unset).
- [x] 3.2 `openspec validate sweep-jq-extract --strict` passes.

## Workflow follow-up

- Archive this change after merge (not in this PR).

## 4. clog-sweep

- [x] 4.1 Replace both scout prompts in `skills/clog-sweep/SKILL.md` with the shared pipeline and review, and update its content checks in `tests/cli/run.sh`.
