#!/usr/bin/env bash
# punch.sh — human-readable punch list from per-session result lines (stdin, as
# printed by result.sh). One line per session:
#   <sid>: swept <dates>, N gaps, N backfilled, N learnings
#   <sid>: no_transcript
# followed by a totals line. Exit 1 on a line that is not a result object.
set -euo pipefail

jq -r -s '
  (map(if (type == "object") and has("sid") and has("status") then . else error("punch: not a result line") end)) as $rs
  | ($rs[] | if .status == "swept"
      then "\(.sid): swept \(.dates | join(",")), \(.gaps) gaps, \(.backfilled) backfilled, \(.learnings) learnings"
      else "\(.sid): \(.status)" end),
    "\($rs | length) sessions: \($rs | map(select(.status == "swept")) | length) swept, \($rs | map(.backfilled) | add // 0) backfilled"' || exit 1
