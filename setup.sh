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
  [[ "${ans,,}" == "y" ]]
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

  if [[ -f "${HOME}/.claude/hooks/clog.sh" ]]; then
    say "Found: ~/.claude/hooks/clog.sh"
    found=true
  fi
  if [[ -n "${CLOG_BIN:-}" ]]; then
    say "Found: \$CLOG_BIN=${CLOG_BIN}"
    found=true
  fi
  if [[ -n "${AI_LOG_ROOT:-}" ]]; then
    say "Found: \$AI_LOG_ROOT=${AI_LOG_ROOT}"
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
  for hook in post-action-log.sh post-log-reminder.sh; do
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
    return 0
  fi

  # Check if hooks already present
  local action_log_registered
  action_log_registered=$(jq -r '
    .hooks.PostToolUse // [] |
    map(select(.matcher == "Bash")) |
    .[0].hooks // [] |
    map(select(.command | test("post-action-log"))) |
    length
  ' "$SETTINGS_JSON" 2>/dev/null || echo "0")

  if [[ "$action_log_registered" -gt "0" ]]; then
    say "post-action-log.sh already registered — skipping."
    return 0
  fi

  # Build the two hook entries to add
  local hook_action_log="${HOME}/.claude/hooks/post-action-log.sh"
  local hook_log_reminder="${HOME}/.claude/hooks/post-log-reminder.sh"

  # Use jq to add hooks into PostToolUse > Bash hooks array
  local tmp_settings="${SETTINGS_JSON}.clog-setup.tmp"
  jq --arg al "$hook_action_log" --arg lr "$hook_log_reminder" '
    .hooks.PostToolUse = (
      .hooks.PostToolUse // [] |
      map(
        if .matcher == "Bash" then
          .hooks = (.hooks // []) + [
            {"type": "command", "command": $al},
            {"type": "command", "command": $lr}
          ]
        else . end
      )
    ) |
    # If no Bash PostToolUse matcher existed, add one
    if ([.hooks.PostToolUse[] | select(.matcher == "Bash")] | length) == 0 then
      .hooks.PostToolUse += [{"matcher": "Bash", "hooks": [
        {"type": "command", "command": $al},
        {"type": "command", "command": $lr}
      ]}]
    else . end
  ' "$SETTINGS_JSON" > "$tmp_settings" && mv "$tmp_settings" "$SETTINGS_JSON"

  say "Registered post-action-log.sh and post-log-reminder.sh in PostToolUse > Bash"
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
  detect_tools
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
