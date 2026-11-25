#!/usr/bin/env bash
# extract.sh <transcript> — list the state-changing tool calls in one Claude Code
# transcript as candidate records for localize.sh and gaps.sh.
#
# stdout: one JSON object per candidate, in transcript order:
#   {"timestamp":"YYYY-MM-DDTHH:MM:SSZ","type":"CODE|ACTION","summary":"…","why":"…"[,"file":"…"]}
# `timestamp` is the tool call's UTC timestamp with fractional seconds dropped.
#
# Candidates (assistant tool_use blocks only):
#   CODE    Edit, Write, MultiEdit, NotebookEdit (with `file`)
#   ACTION  Agent / Task dispatches
#   ACTION  MCP calls whose tool name starts with a mutating verb
#   ACTION  Bash calls with a part that changes repo or remote state. The command
#           is split on && || ; | and newlines, and every part is checked. The call
#           is skipped only when its single mutating part is one post-action-log.sh
#           logs: git commit, git push, gh pr create, or gh pr merge without --auto,
#           with no option before the subcommand (git -C / gh -R are reported).
#           A part carrying --dry-run changes nothing and is ignored, and heredoc
#           bodies (cat > f <<'EOF' … EOF) are file content, never commands.
# Lines that are not JSON, and records that are not assistant messages, are skipped.
# Transcript text is data: nothing from it is executed here.
# Exit 1 on a missing argument or an unreadable transcript.
set -euo pipefail

[[ $# -eq 1 && -n "$1" ]] || { echo "usage: extract.sh <transcript.jsonl>" >&2; exit 1; }
[[ -r "$1" ]] || { printf 'extract: cannot read %s\n' "$1" >&2; exit 1; }

jq -R -c '
  def ts: sub("\\.[0-9]+Z$"; "Z");
  def short($p): ($p // "" | tostring | split("/") | .[-2:] | join("/"));
  # Heredoc bodies are file content, not commands: drop them up to their terminator.
  def strip_heredocs: gsub("<<-?[[:space:]]*[\"'"'"']?(?<w>[A-Za-z_][A-Za-z0-9_]*)[\"'"'"']?(?<rest>[^\n]*)\n[\\s\\S]*?\n[[:space:]]*\\k<w>(?=\n|$)"; "<<\(.w)\(.rest)");
  # One command part, without leading keywords, subshell openers, env assignments.
  def norm: gsub("^[[:space:]]+|[[:space:]]+$"; "")
    | gsub("^((do|then|else|time)[[:space:]]+|[({][[:space:]]*)+"; "")
    | gsub("^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+"; "");
  def git_mut: test("^git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(commit|push|pull|merge|rebase|cherry-pick|revert|reset|rm|mv|tag[[:space:]]+[^-[:space:]][^[:space:]]*|tag[[:space:]]+-[adfs]|branch[[:space:]]+(-[dDmMcC]|--delete|--move|--copy)|worktree[[:space:]]+(add|remove|move|prune)|stash[[:space:]]+(push|pop|drop|apply|clear)|switch[[:space:]]+-[cC]|checkout[[:space:]]+-[bB])([[:space:]]|$)");
  def gh_mut: test("^gh([[:space:]]+-R[[:space:]]+[^[:space:]]+)?[[:space:]]+((pr|issue)[[:space:]]+(create|close|edit|comment|merge|ready|reopen|review|delete|lock)|release[[:space:]]+(create|delete|edit|upload)|repo[[:space:]]+(create|delete|edit|rename|archive)|api[[:space:]].*(-X|--method)[[:space:]]*(POST|PUT|PATCH|DELETE))([[:space:]]|$)");
  def other_mut: test("^(crrt[[:space:]]+(add|complete|edit|note|delete|rm)|trash)([[:space:]]|$)");
  # Logged by post-action-log.sh when it is the only mutating part.
  def hook_logged: test("^(git[[:space:]]+(commit|push)|gh[[:space:]]+pr[[:space:]]+(create|merge))([[:space:]]|$)")
    and (test("--(disable-)?auto([[:space:]]|$)") | not);
  # executeRead and execute_code only read; executeWrite and execute_code_write mutate.
  def mcp_mut: (split("__") | .[-1])
    | test("^(save|create|update|upsert|send|schedule|transition|add|delete|remove|edit|mark|merge|post|publish|archive|set|submit|resolve|share|unshare|trash|move|batch|execute|forward|respond|complete|close|assign|mute|link|unlink|enable|disable|cancel|retry|trigger|run)"; "i")
      and (test("^execute_?(read|code$)"; "i") | not);
  # Command text lands in the log: mask URL credentials, Authorization values, GitHub tokens.
  def redact: gsub("://[^/@[:space:]]+@"; "://***@")
    | gsub("(?<h>authorization:[[:space:]]*([a-z]+[[:space:]]+)?)[^\"'"'"'[:space:]]+"; "\(.h)***"; "i")
    | gsub("(gh[pousr]_|github_pat_)[A-Za-z0-9_]+"; "***");

  fromjson? | objects | select(.type == "assistant" and (.timestamp | type) == "string")
  | (.timestamp | ts) as $t
  | .message.content[]? | objects | select(.type == "tool_use")
  | if (.name | test("^(Edit|Write|MultiEdit|NotebookEdit)$")) then
      (.input.file_path // .input.notebook_path // "") as $f
      | {timestamp: $t, type: "CODE", summary: "\(.name) \(short($f))",
         why: "edit with no clog entry nearby", file: $f}
    elif (.name == "Agent" or .name == "Task") then
      {timestamp: $t, type: "ACTION",
       summary: "Dispatched subagent: \(.input.description // .input.subagent_type // "task")",
       why: "subagent dispatch not logged by the parent"}
    elif (.name | startswith("mcp__")) and (.name | mcp_mut) then
      ((.input.id // .input.identifier // .input.title // .input.name // .input.channel_id // .input.issueIdOrKey // "") | tostring | .[0:60]) as $ref
      | {timestamp: $t, type: "ACTION",
         summary: ("MCP \(.name | sub("^mcp__(claude_ai_)?"; ""))" + (if $ref == "" then "" else " \($ref)" end)),
         why: "MCP call not recognized as a state change"}
    elif .name == "Bash" then
      [ (.input.command // "") | strip_heredocs | splits("&&|\\|\\||;|\\||\n") | norm
        | select((git_mut or gh_mut or other_mut) and (test("--dry-run") | not)) ] as $parts
      | select(($parts | length) > 0)
      | select((($parts | length) == 1 and ($parts[0] | hook_logged)) | not)
      | {timestamp: $t, type: "ACTION",
         summary: ("Bash: " + ($parts | join(" && ") | gsub("[[:space:]]+"; " ") | redact | .[0:160])),
         why: "Bash mutation the post-action-log hook does not log (chain, git -C, gh -R, or no hook)"}
    else empty end
' "$1"
