#!/usr/bin/env bash
# post-action-log.sh — auto-append JSONL entries for git commits, PRs, pushes.
# Runs as PostToolUse hook on Bash; exit 0 always (hook contract).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config silently — this is a hook
# shellcheck source=../lib/config.sh
. "${SCRIPT_DIR}/../lib/config.sh"
load_config --hook || exit 0

# No-op if disabled
[[ "${CLOG_DISABLE:-}" == "1" ]] && exit 0

# Resolve clog binary
CLOG_BIN_RESOLVED=""
if command -v clog >/dev/null 2>&1; then
  CLOG_BIN_RESOLVED=$(which clog)
elif [[ -n "${CLOG_BIN:-}" ]]; then
  CLOG_BIN_RESOLVED="$CLOG_BIN"
elif [[ -x "${SCRIPT_DIR}/../bin/clog" ]]; then
  CLOG_BIN_RESOLVED="${SCRIPT_DIR}/../bin/clog"
fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

extract_git_dir() {
  local cmd="$1"
  local dir
  dir=$(echo "$cmd" | grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $3}')
  [ -n "$dir" ] && { echo "${dir/#\~/$HOME}"; return; }
  dir=$(echo "$cmd" | grep -oE '(^|;)[[:space:]]*cd[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $NF}')
  [ -n "$dir" ] && { echo "${dir/#\~/$HOME}"; return; }
  echo "$HOME"
}

GIT_DIR=$(extract_git_dir "$CMD")

TYPE=""
SUMMARY=""

if echo "$CMD" | grep -qE 'git[[:space:]]+commit'; then
  TYPE="COMMIT"
  SUMMARY=$(echo "$CMD" | grep -oE -- '-m[[:space:]]+"[^"]+"' | head -1 | sed 's/-m[[:space:]]*"//;s/"$//')
  if [ -z "$SUMMARY" ]; then
    SUMMARY=$(echo "$CMD" | grep -oE -- "-m[[:space:]]+'[^']+'" | head -1 | sed "s/-m[[:space:]]*'//;s/'$//")
  fi
  if [ -z "$SUMMARY" ]; then
    SUMMARY=$(git -C "$GIT_DIR" log -1 --format=%s 2>/dev/null || echo "commit")
  fi
elif echo "$CMD" | grep -qE 'gh[[:space:]]+pr[[:space:]]+create'; then
  TYPE="PR"
  SUMMARY=$(echo "$CMD" | grep -oE -- '--title[[:space:]]+"[^"]+"' | sed 's/--title[[:space:]]*"//;s/"$//' || echo "pr created")
elif echo "$CMD" | grep -qE 'git[[:space:]]+push'; then
  TYPE="ACTION"
  BRANCH=$(git -C "$GIT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  REPO_NAME=$(basename "$(git -C "$GIT_DIR" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
  SUMMARY="pushed ${BRANCH}${REPO_NAME:+ ($REPO_NAME)}"
else
  exit 0
fi

LOG_DIR="${CLOG_LOG_ROOT}/${CLOG_LOG_SUBDIR}"
LOG_FILE="${LOG_DIR}/$(date +%Y%m%d).jsonl"
mkdir -p "$LOG_DIR"

if [[ -n "$CLOG_BIN_RESOLVED" && -x "$CLOG_BIN_RESOLVED" ]]; then
  # Delegate to bin/clog
  REPO_ARG=$(basename "$(git -C "$GIT_DIR" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")
  COMMIT_ARG=""
  [[ "$TYPE" == "COMMIT" ]] && COMMIT_ARG=$(git -C "$GIT_DIR" rev-parse --short HEAD 2>/dev/null || echo "")

  "$CLOG_BIN_RESOLVED" "$TYPE" "$SUMMARY" ${REPO_ARG:+--repo "$REPO_ARG"} 2>/dev/null || true

  # Append commit SHA inline when auto-logged via hook (bin/clog doesn't expose --commit)
  if [[ -n "$COMMIT_ARG" && -f "$LOG_FILE" ]]; then
    # Patch last line to add commit field
    local_last=$(tail -1 "$LOG_FILE")
    patched=$(echo "$local_last" | jq --arg c "$COMMIT_ARG" '. + {commit: $c}' 2>/dev/null)
    if [[ -n "$patched" ]]; then
      # Replace last line
      tmp_file="${LOG_FILE}.tmp"
      head -n -1 "$LOG_FILE" > "$tmp_file" 2>/dev/null || true
      echo "$patched" >> "$tmp_file"
      mv "$tmp_file" "$LOG_FILE"
    fi
  fi
else
  # Fallback: inline JSONL append using lib/jsonl.sh
  # shellcheck source=../lib/jsonl.sh
  . "${SCRIPT_DIR}/../lib/jsonl.sh"
  REPO=$(basename "$(git -C "$GIT_DIR" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")
  COMMIT_SHA=""
  [[ "$TYPE" == "COMMIT" ]] && COMMIT_SHA=$(git -C "$GIT_DIR" rev-parse --short HEAD 2>/dev/null || echo "")

  ENTRY=$(build_entry "$TYPE" "$SUMMARY" "" "$REPO" "" "" "" "" "" "")
  if [[ -n "$COMMIT_SHA" ]]; then
    ENTRY=$(echo "$ENTRY" | jq --arg c "$COMMIT_SHA" '. + {commit: $c}')
  fi
  echo "$ENTRY" >> "$LOG_FILE"
fi

# Auto-commit log if enabled
if [[ "${CLOG_AUTO_COMMIT_ENABLED:-false}" == "true" && -n "${CLOG_AUTO_COMMIT_REPO:-}" ]]; then
  git -C "$CLOG_AUTO_COMMIT_REPO" add "$(realpath --relative-to="$CLOG_AUTO_COMMIT_REPO" "$LOG_DIR" 2>/dev/null || echo "logs")" 2>/dev/null
  git -C "$CLOG_AUTO_COMMIT_REPO" commit -m "${CLOG_AUTO_COMMIT_MSG:-docs(clog): auto-commit logs}" 2>/dev/null || true
fi

exit 0
