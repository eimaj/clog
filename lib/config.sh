#!/usr/bin/env bash
# lib/config.sh — load ~/.config/clog/config.yaml and export CLOG_* variables.
# Usage: source this file, then call load_config [--hook]
#   --hook: silent exit 0 on missing config (for hook callers)
#   (no flag): exit 1 with message on missing config (for bin/clog callers)

load_config() {
  local hook_mode=false
  for arg in "$@"; do
    [[ "$arg" == "--hook" ]] && hook_mode=true
  done

  # Resolve config path
  local config_path="${CLOG_CONFIG:-$HOME/.config/clog/config.yaml}"

  if [[ ! -f "$config_path" ]]; then
    if [[ "$hook_mode" == "true" ]]; then
      return 0
    else
      echo "clog: no config at ${config_path}. Run setup.sh to create one." >&2
      return 1
    fi
  fi

  # Short-circuit if disabled
  if [[ "${CLOG_DISABLE:-}" == "1" ]]; then
    return 0
  fi

  # Parse config.yaml — use yq if available, else basic grep/sed for flat key: value lines
  if command -v yq >/dev/null 2>&1; then
    _clog_parse_yq "$config_path"
  else
    _clog_parse_basic "$config_path"
  fi

  # Env overrides (applied last)
  [[ -n "${CLOG_LOG_ROOT:-}" ]] || true  # already set by parser; env wins below
  export CLOG_LOG_ROOT="${CLOG_LOG_ROOT:-${HOME}/clog-logs}"
  export CLOG_REPORTS_ROOT="${CLOG_REPORTS_ROOT:-${HOME}/clog-logs/reports}"
  export CLOG_LOG_SUBDIR="${CLOG_LOG_SUBDIR:-claude}"
  export CLOG_REMINDER_THRESHOLD="${CLOG_REMINDER_THRESHOLD:-900}"
  export CLOG_AUTO_COMMIT_ENABLED="${CLOG_AUTO_COMMIT_ENABLED:-false}"
  export CLOG_AUTO_COMMIT_REPO="${CLOG_AUTO_COMMIT_REPO:-}"
  export CLOG_AUTO_COMMIT_MSG="${CLOG_AUTO_COMMIT_MSG:-docs(clog): auto-commit logs}"
  export CLOG_FAMILIES="${CLOG_FAMILIES:-}"
  export CLOG_KPIS="${CLOG_KPIS:-}"
  export CLOG_AGENTS="${CLOG_AGENTS:-}"
  export CLOG_INTEGRATIONS_CRRT="${CLOG_INTEGRATIONS_CRRT:-false}"
}

