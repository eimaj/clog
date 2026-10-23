#!/usr/bin/env bash
# post-action-log.sh — auto-append JSONL entries for git commits, PRs, pushes.
# Runs as PostToolUse hook on Bash; exit 0 always (hook contract).

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
  # The hook's cwd is the project Claude Code is working in
  if git -C "$PWD" rev-parse --git-dir >/dev/null 2>&1; then
    echo "$PWD"
    return
  fi
  echo "$HOME"
}

GIT_DIR=$(extract_git_dir "$CMD")

TYPE=""
SUMMARY=""

if echo "$CMD" | grep -qE 'git[[:space:]]+commit'; then
  TYPE="COMMIT"
  # First -m "…" or -m '…' in the command (a later -m is the same commit's body)
  nl=$'\n' q="'"
  msg_re="-m[[:space:]]+(\"([^\"${nl}]+)\"|${q}([^${q}${nl}]+)${q})"
  if [[ $CMD =~ $msg_re ]]; then
    SUMMARY="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
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

# write_entry <summary> <commit-sha-or-empty>: append one entry of $TYPE.
write_entry() {
  local SUMMARY="$1" COMMIT_ARG="$2"
  if [[ -n "$CLOG_BIN_RESOLVED" && -x "$CLOG_BIN_RESOLVED" ]]; then
    # Delegate to bin/clog
    REPO_ARG=$(basename "$(git -C "$GIT_DIR" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")

    "$CLOG_BIN_RESOLVED" "$TYPE" "$SUMMARY" ${REPO_ARG:+--repo "$REPO_ARG"} 2>/dev/null || true

    # Append commit SHA inline when auto-logged via hook (bin/clog doesn't expose --commit)
    if [[ -n "$COMMIT_ARG" && -f "$LOG_FILE" ]]; then
      # Patch last line to add commit field
      local_last=$(tail -1 "$LOG_FILE")
      patched=$(printf '%s\n' "$local_last" | jq -c --arg c "$COMMIT_ARG" '. + {commit: $c}' 2>/dev/null)
      if [[ -n "$patched" ]]; then
        # Replace last line
        tmp_file="${LOG_FILE}.tmp"
        sed '$d' "$LOG_FILE" > "$tmp_file" 2>/dev/null || true
        printf '%s\n' "$patched" >> "$tmp_file"
        mv "$tmp_file" "$LOG_FILE"
      fi
    fi
  else
    # Fallback: inline JSONL append using lib/jsonl.sh
    # shellcheck source=../lib/jsonl.sh
    . "${SCRIPT_DIR}/../lib/jsonl.sh"
    REPO=$(basename "$(git -C "$GIT_DIR" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")
    ENTRY=$(build_entry "$TYPE" "$SUMMARY" "" "$REPO" "" "" "" "" "" "" "${CLOG_DEFAULT_TAGS:-}")
    if [[ -n "$COMMIT_ARG" ]]; then
      ENTRY=$(printf '%s\n' "$ENTRY" | jq -c --arg c "$COMMIT_ARG" '. + {commit: $c}')
    fi
    printf '%s\n' "$ENTRY" >> "$LOG_FILE"
  fi
}

SHA=""
[[ "$TYPE" == "COMMIT" ]] && SHA=$(git -C "$GIT_DIR" rev-parse --short HEAD 2>/dev/null || echo "")
write_entry "$SUMMARY" "$SHA"

# Auto-commit log if enabled
if [[ "${CLOG_AUTO_COMMIT_ENABLED:-false}" == "true" && -n "${CLOG_AUTO_COMMIT_REPO:-}" ]]; then
  # Absolute path: git resolves pathspecs against the repo, not our cwd.
  ABS_LOG_DIR=$(cd "$LOG_DIR" && pwd -P) || ABS_LOG_DIR=""
  # Pathspec-limited commit so files the user already staged are never swept in.
  if [[ -n "$ABS_LOG_DIR" ]] && git -C "$CLOG_AUTO_COMMIT_REPO" add -- "$ABS_LOG_DIR" >/dev/null 2>&1; then
    git -C "$CLOG_AUTO_COMMIT_REPO" commit -q -m "${CLOG_AUTO_COMMIT_MSG:-docs(clog): auto-commit logs}" -- "$ABS_LOG_DIR" >/dev/null 2>&1 || true
  fi
fi

exit 0
