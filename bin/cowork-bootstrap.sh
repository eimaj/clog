#!/usr/bin/env bash
# cowork-bootstrap.sh — wire clog into a Cowork sandbox session.
#
# Cowork's shell runs in an isolated Linux VM. Connected folders appear under
# /sessions/<session>/mnt/. This script recreates the Mac-equivalent paths as
# $HOME-relative symlinks so clog and its config work unmodified.
#
# Requires these folders connected to the Cowork project:
#   ~/Code/clog      (this repo)
#   ~/Code/logs      (log root)
#   ~/.config/clog   (config)
#
# Idempotent. Run at task start:
#   bash /sessions/*/mnt/clog/bin/cowork-bootstrap.sh
# Then invoke clog as: "$HOME/.local/bin/clog" <TYPE> "<summary>"
set -euo pipefail

# Resolve the mount root from this script's own location (<mnt>/clog/bin/…)
CLOG_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MNT="$(dirname "$CLOG_DIR")"

[[ -d "$MNT/logs" ]] || { echo "cowork-bootstrap: ~/Code/logs is not connected to this project" >&2; exit 1; }

# Find the config mount (name varies with how it was connected)
CONFIG_DIR=""
for d in "$MNT/.config--clog" "$MNT/clog-config"; do
  [[ -f "$d/config.yaml" ]] && CONFIG_DIR="$d" && break
done
[[ -n "$CONFIG_DIR" ]] || { echo "cowork-bootstrap: ~/.config/clog is not connected to this project" >&2; exit 1; }

mkdir -p "$HOME/Code" "$HOME/.local/bin" "$HOME/.config"
ln -sfn "$MNT/logs"            "$HOME/Code/logs"
ln -sfn "$CLOG_DIR"            "$HOME/Code/clog"
ln -sfn "$CLOG_DIR/bin/clog"   "$HOME/.local/bin/clog"
ln -sfn "$CONFIG_DIR"          "$HOME/.config/clog"

echo "cowork-bootstrap: clog ready at $HOME/.local/bin/clog (logs -> $MNT/logs)"
