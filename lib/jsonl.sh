#!/usr/bin/env bash
# lib/jsonl.sh — shared JSONL entry builder for bin/clog and hooks.
# Usage: source this file, then call build_entry TYPE SUMMARY AGENT REPO SESSION MODEL FILE_PATH FAMILY KPI CLOG_VERSION [TAGS] [LOGGED_AT]
#   TAGS is a comma-separated string (defaults from $CLOG_DEFAULT_TAGS, then --tags); optional.
#   Items are trimmed, empty items dropped, duplicates removed keeping first occurrence.
#   LOGGED_AT (YYYY-MM-DDTHH:MM:SS, write time of a backfilled entry) is emitted after tags; empty omits it.
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
  local tags="${11:-}"
  local logged_at="${12:-}"

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
    --arg tags "$tags" \
    --arg logged_at "$logged_at" \
    '{time: $time, type: $type, summary: $summary} +
     (if $agent != "" then {agent: $agent} else {} end) +
     (if $repo != "" then {repo: $repo} else {} end) +
     (if $session != "unknown" and $session != "" then {session: $session} else {} end) +
     (if $model != "" then {model: $model} else {} end) +
     (if $file != "" then {file: $file} else {} end) +
     (if $family != "" then {family: $family} else {} end) +
     (if $kpi != "" then {kpi: $kpi} else {} end) +
     (if $clog_version != "" then {clog_version: $clog_version} else {} end) +
     (if $tags != "" then {tags: ($tags | split(",")
        | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))
        | reduce .[] as $t ([]; if index([$t]) then . else . + [$t] end))} else {} end) +
     (if $logged_at != "" then {logged_at: $logged_at} else {} end)'
}
