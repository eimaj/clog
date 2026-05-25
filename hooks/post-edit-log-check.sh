#!/usr/bin/env bash
# post-edit-log-check.sh — warn when N+ edits happen since the last clog entry.
# PostToolUse hook on Edit / Write / MultiEdit / NotebookEdit.
# Exit 0 always (advisory only). Stderr surfaces to the model via the tool result.

# Resolve symlinks so SCRIPT_DIR points to the real install location
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# Load config silently — this is a hook
# shellcheck source=../lib/config.sh
. "${SCRIPT_DIR}/../lib/config.sh"
load_config --hook || exit 0

# No-op if disabled
[[ "${CLOG_DISABLE:-}" == "1" ]] && exit 0

THRESHOLD="${CLOG_EDIT_THRESHOLD:-3}"

# 0 threshold disables the check
[[ "$THRESHOLD" == "0" ]] && exit 0

LOG_FILE="${CLOG_LOG_ROOT}/${CLOG_LOG_SUBDIR}/$(date +%Y%m%d).jsonl"
SESSION="${CLAUDE_SESSION_ID:-${CODEX_SESSION_ID:-${CURSOR_SESSION_ID:-default}}}"
MARKER="${TMPDIR:-/tmp}/clog-edit-counter-${SESSION}"

# Current log file mtime (0 if file does not exist)
LOG_MTIME=0
if [[ -f "$LOG_FILE" ]]; then
  LOG_MTIME=$(stat -f %m "$LOG_FILE" 2>/dev/null || stat -c %Y "$LOG_FILE" 2>/dev/null || echo 0)
fi

# Marker stores "<observed_log_mtime> <count>" so we can detect when a clog
# entry has been written since the last edit and reset the counter.
STORED_LOG_MTIME=0
STORED_COUNT=0
if [[ -f "$MARKER" ]]; then
  read -r STORED_LOG_MTIME STORED_COUNT < "$MARKER" 2>/dev/null || true
  STORED_LOG_MTIME="${STORED_LOG_MTIME:-0}"
  STORED_COUNT="${STORED_COUNT:-0}"
fi

if [[ "$LOG_MTIME" != "$STORED_LOG_MTIME" ]]; then
  # A clog entry was written since the last edit — reset the counter
  COUNT=1
else
  COUNT=$(( STORED_COUNT + 1 ))
fi

echo "$LOG_MTIME $COUNT" > "$MARKER"

if [[ $COUNT -ge $THRESHOLD ]]; then
  echo "LEDGER: ${COUNT} edits since last clog entry. Log a CODE entry before continuing." >&2
fi

exit 0
