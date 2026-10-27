#!/usr/bin/env bash
# localize.sh — derive local date/time from each scout record's UTC timestamp.
#
# stdin: one JSON object per line with a UTC ISO `timestamp` (e.g.
# "2026-10-27T02:30:00.123Z"), as found in the transcript.
# stdout: the same object plus "date":"YYYY-MM-DD" and "time":"HH:MM:SS" in the
# local timezone (log files are named by local date, as in resolve.sh). Any
# date/time the scout supplied is replaced. Fractional seconds are dropped.
# Exit 1 on a record with a missing or unparseable timestamp.
set -euo pipefail

# local_stamp <epoch>: "YYYY-MM-DD HH:MM:SS" locally (BSD date -r, else GNU date -d)
local_stamp() { date -r "$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M:%S'; }

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "$line" ]] || continue
  epoch=$(jq -r '
    (.timestamp? // "") | if type == "string" then sub("\\.[0-9]+"; "") else "" end
    | try fromdateiso8601 catch empty' <<< "$line") || exit 1
  if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
    printf 'localize: missing or invalid timestamp in %s\n' "$line" >&2
    exit 1
  fi
  stamp=$(local_stamp "$epoch")
  jq -c --arg d "${stamp% *}" --arg t "${stamp#* }" '. + {date:$d,time:$t}' <<< "$line"
done