_clog_parse_yq() {
  local cfg="$1"

  local log_root
  log_root=$(yq '.log_root // ""' "$cfg" 2>/dev/null | _clog_expand_home)
  [[ -n "$log_root" ]] && export CLOG_LOG_ROOT="$log_root"

  local log_subdir
  log_subdir=$(yq '.log_subdir // ""' "$cfg" 2>/dev/null)
  [[ -n "$log_subdir" ]] && export CLOG_LOG_SUBDIR="$log_subdir"

  local reports_root
  reports_root=$(yq '.reports_root // ""' "$cfg" 2>/dev/null | _clog_expand_home)
  [[ -n "$reports_root" ]] && export CLOG_REPORTS_ROOT="$reports_root"

  local threshold
  threshold=$(yq '.reminder_threshold_seconds // ""' "$cfg" 2>/dev/null)
  [[ -n "$threshold" ]] && export CLOG_REMINDER_THRESHOLD="$threshold"

  local auto_enabled
  auto_enabled=$(yq '.auto_commit.enabled // ""' "$cfg" 2>/dev/null)
  [[ -n "$auto_enabled" ]] && export CLOG_AUTO_COMMIT_ENABLED="$auto_enabled"

  local auto_repo
  auto_repo=$(yq '.auto_commit.repo_root // ""' "$cfg" 2>/dev/null | _clog_expand_home)
  [[ -n "$auto_repo" ]] && export CLOG_AUTO_COMMIT_REPO="$auto_repo"

  local auto_msg
  auto_msg=$(yq '.auto_commit.message // ""' "$cfg" 2>/dev/null)
  [[ -n "$auto_msg" ]] && export CLOG_AUTO_COMMIT_MSG="$auto_msg"

  local families
  families=$(yq '.families[]? // ""' "$cfg" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
  [[ -n "$families" ]] && export CLOG_FAMILIES="$families"

  local kpis
  kpis=$(yq '.kpis[]? // ""' "$cfg" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
  [[ -n "$kpis" ]] && export CLOG_KPIS="$kpis"

  local agents
  agents=$(yq '.agents[]? // ""' "$cfg" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
  [[ -n "$agents" ]] && export CLOG_AGENTS="$agents"

  local crrt
  crrt=$(yq '.integrations.crrt // ""' "$cfg" 2>/dev/null)
  [[ -n "$crrt" ]] && export CLOG_INTEGRATIONS_CRRT="$crrt"
}

_clog_parse_basic() {
  local cfg="$1"

  # Basic parser: handles flat key: value lines only (no nested keys for flat values)
  _read_flat() { grep -E "^${1}:" "$cfg" 2>/dev/null | head -1 | sed "s/^${1}:[[:space:]]*//" | tr -d '"' | _clog_expand_home; }

  local log_root; log_root=$(_read_flat log_root)
  [[ -n "$log_root" ]] && export CLOG_LOG_ROOT="$log_root"

  local log_subdir; log_subdir=$(_read_flat log_subdir)
  [[ -n "$log_subdir" ]] && export CLOG_LOG_SUBDIR="$log_subdir"

  local reports_root; reports_root=$(_read_flat reports_root)
  [[ -n "$reports_root" ]] && export CLOG_REPORTS_ROOT="$reports_root"

  local threshold; threshold=$(_read_flat reminder_threshold_seconds)
  [[ -n "$threshold" ]] && export CLOG_REMINDER_THRESHOLD="$threshold"

  # Nested auto_commit fields — parsed with basic grep on indented lines
  local auto_enabled; auto_enabled=$(grep -E "^\s+enabled:" "$cfg" 2>/dev/null | head -1 | sed 's/.*enabled:[[:space:]]*//' | tr -d '"')
  [[ -n "$auto_enabled" ]] && export CLOG_AUTO_COMMIT_ENABLED="$auto_enabled"

  local auto_msg; auto_msg=$(grep -E "^\s+message:" "$cfg" 2>/dev/null | head -1 | sed 's/.*message:[[:space:]]*//' | tr -d '"')
  [[ -n "$auto_msg" ]] && export CLOG_AUTO_COMMIT_MSG="$auto_msg"

  # List fields — collect items prefixed with "  - "
  local families
  families=$(awk '/^families:/,/^[a-z]/' "$cfg" 2>/dev/null | grep '^\s*-' | sed 's/.*-[[:space:]]*//' | tr '\n' ' ' | sed 's/ $//')
  [[ -n "$families" ]] && export CLOG_FAMILIES="$families"

  local kpis
  kpis=$(awk '/^kpis:/,/^[a-z]/' "$cfg" 2>/dev/null | grep '^\s*-' | sed 's/.*-[[:space:]]*//' | tr '\n' ' ' | sed 's/ $//')
  [[ -n "$kpis" ]] && export CLOG_KPIS="$kpis"

  local agents
  agents=$(awk '/^agents:/,/^[a-z]/' "$cfg" 2>/dev/null | grep '^\s*-' | sed 's/.*-[[:space:]]*//' | tr '\n' ' ' | sed 's/ $//')
  [[ -n "$agents" ]] && export CLOG_AGENTS="$agents"

  local crrt; crrt=$(grep -E "^\s+crrt:" "$cfg" 2>/dev/null | head -1 | sed 's/.*crrt:[[:space:]]*//' | tr -d '"')
  [[ -n "$crrt" ]] && export CLOG_INTEGRATIONS_CRRT="$crrt"
}

_clog_expand_home() {
  # Replace ${HOME} or ~ at start of value
  sed "s|^\${HOME}|${HOME}|;s|^~|${HOME}|"
}
