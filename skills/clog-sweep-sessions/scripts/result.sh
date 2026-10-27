#!/usr/bin/env bash
# result.sh '<resolve.sh line>' [--gaps N] [--backfilled N] [--learnings N] [--date YYYY-MM-DD]...
#
# Build the per-session result object from one resolve.sh line plus the counts
# for that session. Prints one JSON line:
#   {"sid","transcript","dates","gaps","backfilled","learnings","status"}
# status is "swept" when the transcript was read, else resolve's "no_transcript"
# or "unreadable"; those carry transcript null (no_transcript only), dates [] and
# zero counts whatever was passed. `dates` is the dates swept: the --date values
# when given (sorted, unique), else resolve's dates. Counts default to 0.
# Exit 1 on a missing/invalid resolve line, a bad count, or a bad date.
set -euo pipefail

usage() { echo "usage: result.sh '<resolve json>' [--gaps N] [--backfilled N] [--learnings N] [--date YYYY-MM-DD]..." >&2; exit 1; }
[[ $# -ge 1 ]] || usage
resolved=$1; shift

gaps=0 backfilled=0 learnings=0 dates=()
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage
  case "$1" in
    --gaps)       gaps=$2 ;;
    --backfilled) backfilled=$2 ;;
    --learnings)  learnings=$2 ;;
    --date)
      [[ "$2" =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]] \
        || { printf "result: invalid date '%s'\n" "$2" >&2; exit 1; }
      dates+=("$2") ;;
    *) usage ;;
  esac
  shift 2
done
for n in "$gaps" "$backfilled" "$learnings"; do
  [[ "$n" =~ ^[0-9]+$ ]] || { printf "result: invalid count '%s'\n" "$n" >&2; exit 1; }
done

jq -c -n --argjson r "$resolved" --argjson gaps "$gaps" --argjson bf "$backfilled" --argjson ln "$learnings" \
  '$ARGS.positional as $want |
   if ($r | type) != "object" or (($r.sid // "") | type) != "string" or ($r.sid // "") == ""
   then error("result: resolve line needs a sid") else . end |
   ($r.status // "swept") as $st |
   if $st == "swept" then
     {sid: $r.sid, transcript: $r.transcript,
      dates: (if ($want | length) > 0 then ($want | unique) else ($r.dates // []) end),
      gaps: $gaps, backfilled: $bf, learnings: $ln, status: "swept"}
   else
     {sid: $r.sid, transcript: ($r.transcript // null), dates: [],
      gaps: 0, backfilled: 0, learnings: 0, status: $st}
   end' --args ${dates[@]+"${dates[@]}"} || exit 1
