#!/usr/bin/env bash
# gaps.sh <sid> — drop candidate misses that the log already covers.
#
# stdin: one JSON object per candidate, at least {"date":"YYYY-MM-DD","time":"HH:MM:SS"}
# (extra fields such as type, summary, why pass through untouched).
# stdout: the candidates with no entry for session <sid> within +-60 s of their
# time in that date's day file (path from logs-for.sh), sorted by date then time.
# Entries this skill backfilled earlier carry the action's time, so they count as
# matches and a second run reports zero gaps. The window does not cross midnight.
# Unparseable log lines and entries without session/time are ignored; a missing
# day file means nothing is covered. Exit 1 on no sid, a bad candidate, or when
# logs-for.sh fails (e.g. clog disabled).
set -euo pipefail

# Resolve symlinks (the skill dir is symlinked into ~/.claude/skills)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "usage: gaps.sh <session-id>   (candidates on stdin)" >&2
  exit 1
fi
sid=$1

# Validate and normalise first, so a bad record fails before any output.
cands=$(jq -c '
  if (((.date // "") | test("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$"))
      and ((.time // "") | test("^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$")))
  then . else error("gaps: invalid date/time in candidate \(tojson)") end') || exit 1
[[ -n "$cands" ]] || exit 0

dates=() paths=()
while IFS= read -r d; do dates+=("$d"); done < <(jq -r '.date' <<< "$cands" | sort -u)
# Command substitution, not process substitution, so a logs-for failure aborts.
out=$("$SCRIPT_DIR/logs-for.sh" "${dates[@]}") || exit 1
while IFS= read -r p; do paths+=("$p"); done <<< "$out"

for i in "${!dates[@]}"; do
  f=${paths[$i]}
  covered='[]'
  if [[ -f "$f" ]]; then
    covered=$(jq -R -n -c --arg sid "$sid" '
      def secs: split(":") | map(tonumber) | .[0] * 3600 + .[1] * 60 + .[2];
      [inputs | fromjson? | objects | select(.session == $sid) | .time? | strings | try secs catch empty]' "$f")
  fi
  jq -c --arg d "${dates[$i]}" --argjson cov "$covered" '
    def secs: split(":") | map(tonumber) | .[0] * 3600 + .[1] * 60 + .[2];
    select(.date == $d) | (.time | secs) as $t | select(any($cov[]; (. - $t) | fabs <= 60) | not)' \
    <<< "$cands"
done | jq -s -c 'sort_by(.date, .time)[]'
