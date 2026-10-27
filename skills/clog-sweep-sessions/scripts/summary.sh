#!/usr/bin/env bash
# summary.sh — one-line summary of a sweep, for the run's clog ACTION.
# stdin: per-session result lines (as printed by result.sh). stdout, e.g.:
#   clog-sweep-sessions: swept 3 of 4 sessions, backfilled 5 entries
# Counts only sessions with status "swept" as swept; "of N" is every session given.
# Exit 1 on a line that is not a result object or on empty input.
set -euo pipefail

jq -r -s '
  if length == 0 then error("summary: no result lines") else . end
  | map(if (type == "object") and has("sid") and has("status") then . else error("summary: not a result line") end)
  | "clog-sweep-sessions: swept \(map(select(.status == "swept")) | length) of \(length) session\(if length == 1 then "" else "s" end), backfilled \(map(.backfilled) | add // 0) entr\(if (map(.backfilled) | add // 0) == 1 then "y" else "ies" end)"' || exit 1
