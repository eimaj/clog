#!/usr/bin/env bash
# pre-agent-clog.sh — auto-append a parent-side ACTION entry for every subagent dispatch.
# Runs as PreToolUse hook on Agent; exit 0 always (hook contract) so it can never block a dispatch.
#
# Why this exists: a subagent logging its own work does NOT satisfy the parent's checkpoint.
# The two answer different questions when a run is reconstructed later — what the agent did
# vs. that the orchestrator handed off. Relying on the model to remember this fails: the rule
# lived in orchestrate's prompts/_logging.md and was violated on the very next dispatch.
# A hook cannot be forgotten.

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

DESC=$(echo "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // "claude"' 2>/dev/null)
MODEL=$(echo "$INPUT" | jq -r '.tool_input.model // ""' 2>/dev/null)

# Nothing useful to say — skip rather than write a junk entry the sweep will flag.
[[ -z "$DESC" ]] && exit 0

SUMMARY="dispatch ${AGENT_TYPE}${MODEL:+ ($MODEL)} — ${DESC}"

REPO_ARG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")

if [[ -n "$CLOG_BIN_RESOLVED" && -x "$CLOG_BIN_RESOLVED" ]]; then
  "$CLOG_BIN_RESOLVED" ACTION "$SUMMARY" ${REPO_ARG:+--repo "$REPO_ARG"} 2>/dev/null || true
else
  # Fallback: inline JSONL append using lib/jsonl.sh
  # shellcheck source=../lib/jsonl.sh
  . "${SCRIPT_DIR}/../lib/jsonl.sh"
  LOG_DIR="${CLOG_LOG_ROOT}/${CLOG_LOG_SUBDIR}"
  LOG_FILE="${LOG_DIR}/$(date +%Y%m%d).jsonl"
  mkdir -p "$LOG_DIR"
  build_entry ACTION "$SUMMARY" "" "$REPO_ARG" "" "" "" "" "" "" >> "$LOG_FILE"
fi

exit 0
