#!/usr/bin/env bash
# setup.sh — interactive installer and migrator for clog.
# Usage: ./setup.sh [--dry-run] [--migrate] [--force]
#
# --dry-run   : show planned changes without executing
# --migrate   : allow migrating an existing clog install (required if existing install detected)
# --force     : overwrite existing config.yaml without prompting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOG_VERSION="1.0"
SETTINGS_JSON="${HOME}/.claude/settings.json"

# ── Flags ──────────────────────────────────────────────────────────────────────

DRY_RUN=false
MIGRATE=false
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=true ;;
    --migrate)  MIGRATE=true ;;
    --force)    FORCE=true ;;
    --help|-h)
      echo "Usage: $0 [--dry-run] [--migrate] [--force]"
      exit 0 ;;
    *)
      echo "Unknown flag: $arg" >&2
      exit 1 ;;
  esac
done

# ── Helpers ────────────────────────────────────────────────────────────────────

say()  { echo "  $*"; }
info() { echo ""; echo "==> $*"; }
warn() { echo "  [!] $*"; }

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] $*"
  else
    eval "$*"
  fi
}

prompt_yn() {
  local msg="$1" default="${2:-y}"
  local prompt
  [[ "$default" == "y" ]] && prompt="[Y/n]" || prompt="[y/N]"
  read -r -p "  ${msg} ${prompt}: " ans
  ans="${ans:-$default}"
  case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

prompt_val() {
  local msg="$1" default="$2"
  read -r -p "  ${msg} [${default}]: " val
  echo "${val:-$default}"
}

# ── Step 1: Detect existing install ───────────────────────────────────────────

detect_existing_install() {
  info "Checking for existing clog install..."
  local found=false

  local legacy_clog="${HOME}/.claude/hooks/clog.sh"
  if [[ -L "$legacy_clog" && "$(readlink "$legacy_clog")" == "${SCRIPT_DIR}/bin/clog" ]]; then
    say "~/.claude/hooks/clog.sh already links to this repo — not a legacy install."
  elif [[ -f "$legacy_clog" ]]; then
    say "Found: ~/.claude/hooks/clog.sh"
    found=true
  fi
  if [[ -n "${CLOG_BIN:-}" ]]; then
    say "Found: \$CLOG_BIN=${CLOG_BIN}"
    found=true
  fi

  if [[ "$found" == "true" ]]; then
    if [[ "$MIGRATE" != "true" ]]; then
      echo ""
      warn "Existing clog setup detected. Re-run with --migrate to update it."
      warn "Without --migrate, this installer will not overwrite your existing setup."
      exit 1
    fi
    say "Migration mode active — will back up existing files before symlinking."
    return 0
  fi
}

# ── Step 1b: Check dependencies ──────────────────────────────────────────────

check_dependencies() {
  info "Checking dependencies..."

  # jq is required
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is required but not installed."
    if command -v brew >/dev/null 2>&1; then
      if prompt_yn "Install jq via Homebrew?" "y"; then
        run brew install jq
      else
        echo "Install jq manually: https://stedolan.github.io/jq/" >&2
        exit 1
      fi
    else
      echo "jq is required. Install it: https://stedolan.github.io/jq/" >&2
      exit 1
    fi
  else
    say "jq: $(command -v jq)"
  fi

  # gh is optional — enables gh pr create auto-logging
  if ! command -v gh >/dev/null 2>&1; then
    say "gh (GitHub CLI) not found — gh pr create events won't be auto-logged."
    if command -v brew >/dev/null 2>&1; then
      if prompt_yn "Install gh via Homebrew? (enables PR auto-logging)" "n"; then
        run brew install gh
      else
        say "Skipping gh. Install later: brew install gh"
      fi
    else
      say "To enable PR auto-logging, install gh: https://cli.github.com/"
    fi
  else
    say "gh:  $(command -v gh)"
  fi

  # yq is optional — richer YAML parsing; falls back to grep/sed without it
  if ! command -v yq >/dev/null 2>&1; then
    say "yq not found — config will be parsed with grep/sed fallback (all fields still work)."
    if command -v brew >/dev/null 2>&1; then
      if prompt_yn "Install yq via Homebrew? (recommended)" "n"; then
        run brew install yq
      else
        say "Skipping yq. Install later: brew install yq"
      fi
    fi
  else
    say "yq:  $(command -v yq)"
  fi
}

# ── Step 2: Detect AI tools ───────────────────────────────────────────────────

detect_tools() {
  info "Detecting installed AI coding tools..."
  TOOLS_DETECTED=()

  [[ -d "${HOME}/.claude" ]]                && TOOLS_DETECTED+=("claude")   && say "Found: Claude Code (~/.claude/)"
  [[ -d "${HOME}/.codex" ]]                 && TOOLS_DETECTED+=("codex")    && say "Found: Codex (~/.codex/)"
  [[ -d "${HOME}/.cursor" ]]                && TOOLS_DETECTED+=("cursor")   && say "Found: Cursor (~/.cursor/)"
  [[ -d "${HOME}/.config/opencode" ]]       && TOOLS_DETECTED+=("opencode") && say "Found: OpenCode (~/.config/opencode/)"

  if [[ ${#TOOLS_DETECTED[@]} -eq 0 ]]; then
    warn "No AI coding tools detected. Installing clog standalone (bin/clog on PATH only)."
    TOOLS_DETECTED=()
    return 0
  fi

  echo ""
  say "Note: Hooks (PostToolUse) are only supported by Claude Code."
  say "Codex, Cursor, and OpenCode get skill symlinks only — no hooks."
  echo ""

  TOOLS_SELECTED=()
  for tool in "${TOOLS_DETECTED[@]}"; do
    if prompt_yn "Install into ${tool}?" "y"; then
      TOOLS_SELECTED+=("$tool")
    fi
  done
}

# ── Step 2b: Install CLI ──────────────────────────────────────────────────────

CLI_INSTALL_PATH=""

install_cli() {
  info "Install clog CLI..."

  local target="${HOME}/.local/bin/clog"
  local bin_dir="${HOME}/.local/bin"

  if ! prompt_yn "Install bin/clog to ~/.local/bin/clog? (lets skills call clog directly)" "y"; then
    say "Skipping CLI install. Skills will fall back to inline bash logging."
    say "To install later: ln -sf ${SCRIPT_DIR}/bin/clog ${target}"
    return 0
  fi

  run mkdir -p "$bin_dir"

  if [[ -L "$target" ]]; then
    run ln -sf "${SCRIPT_DIR}/bin/clog" "$target"
    say "Updated symlink: $target -> ${SCRIPT_DIR}/bin/clog"
  elif [[ -f "$target" ]]; then
    if prompt_yn "${target} exists (not a symlink). Overwrite?" "n"; then
      run mv "$target" "${target}.pre-clog-pkg.bak"
      say "Backed up: ${target}.pre-clog-pkg.bak"
      run ln -sf "${SCRIPT_DIR}/bin/clog" "$target"
      say "Symlinked: $target -> ${SCRIPT_DIR}/bin/clog"
    else
      say "Skipping — existing file kept."
      return 0
    fi
  else
    run ln -sf "${SCRIPT_DIR}/bin/clog" "$target"
    say "Symlinked: $target -> ${SCRIPT_DIR}/bin/clog"
  fi

  if [[ "$DRY_RUN" == "false" ]]; then
    CLI_INSTALL_PATH="$target"
  fi

  # Warn if ~/.local/bin is not on PATH
  if [[ ":${PATH}:" != *":${bin_dir}:"* ]]; then
    warn "~/.local/bin is not on your PATH. Add to ~/.zshrc or ~/.bashrc:"
    echo "    export PATH=\"\${HOME}/.local/bin:\$PATH\""
  fi
}

# ── Step 3: Pick log_root and reports_root ────────────────────────────────────

pick_paths() {
  info "Configure log paths..."

  local default_log="${HOME}/clog-logs"
  local default_reports="${HOME}/clog-logs/reports"

  LOG_ROOT=$(prompt_val "Log root directory" "$default_log")
  REPORTS_ROOT=$(prompt_val "Reports root directory" "$default_reports")

  # Expand ~ if present
  LOG_ROOT="${LOG_ROOT/#\~/$HOME}"
  REPORTS_ROOT="${REPORTS_ROOT/#\~/$HOME}"

  # Validate writable (create if needed)
  if [[ "$DRY_RUN" == "false" ]]; then
    mkdir -p "$LOG_ROOT" || { echo "Cannot create $LOG_ROOT" >&2; exit 1; }
    mkdir -p "$REPORTS_ROOT" || { echo "Cannot create $REPORTS_ROOT" >&2; exit 1; }
    # Verify writable
    touch "${LOG_ROOT}/.clog-setup-test" && rm "${LOG_ROOT}/.clog-setup-test" || {
      echo "Log root is not writable: $LOG_ROOT" >&2; exit 1
    }
  fi
  say "Log root:     $LOG_ROOT"
  say "Reports root: $REPORTS_ROOT"
}

# ── Step 4: Write config.yaml ─────────────────────────────────────────────────

write_config() {
  info "Writing ~/.config/clog/config.yaml..."
  local config_path="${CLOG_CONFIG:-$HOME/.config/clog/config.yaml}"

  if [[ -f "$config_path" && "$FORCE" != "true" ]]; then
    if ! prompt_yn "Config already exists at ${config_path}. Overwrite?" "n"; then
      say "Skipping config write — using existing config."
      return 0
    fi
  fi

  run mkdir -p "$(dirname "$config_path")"
  if [[ "$DRY_RUN" == "false" ]]; then
    sed \
      -e "s|\${HOME}/clog-logs|${LOG_ROOT}|g" \
      -e "s|${HOME}/clog-logs/reports|${REPORTS_ROOT}|g" \
      -e "s|cli_path: \"\"|cli_path: \"${CLI_INSTALL_PATH}\"|g" \
      "${SCRIPT_DIR}/config/config.yaml.example" > "$config_path"
    say "Written: $config_path"
  else
    say "[dry-run] Would write: $config_path"
  fi
}

# ── Step 5: Wire each selected tool ───────────────────────────────────────────

wire_tools() {
  for tool in "${TOOLS_SELECTED[@]:-}"; do
    case "$tool" in
      claude) wire_claude_code ;;
      codex)  wire_codex ;;
      cursor) wire_cursor ;;
      opencode) wire_opencode ;;
    esac
  done
}

