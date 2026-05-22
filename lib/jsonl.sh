#!/usr/bin/env bash
# lib/jsonl.sh — shared JSONL entry builder for bin/clog and hooks.
# Usage: source this file, then call build_entry TYPE SUMMARY AGENT REPO SESSION MODEL FILE_PATH FAMILY KPI CLOG_VERSION
# Prints a single JSON line to stdout. Empty fields are omitted.

build_entry() {
  local type="$1"
  local summary="$2"
  local agent="$3"
  local repo="$4"
  local session="$5"
  local model="$6"
  local file_path="$7"
  local family="$8"
  local kpi="$9"
  local clog_version="${10:-}"

  jq -nc \
    --arg time "$(date +%H:%M:%S)" \
    --arg type "$type" \
    --arg summary "$summary" \
    --arg agent "$agent" \
    --arg repo "$repo" \
    --arg session "$session" \
    --arg model "$model" \
    --arg file "$file_path" \
    --arg family "$family" \
    --arg kpi "$kpi" \
    --arg clog_version "$clog_version" \
    '{time: $time, type: $type, summary: $summary} +
     (if $agent != "" then {agent: $agent} else {} end) +
     (if $repo != "" then {repo: $repo} else {} end) +
     (if $session != "unknown" and $session != "" then {session: $session} else {} end) +
     (if $model != "" then {model: $model} else {} end) +
     (if $file != "" then {file: $file} else {} end) +
     (if $family != "" then {family: $family} else {} end) +
     (if $kpi != "" then {kpi: $kpi} else {} end) +
     (if $clog_version != "" then {clog_version: $clog_version} else {} end)'
}
