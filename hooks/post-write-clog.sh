#!/usr/bin/env bash
# post-write-clog.sh — auto-clog CODE entry for every Write, Edit, MultiEdit, NotebookEdit.
# PostToolUse hook. Exit 0 always.

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

. "${SCRIPT_DIR}/../lib/config.sh"
load_config --hook || exit 0

[[ "${CLOG_DISABLE:-}" == "1" ]] && exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')

case "$TOOL" in
  Write|Edit|MultiEdit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')
    ;;
  NotebookEdit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.notebook_path // ""')
    ;;
  *)
    exit 0
    ;;
esac

[[ -z "$FILE_PATH" ]] && exit 0

# Expand ~ so paths are absolute
FILE_PATH="${FILE_PATH/#\~/$HOME}"

# Session: JSON payload > env var (clog also reads CLAUDE_SESSION_ID itself, but be explicit)
SESSION=$(echo "$INPUT" | jq -r '.session_id // ""')
SESSION="${SESSION:-${CLAUDE_SESSION_ID:-${CODEX_SESSION_ID:-${CURSOR_SESSION_ID:-}}}}"

# Model: env var set by Claude Code
MODEL="${CLAUDE_MODEL:-}"

# Repo: nearest git root relative to the file being written
REPO=""
FILE_DIR=$(dirname "$FILE_PATH")
if [[ -d "$FILE_DIR" ]]; then
  GIT_ROOT=$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
  [[ -n "$GIT_ROOT" ]] && REPO=$(basename "$GIT_ROOT")
fi

CLOG_BIN=""
if command -v clog >/dev/null 2>&1; then
  CLOG_BIN=$(which clog)
elif [[ -n "${CLOG_BIN:-}" ]]; then
  CLOG_BIN="$CLOG_BIN"
elif [[ -x "${SCRIPT_DIR}/../bin/clog" ]]; then
  CLOG_BIN="${SCRIPT_DIR}/../bin/clog"
fi

[[ -z "$CLOG_BIN" ]] && exit 0

"$CLOG_BIN" CODE "auto: wrote $FILE_PATH" \
  ${SESSION:+--session "$SESSION"} \
  ${MODEL:+--model "$MODEL"} \
  ${REPO:+--repo "$REPO"} \
  --file "$FILE_PATH" \
  2>/dev/null || true

exit 0