wire_claude_code() {
  info "Wiring Claude Code (~/.claude/)..."

  local hooks_dir="${HOME}/.claude/hooks"
  run mkdir -p "$hooks_dir"

  # Back up and symlink hooks
  for hook in post-action-log.sh post-log-reminder.sh post-edit-log-check.sh \
    post-write-clog.sh pre-agent-clog.sh; do
    local src="${SCRIPT_DIR}/hooks/${hook}"
    local dst="${hooks_dir}/${hook}"
    if [[ -f "$dst" && ! -L "$dst" ]]; then
      run mv "$dst" "${dst}.pre-clog-pkg.bak"
      say "Backed up: ${dst}.pre-clog-pkg.bak"
    fi
    run ln -sf "$src" "$dst"
    say "Symlinked: $dst -> $src"
  done

  # Back up and symlink bin/clog (over clog.sh if it exists)
  local old_clog="${hooks_dir}/clog.sh"
  if [[ -f "$old_clog" && ! -L "$old_clog" ]]; then
    run mv "$old_clog" "${old_clog}.pre-clog-pkg.bak"
    say "Backed up: ${old_clog}.pre-clog-pkg.bak"
  fi

  # Also symlink bin/clog into hooks dir so existing hook references still resolve
  run ln -sf "${SCRIPT_DIR}/bin/clog" "${hooks_dir}/clog.sh"
  say "Symlinked: ${hooks_dir}/clog.sh -> ${SCRIPT_DIR}/bin/clog"

  # Symlink skills
  local skills_dir="${HOME}/.claude/skills"
  run mkdir -p "$skills_dir"
  for skill_dir in "${SCRIPT_DIR}/skills"/*/; do
    local skill_name
    skill_name=$(basename "$skill_dir")
    local dst_skill="${skills_dir}/${skill_name}"
    if [[ -d "$dst_skill" && ! -L "$dst_skill" ]]; then
      warn "Skill already exists (not a symlink): $dst_skill — skipping. Remove manually to replace."
    else
      run ln -sfn "$skill_dir" "$dst_skill"
      say "Symlinked skill: $dst_skill"
    fi
  done

  # Register hooks in ~/.claude/settings.json
  register_claude_hooks

  # Offer to append persona fragment to CLAUDE.md
  local claude_md="${HOME}/.claude/CLAUDE.md"
  if [[ -f "$claude_md" ]]; then
    if prompt_yn "Append Ledger persona fragment to ~/.claude/CLAUDE.md?" "n"; then
      if [[ "$DRY_RUN" == "false" ]]; then
        echo "" >> "$claude_md"
        echo "# Proactive Logging Persona" >> "$claude_md"
        cat "${SCRIPT_DIR}/persona/PERSONA.md" >> "$claude_md"
        say "Appended persona to $claude_md"
      else
        say "[dry-run] Would append persona to $claude_md"
      fi
    fi
  fi
}

register_claude_hooks() {
  info "Registering hooks in ${SETTINGS_JSON}..."

  if [[ ! -f "$SETTINGS_JSON" ]]; then
    warn "settings.json not found at ${SETTINGS_JSON} — skipping hook registration."
    warn "Add hooks manually to ${SETTINGS_JSON} after creating it."
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    say "[dry-run] Would register post-action-log.sh and post-log-reminder.sh in PostToolUse>Bash"
    say "[dry-run] Would register post-edit-log-check.sh in PostToolUse>Edit/Write/MultiEdit/NotebookEdit"
    say "[dry-run] Would register post-write-clog.sh in PostToolUse>Edit/Write/MultiEdit/NotebookEdit"
    say "[dry-run] Would register post-log-reminder.sh in PostToolUse>Agent"
    say "[dry-run] Would register pre-agent-clog.sh in PreToolUse>Agent"
    return 0
  fi

  if ! jq -e . "$SETTINGS_JSON" >/dev/null 2>&1; then
    warn "${SETTINGS_JSON} is not valid JSON — skipping hook registration."
    return 0
  fi

  local hooks_dir="${HOME}/.claude/hooks" tool
  register_hook PostToolUse Bash "${hooks_dir}/post-action-log.sh"
  register_hook PostToolUse Bash "${hooks_dir}/post-log-reminder.sh"
  register_hook PostToolUse Agent "${hooks_dir}/post-log-reminder.sh"
  for tool in Edit Write MultiEdit NotebookEdit; do
    register_hook PostToolUse "$tool" "${hooks_dir}/post-edit-log-check.sh"
    register_hook PostToolUse "$tool" "${hooks_dir}/post-write-clog.sh"
  done
  register_hook PreToolUse Agent "${hooks_dir}/pre-agent-clog.sh"
}

# register_hook <PreToolUse|PostToolUse> <tool> <hook-path>
# No-op when an entry whose matcher covers <tool> (exact, "A|B" list, regex,
# or empty) already runs a command ending in /<hook-name>. Otherwise adds the
# hook to the first entry whose matcher equals <tool>, or appends a new entry.
# Writes through `cat >` so a symlinked settings file keeps its link.
register_hook() {
  local event="$1" tool="$2" hook="$3"
  local name="${hook##*/}" tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/clog-settings.XXXXXX") || {
    warn "Could not create a temp file — skipping ${name}."
    return 0
  }

  if ! jq --arg ev "$event" --arg t "$tool" --arg c "$hook" --arg n "/${name}" '
    def covers($t):
      (.matcher // "") as $m
      | if ($m | type) != "string" then false
        elif $m == "" or $m == "*" then true
        else $m == $t
          or (($m | split("|")) | index($t) != null)
          or (try ($t | test("^(?:" + $m + ")$")) catch false)
        end;
    (.hooks[$ev] // []) as $arr
    | if ([$arr[] | select(type == "object" and covers($t))
           | (.hooks // [])[] | (.command // "") | select(endswith($n))] | length) > 0
      then .
      else ([$arr[] | (.matcher? == $t)] | index(true)) as $i
        | {"type": "command", "command": $c} as $h
        | if $i != null
          then .hooks[$ev][$i].hooks = ((.hooks[$ev][$i].hooks // []) + [$h])
          else .hooks[$ev] = ($arr + [{"matcher": $t, "hooks": [$h]}])
          end
      end
  ' "$SETTINGS_JSON" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    warn "Could not process ${SETTINGS_JSON} — skipping ${name}."
    return 0
  fi

  if [[ "$(jq -S -c . "$tmp")" == "$(jq -S -c . "$SETTINGS_JSON")" ]]; then
    say "${name} already registered in ${event} > ${tool}"
  else
    cat "$tmp" > "$SETTINGS_JSON"
    say "Registered ${name} in ${event} > ${tool}"
  fi
  rm -f "$tmp"
}

wire_codex() {
  info "Wiring Codex (~/.codex/) — skills only..."
  local skills_dir="${HOME}/.codex/skills"
  run mkdir -p "$skills_dir"
  for skill_dir in "${SCRIPT_DIR}/skills"/*/; do
    local skill_name
    skill_name=$(basename "$skill_dir")
    run ln -sfn "$skill_dir" "${skills_dir}/${skill_name}"
    say "Symlinked skill: ${skills_dir}/${skill_name}"
  done
  warn "Codex does not expose a hooks API — post-action-log.sh and post-log-reminder.sh are NOT registered."
}

wire_cursor() {
  info "Wiring Cursor (~/.cursor/) — skills only..."
  local skills_dir="${HOME}/.cursor/skills"
  run mkdir -p "$skills_dir"
  for skill_dir in "${SCRIPT_DIR}/skills"/*/; do
    local skill_name
    skill_name=$(basename "$skill_dir")
    run ln -sfn "$skill_dir" "${skills_dir}/${skill_name}"
    say "Symlinked skill: ${skills_dir}/${skill_name}"
  done
  warn "Cursor does not currently expose a hooks API — hooks are NOT registered."
}

wire_opencode() {
  info "Wiring OpenCode (~/.config/opencode/) — skills only..."
  local skills_dir="${HOME}/.config/opencode/skills"
  run mkdir -p "$skills_dir"
  for skill_dir in "${SCRIPT_DIR}/skills"/*/; do
    local skill_name
    skill_name=$(basename "$skill_dir")
    run ln -sfn "$skill_dir" "${skills_dir}/${skill_name}"
    say "Symlinked skill: ${skills_dir}/${skill_name}"
  done
  warn "OpenCode does not currently expose a hooks API — hooks are NOT registered."
}

# ── Step 6: Print shell exports ───────────────────────────────────────────────

print_shell_exports() {
  info "Suggested shell exports (add to ~/.zshrc or ~/.bashrc):"
  echo ""
  echo "    export PATH=\"${SCRIPT_DIR}/bin:\$PATH\""
  echo "    export CLOG_CONFIG=\"\${HOME}/.config/clog/config.yaml\""
  echo ""
  say "Do not auto-write to dotfiles. Copy the lines above and add them manually."
}

# ── Step 7: Verify ────────────────────────────────────────────────────────────

verify_install() {
  info "Verifying installation..."

  if [[ "$DRY_RUN" == "true" ]]; then
    say "[dry-run] Skipping verification."
    return 0
  fi

  local clog_bin="${SCRIPT_DIR}/bin/clog"
  if [[ ! -x "$clog_bin" ]]; then
    warn "bin/clog not found or not executable at: $clog_bin"
    return 1
  fi

  # Source config for log path
  # shellcheck source=lib/config.sh
  . "${SCRIPT_DIR}/lib/config.sh"
  load_config 2>/dev/null || {
    warn "Config not found — run setup again or write ~/.config/clog/config.yaml manually."
    return 1
  }

  say "Running: clog ACTION \"clog setup complete\" --agent setup"
  "$clog_bin" ACTION "clog setup complete" --agent setup

  local log_file="${CLOG_LOG_ROOT}/${CLOG_LOG_SUBDIR}/$(date +%Y%m%d).jsonl"
  if [[ -f "$log_file" ]]; then
    say "Verification entry:"
    tail -1 "$log_file" | jq .
    say "Log file: $log_file"
  else
    warn "Log file not found after write — check permissions on: $CLOG_LOG_ROOT"
    return 1
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "clog setup (version ${CLOG_VERSION})"
  echo "────────────────────────────────────────"
  [[ "$DRY_RUN" == "true" ]] && echo "  DRY RUN — no changes will be made"
  echo ""

  detect_existing_install
  check_dependencies
  detect_tools
  install_cli
  pick_paths
  write_config
  wire_tools
  print_shell_exports
  verify_install

  echo ""
  echo "Setup complete."
  echo ""
}

main "$@"
