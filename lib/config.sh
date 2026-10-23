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

  # Snapshot non-empty CLOG_* env values; the parsers overwrite them from the
  # config file, so they are re-applied afterwards (env > config > default).
  local -a env_snap=()
  local env_key
  for env_key in CLOG_LOG_ROOT CLOG_LOG_SUBDIR CLOG_REPORTS_ROOT \
    CLOG_REMINDER_THRESHOLD CLOG_AUTO_COMMIT_ENABLED CLOG_AUTO_COMMIT_REPO \
    CLOG_AUTO_COMMIT_MSG CLOG_FAMILIES CLOG_KPIS CLOG_CLI_PATH; do
    [[ -n "${!env_key:-}" ]] && env_snap+=("${env_key}=${!env_key}")
  done

  # Parse config.yaml — use yq if available, else basic grep/sed for flat key: value lines
  if command -v yq >/dev/null 2>&1; then
    _clog_parse_yq "$config_path"
  else
    _clog_parse_basic "$config_path"
  fi

  # Env overrides (applied last), then built-in defaults for anything still unset
  local env_kv
  for env_kv in ${env_snap[@]+"${env_snap[@]}"}; do
    export "$env_kv"
  done
  # Env path values can carry a literal ~ or ${HOME} (e.g. from a settings.json
  # env block) that no shell expanded; the parsers expand config values, so do
  # the same here or the path becomes <cwd>/~/...
  local path_key
  for path_key in CLOG_LOG_ROOT CLOG_REPORTS_ROOT CLOG_AUTO_COMMIT_REPO CLOG_CLI_PATH; do
    [[ -n "${!path_key:-}" ]] && export "${path_key}=$(printf '%s' "${!path_key}" | _clog_expand_home)"
  done
  export CLOG_LOG_ROOT="${CLOG_LOG_ROOT:-${HOME}/clog-logs}"
  export CLOG_REPORTS_ROOT="${CLOG_REPORTS_ROOT:-${HOME}/clog-logs/reports}"
  export CLOG_LOG_SUBDIR="${CLOG_LOG_SUBDIR:-claude}"
  export CLOG_REMINDER_THRESHOLD="${CLOG_REMINDER_THRESHOLD:-900}"
  export CLOG_AUTO_COMMIT_ENABLED="${CLOG_AUTO_COMMIT_ENABLED:-false}"
  export CLOG_AUTO_COMMIT_REPO="${CLOG_AUTO_COMMIT_REPO:-}"
  export CLOG_AUTO_COMMIT_MSG="${CLOG_AUTO_COMMIT_MSG:-docs(clog): auto-commit logs}"
  export CLOG_FAMILIES="${CLOG_FAMILIES:-}"
  export CLOG_KPIS="${CLOG_KPIS:-}"
  export CLOG_CLI_PATH="${CLOG_CLI_PATH:-}"

  # Machine-scoped default tags (e.g. "jbook"), auto-applied to every entry.
  # Never sourced from config.yaml (that file is typically dotfiles-synced
  # across machines). Env wins; otherwise read a plain-text local-only file
  # that lives outside any git repo, so it never leaves this machine.
  export CLOG_DEFAULT_TAGS="${CLOG_DEFAULT_TAGS:-}"
  if [[ -z "$CLOG_DEFAULT_TAGS" ]]; then
    local tags_file="${CLOG_TAGS_FILE:-$HOME/.config/clog/tags.local}"
    if [[ -f "$tags_file" ]]; then
      CLOG_DEFAULT_TAGS=$(tr -d '\n' < "$tags_file" | sed 's/[[:space:]]*$//')
      export CLOG_DEFAULT_TAGS
    fi
  fi
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

  local cli_path
  cli_path=$(yq '.cli_path // ""' "$cfg" 2>/dev/null | _clog_expand_home)
  [[ -n "$cli_path" ]] && export CLOG_CLI_PATH="$cli_path"
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

  local auto_repo; auto_repo=$(grep -E "^\s+repo_root:" "$cfg" 2>/dev/null | head -1 | sed 's/.*repo_root:[[:space:]]*//' | tr -d '"' | _clog_expand_home)
  [[ -n "$auto_repo" ]] && export CLOG_AUTO_COMMIT_REPO="$auto_repo"

  local auto_msg; auto_msg=$(grep -E "^\s+message:" "$cfg" 2>/dev/null | head -1 | sed 's/.*message:[[:space:]]*//' | tr -d '"')
  [[ -n "$auto_msg" ]] && export CLOG_AUTO_COMMIT_MSG="$auto_msg"

  # List fields — collect every "  - item" line under the key until the next
  # top-level (non-indented, non-blank, non-comment) line. Space-joined, like yq.
  _read_list() {
    awk -v key="$1" '
      $0 ~ "^" key ":" { in_list = 1; next }
      in_list && /^[^ \t#]/ { in_list = 0 }
      in_list && /^[ \t]*-/ {
        sub(/^[ \t]*-[ \t]*/, ""); gsub(/"/, "")
        out = (out == "" ? $0 : out " " $0)
      }
      END { print out }
    ' "$cfg" 2>/dev/null
  }

  local families; families=$(_read_list families)
  [[ -n "$families" ]] && export CLOG_FAMILIES="$families"

  local kpis; kpis=$(_read_list kpis)
  [[ -n "$kpis" ]] && export CLOG_KPIS="$kpis"

  local cli_path; cli_path=$(_read_flat cli_path)
  [[ -n "$cli_path" ]] && export CLOG_CLI_PATH="$cli_path"
}

_clog_expand_home() {
  # Replace ${HOME} or ~ at start of value
  sed "s|^\${HOME}|${HOME}|;s|^~|${HOME}|"
}
