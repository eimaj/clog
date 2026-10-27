#!/usr/bin/env bash
# backfill-cmds.sh <sid> — turn gap records into `clog` backfill commands.
#
# stdin: one JSON object per line:
#   {"date":"YYYY-MM-DD","time":"HH:MM:SS","type":"CODE","summary":"..","why":"..",
#    "file":"/optional/path","kpi":"optional, default failure"}
# stdout: per record, a clog call for the missed action followed by its paired
# LEARNING (`why` names the pattern that defeated logging). Both carry
# --session <sid> --date <date> --time <time> so they land on the right session,
# day and time. Values are shell-quoted, so the output is safe to run with bash.
# `summary` and `why` come from untrusted transcript text and are cut to 200 characters.
# Exit 1 (nothing printed for the bad record onward) on a missing sid or a record
# with a bad type, date, time, or empty summary/why.
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "usage: backfill-cmds.sh <session-id>   (gap records on stdin)" >&2
  exit 1
fi

jq -r --arg sid "$1" '
  def bad($m): error("backfill-cmds: " + $m);
  select(. != null)
  | if (.type // "" | test("^(DECISION|ACTION|CODE|PR|COMMIT|REPO|FOLLOWUP)$") | not)
      then bad("invalid type \(.type // "" | tojson) (LEARNING is added automatically)") else . end
  | if (.date // "" | test("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$") | not)
      then bad("invalid date \(.date // "" | tojson)") else . end
  | if (.time // "" | test("^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$") | not)
      then bad("invalid time \(.time // "" | tojson)") else . end
  | if (.summary // "" | length) == 0 then bad("empty summary") else . end
  | if (.why // "" | length) == 0 then bad("empty why (the paired LEARNING needs one)") else . end
  | .summary |= .[0:200] | .why |= .[0:200]
  | @sh "--agent clog-sweep-sessions --session \($sid) --date \(.date) --time \(.time)" as $at
  | (@sh "clog \(.type) \(.summary)"
      + (if (.file // "") != "" then @sh " --file \(.file)" else "" end)
      + " " + $at),
    (@sh "clog LEARNING \(.why) --family interactive --kpi \(.kpi // "failure") " + $at)
' || exit 1
