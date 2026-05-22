#!/usr/bin/env bash
# post-log-reminder.sh — warn if no log entries have been written recently.
# PostToolUse hook on Bash; exit 0 always (advisory only).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config silently — this is a hook
# shellcheck source=../lib/config.sh
. "${SCRIPT_DIR}/../lib/config.sh"
load_config --hook || exit 0

# No-op if disabled
[[ "${CLOG_DISABLE:-}" == "1" ]] && exit 0

THRESHOLD="${CLOG_REMINDER_THRESHOLD:-900}"

# 0 threshold disables reminder
[[ "$THRESHOLD" == "0" ]] && exit 0

LOG_FILE="${CLOG_LOG_ROOT}/${CLOG_LOG_SUBDIR}/$(date +%Y%m%d).jsonl"
MARKER="${TMPDIR:-/tmp}/clog-reminder-warned"
NOW=$(date +%s)

# Check marker — avoid spamming warnings within the threshold window
if [[ -f "$MARKER" ]]; then
  MARKER_AGE=$(( NOW - $(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null || echo "$NOW") ))
  if [[ $MARKER_AGE -lt $THRESHOLD ]]; then
    exit 0
  fi
fi

# Resolve clog binary for self-log calls
CLOG_BIN_RESOLVED=""
if command -v clog >/dev/null 2>&1; then
  CLOG_BIN_RESOLVED=$(which clog)
elif [[ -n "${CLOG_BIN:-}" ]]; then
  CLOG_BIN_RESOLVED="$CLOG_BIN"
elif [[ -x "${SCRIPT_DIR}/../bin/clog" ]]; then
  CLOG_BIN_RESOLVED="${SCRIPT_DIR}/../bin/clog"
fi

_self_log() {
  local msg="$1"
  if [[ -n "$CLOG_BIN_RESOLVED" && -x "$CLOG_BIN_RESOLVED" ]]; then
    # Only pass --family/--kpi if those values exist in config
    local family_flag=()
    local kpi_flag=()
    [[ -n "${CLOG_FAMILIES:-}" ]] && family_flag=(--family interactive)
    [[ -n "${CLOG_KPIS:-}" ]] && kpi_flag=(--kpi prompt_gap)
    "$CLOG_BIN_RESOLVED" LEARNING "$msg" --agent hook-post-log "${family_flag[@]}" "${kpi_flag[@]}" 2>/dev/null || true
  fi
}

if [[ ! -f "$LOG_FILE" ]]; then
  touch "$MARKER"
  echo "WARNING: No log entries today. Log actions with: clog <TYPE> \"<summary>\""
  _self_log "post-log-reminder: no log file today — agent has not logged yet"
  exit 0
fi

LOG_MTIME=$(stat -f %m "$LOG_FILE" 2>/dev/null || stat -c %Y "$LOG_FILE" 2>/dev/null || echo "$NOW")
ELAPSED=$(( NOW - LOG_MTIME ))

if [[ $ELAPSED -gt $THRESHOLD ]]; then
  MINS=$(( ELAPSED / 60 ))
  touch "$MARKER"
  echo "WARNING: Last log entry was ${MINS}m ago. Log actions with: clog <TYPE> \"<summary>\""
  _self_log "post-log-reminder: log stale ${MINS}m — agent not logging regularly"
fi

exit 0
