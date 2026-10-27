#!/usr/bin/env bash
# logs-for.sh <YYYY-MM-DD>... — print the clog day-file path for each date:
#   <CLOG_LOG_ROOT>/<CLOG_LOG_SUBDIR>/YYYYMMDD.jsonl
# Root and subdir come from lib/config.sh load_config (env > CLOG_CONFIG /
# ~/.config/clog/config.yaml > defaults). A path is printed whether or not the
# file exists. Exit 1 on no dates, a bad date, or a missing config.
set -euo pipefail

# Resolve symlinks (the skill dir is symlinked into ~/.claude/skills)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

if [[ $# -eq 0 ]]; then
  echo "usage: logs-for.sh <YYYY-MM-DD>..." >&2
  exit 1
fi

# Same pattern as bin/clog --date
DATE_RE='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'
for d in "$@"; do
  if [[ ! "$d" =~ $DATE_RE ]]; then
    printf "logs-for: invalid date '%s'\n" "$d" >&2
    exit 1
  fi
done

. "${SCRIPT_DIR}/../../../lib/config.sh"
# `|| exit 1` as in bin/clog: it also keeps `set -e` from firing inside the
# parsers, whose last `[[ -n .. ]] && export` returns 1 when a key is unset.
load_config || exit 1
if [[ ${CLOG_DISABLE:-} == 1 || -z "${CLOG_LOG_ROOT:-}" ]]; then
  echo "logs-for: clog is disabled (CLOG_DISABLE=1); no log root" >&2
  exit 1
fi

for d in "$@"; do
  printf '%s/%s/%s.jsonl\n' "$CLOG_LOG_ROOT" "$CLOG_LOG_SUBDIR" "${d//-/}"
done
