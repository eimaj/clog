#!/usr/bin/env bash
# resolve.sh <sid>... — locate Claude Code transcripts by session id and list the
# local calendar dates each session ran on.
#
# Prints one JSON line per sid:
#   {"sid":..,"transcript":"/abs/path.jsonl","dates":["YYYY-MM-DD",..]}   found
#   {"sid":..,"status":"no_transcript"}                                    not found
# Searches ${CLOG_CC_PROJECTS:-$HOME/.claude/projects}/*/<sid>.jsonl. Dates run
# from the first to the last `timestamp` (lines without one are skipped),
# inclusive, in the local timezone (log files are named by local date).
# Exit 1 with usage on no sids; a missing transcript does not change the exit code.
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: resolve.sh <session-id>..." >&2
  exit 1
fi

ROOT="${CLOG_CC_PROJECTS:-$HOME/.claude/projects}"

# local_date <epoch>: YYYY-MM-DD in the local timezone (BSD date -r, else GNU date -d)
local_date() { date -r "$1" +%Y-%m-%d 2>/dev/null || date -d "@$1" +%Y-%m-%d; }

for sid in "$@"; do
  transcript=""
  if [[ "$sid" != */* && -d "$ROOT" ]]; then
    for f in "$ROOT"/*/"$sid".jsonl; do
      [[ -f "$f" ]] && { transcript="$f"; break; }
    done
  fi
  if [[ -z "$transcript" ]]; then
    jq -nc --arg sid "$sid" '{sid:$sid,status:"no_transcript"}'
    continue
  fi

  # First and last timestamp as epoch seconds; unparseable lines and lines
  # without a string timestamp are skipped. Fractional seconds are dropped.
  bounds=$(jq -R -n -r '
    [inputs | fromjson? | objects | .timestamp? | strings
     | sub("\\.[0-9]+"; "") | try fromdateiso8601 catch empty]
    | if length == 0 then empty else "\(min) \(max)" end' "$transcript")

  dates=()
  if [[ -n "$bounds" ]]; then
    first=${bounds% *} last=${bounds#* }
    last_date=$(local_date "$last")
    # Step 12h (shorter than any local day, DST included) so no date is skipped.
    cur=$first
    while (( cur <= last )); do
      d=$(local_date "$cur")
      [[ ${#dates[@]} -gt 0 && "${dates[${#dates[@]}-1]}" == "$d" ]] || dates+=("$d")
      cur=$(( cur + 43200 ))
    done
    [[ "${dates[${#dates[@]}-1]}" == "$last_date" ]] || dates+=("$last_date")
  fi

  jq -nc --arg sid "$sid" --arg t "$transcript" '{sid:$sid,transcript:$t,dates:($ARGS.positional|unique)}' \
    --args ${dates[@]+"${dates[@]}"}
done
