#!/usr/bin/env bash
# run-backfill.sh — run backfill-cmds.sh output one command at a time and count exit codes.
#
# stdin: one shell command per line (the output of backfill-cmds.sh).
# stdout: {"backfilled":N,"learnings":M,"failed":K} — N counts commands that exited 0
# and are not `clog LEARNING`, M counts `clog LEARNING` commands that exited 0, K counts
# the rest. A failing command never stops the others; each one's stderr passes through.
# Exit 0 whenever every line was attempted.
set -euo pipefail

backfilled=0 learnings=0 failed=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "$line" ]] || continue
  if bash -c "$line" < /dev/null > /dev/null; then
    if [[ "$line" == "clog LEARNING "* ]]; then learnings=$((learnings + 1)); else backfilled=$((backfilled + 1)); fi
  else
    failed=$((failed + 1))
  fi
done

jq -nc --argjson b "$backfilled" --argjson l "$learnings" --argjson f "$failed" \
  '{backfilled:$b,learnings:$l,failed:$f}'
