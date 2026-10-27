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
# Every field is untrusted transcript text, so each record is checked against a
# schema before anything is quoted: type is one of the action types, date and
# time match their formats, summary and why are strings, file and kpi (when
# present) are strings (kpi one of the config.yaml.example kpis), and <sid> is
# [A-Za-z0-9._-]+. Strings are cut to 200 characters and control characters
# become spaces.
# All or nothing: a record that fails is reported on stderr as
# `backfill-cmds: rejected record <n>: <reason>`, and then nothing at all is
# printed and the exit is 1. A bad <sid> exits 1 the same way.
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "usage: backfill-cmds.sh <session-id>   (gap records on stdin)" >&2
  exit 1
fi
if [[ ! "$1" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "backfill-cmds: invalid session id (want [A-Za-z0-9._-]+)" >&2
  exit 1
fi

jq -nr --arg sid "$1" '
  def flat: gsub("[\u0000-\u001f\u007f]"; " ") | .[0:200];
  def isstr: type == "string";
  # first reason this record fails the schema, or null
  def reason:
    if type != "object" then "not a JSON object"
    elif (.type | isstr | not) or (.type | test("^(DECISION|ACTION|CODE|PR|COMMIT|REPO|FOLLOWUP)$") | not)
      then "invalid type \(.type | tojson) (LEARNING is added automatically)"
    elif (.date | isstr | not) or (.date | test("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$") | not)
      then "invalid date \(.date | tojson)"
    elif (.time | isstr | not) or (.time | test("^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$") | not)
      then "invalid time \(.time | tojson)"
    elif (.summary | isstr | not) then "summary must be a string"
    elif (.summary | flat | test("^ *$")) then "empty summary"
    elif (.why | isstr | not) then "why must be a string (the paired LEARNING needs one)"
    elif (.why | flat | test("^ *$")) then "empty why (the paired LEARNING needs one)"
    elif (.file != null and (.file | isstr | not)) then "file must be a string"
    elif (.kpi != null and ((.kpi | isstr | not) or (.kpi | test("^(failure|prompt_gap|token_waste|effective|format_issue)$") | not)))
      then "invalid kpi \(.kpi | tojson)"
    else null end;
  def cmds:
    (.summary | flat) as $summary | (.why | flat) as $why
    | (if .file == null then "" else .file | flat end) as $file
    | (.kpi // "failure") as $kpi
    | @sh "--agent clog-sweep-sessions --session \($sid) --date \(.date) --time \(.time)" as $at
    | (@sh "clog \(.type) \($summary)"
        + (if $file != "" then @sh " --file \($file)" else "" end)
        + " " + $at),
      (@sh "clog LEARNING \($why) --family interactive --kpi \($kpi) " + $at);
  reduce (inputs | select(. != null)) as $r ({n: 0, out: [], bad: []};
      .n += 1
    | ($r | reason) as $why
    | if $why != null then .bad += ["backfill-cmds: rejected record \(.n): \($why)"]
      else .out += [$r | cmds] end)
  | if (.bad | length) > 0 then (.bad | join("\n") + "\n" | halt_error(1)) else .out[] end
' || exit 1
