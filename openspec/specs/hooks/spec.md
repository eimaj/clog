# Hooks Specification

## Purpose

The five Claude Code hooks under `hooks/` and what each writes or prints. Reverse-engineered from the scripts at `b5d2927` (main) and verified by piping fixture JSON into each hook with a scratch config.

## Requirements

### Requirement: Hook exit status
Every hook SHALL exit 0 on every path and SHALL exit 0 silently when `CLOG_DISABLE` is exactly `1`.

#### Scenario: Disabled
- **WHEN** any hook runs with `CLOG_DISABLE=1`
- **THEN** it exits 0, prints nothing and writes nothing

### Requirement: CLI resolution in hooks
Hooks that invoke the CLI SHALL resolve it as: `clog` on PATH, else `$CLOG_BIN`, else `../bin/clog` relative to the hook, and SHALL discard the CLI's stderr and exit status. `post-write-clog.sh` SHALL NOT honour `$CLOG_BIN` (it clears the variable before checking it).

#### Scenario: CLI failure is swallowed
- **WHEN** a hook calls the CLI and the CLI exits non-zero
- **THEN** the hook still exits 0 and prints nothing about the failure

### Requirement: Hooks without config
When the config file is missing, `load_config --hook` returns 0 without setting any `CLOG_*` variable, so the hook SHALL continue with those variables unset: it SHALL never append a log entry (the CLI refuses without a config), but it MAY still print its advisory and touch its marker file.

#### Scenario: Missing config, writing hook
- **WHEN** `post-action-log.sh` runs with `CLOG_CONFIG` pointing at a missing file and a `git commit` command
- **THEN** it exits 0, prints nothing and no log file is created

#### Scenario: Missing config, advisory hook
- **WHEN** `post-log-reminder.sh` runs with `CLOG_CONFIG` pointing at a missing file
- **THEN** it exits 0 and prints `WARNING: No log entries today. …` because the unset log root resolves to a file that does not exist

### Requirement: post-action-log.sh triggers
On PostToolUse for Bash, the hook SHALL read `tool_input.command` and write at most one entry: `COMMIT` when the command contains `git commit`, `PR` when it contains `gh pr create`, or `ACTION` `pushed <branch> (<repo>)` when it contains `git push`. The `COMMIT` summary SHALL be the first `-m "…"` or `-m '…'` value, else the HEAD subject; the `PR` summary SHALL be the `--title "…"` value.

#### Scenario: Commit with message
- **WHEN** the hook receives `{"tool_input":{"command":"git commit -m \"feat(x): hook test\""}}`
- **THEN** a `COMMIT` entry with `summary` `feat(x): hook test` is appended

#### Scenario: Several commits in one command
- **WHEN** the command string contains two `git commit -m` invocations
- **THEN** only one `COMMIT` entry is written, for the first message

#### Scenario: Unrelated command
- **WHEN** the command is `ls`
- **THEN** nothing is written

### Requirement: post-action-log.sh trigger matching
The triggers SHALL match `git` immediately followed by `commit` or `push` (whitespace only), so `git -C <dir> commit` SHALL NOT trigger on its own. A `gh pr create` without `--title` SHALL write nothing, because the empty summary is rejected by the CLI.

#### Scenario: Flag between git and commit
- **WHEN** the command is `git -C ~/Code/clog commit -m "x"`
- **THEN** nothing is written

#### Scenario: PR without a title
- **WHEN** the command is `gh pr create --fill`
- **THEN** nothing is written

### Requirement: post-action-log.sh repository and commit marker
The hook SHALL resolve the repository from the first `git -C <dir>` or leading `cd <dir>` anywhere in the command, else from `$HOME`. For `COMMIT` entries it SHALL rewrite the last line of the log file (delete-and-rewrite via a temp file, not an append) to add `commit` with the short SHA whenever a SHA resolves, even if the CLI wrote nothing.

#### Scenario: Command names the repo
- **WHEN** the command is `cd ~/Code/clog && git commit -m "x"`
- **THEN** the `COMMIT` entry carries `repo` `clog` and `commit` set to the new HEAD's short SHA

#### Scenario: Command does not name the repo
- **WHEN** the command is `git commit -m "x"` and `$HOME` is not a git checkout
- **THEN** the `COMMIT` entry has no `commit` field

### Requirement: post-action-log.sh auto-commit
After writing, the hook SHALL run its own auto-commit when `auto_commit.enabled` is true, using `logs` as the path when `realpath --relative-to` fails, and SHALL ignore any git failure.

#### Scenario: Auto-commit disabled
- **WHEN** `auto_commit.enabled` is `false`
- **THEN** the hook runs no git command after writing

### Requirement: post-log-reminder.sh warning
On PostToolUse for Bash and Agent, the hook SHALL print `WARNING: Last log entry was <N>m ago. Log actions with: clog <TYPE> "<summary>"` to stdout when today's log file is older than `reminder_threshold_seconds`, or `WARNING: No log entries today. …` when the file does not exist. A threshold of `0` SHALL disable the hook.

#### Scenario: Stale log
- **WHEN** today's file was last modified longer ago than the threshold and no marker is fresh
- **THEN** the warning is printed on stdout

#### Scenario: No file today
- **WHEN** today's file does not exist
- **THEN** the "No log entries today" warning is printed on stdout

### Requirement: post-log-reminder.sh self-log
On each warning the hook SHALL write a `LEARNING` entry with `agent` `hook-post-log` when a CLI can be resolved (the warning is still printed when none can). It SHALL add `--family interactive --kpi prompt_gap` whenever the configured lists are non-empty, even if those values are not in the lists, in which case the entry carries `validation`.

#### Scenario: Self-log on warning
- **WHEN** a warning is printed with the example lists configured
- **THEN** a `LEARNING` entry with `agent` `hook-post-log`, `family` `interactive` and `kpi` `prompt_gap` is appended

#### Scenario: Custom lists without those values
- **WHEN** the configured `families` list does not contain `interactive`
- **THEN** the self-logged entry carries `validation` `unknown_family`

### Requirement: post-log-reminder.sh throttle
The hook SHALL touch a single marker file `$TMPDIR/clog-reminder-warned`, shared across sessions, on each warning, and SHALL print nothing while that marker is younger than the threshold.

#### Scenario: Within window
- **WHEN** the marker file is younger than the threshold
- **THEN** nothing is printed and nothing is written

### Requirement: post-edit-log-check.sh
On PostToolUse for Edit, Write, MultiEdit and NotebookEdit, the hook SHALL count edits since the log file's mtime last changed, per session (`CLAUDE_SESSION_ID`, else `CODEX_SESSION_ID`, else `CURSOR_SESSION_ID`, else `default`), and SHALL print `LEDGER: <N> edits since last clog entry. Log a CODE entry before continuing.` to stderr on every invocation where the count is at or above `CLOG_EDIT_THRESHOLD` (default 3; `0` disables). It SHALL write nothing to the log.

#### Scenario: Third and fourth edits
- **WHEN** four edit events arrive with no new log entry between them
- **THEN** the third and the fourth invocations each print the LEDGER line on stderr

### Requirement: post-write-clog.sh
On PostToolUse for Edit, Write, MultiEdit and NotebookEdit, the hook SHALL write a `CODE` entry `auto: wrote <path>` with `--file <path>`, `--session` from the payload's `session_id` (else the session env chain), `--model` from `CLAUDE_MODEL` and `--repo` from the git root containing the file. It SHALL do nothing when the payload has no path, and SHALL exit silently with no inline fallback when no CLI can be resolved.

#### Scenario: Write event
- **WHEN** the hook receives `{"tool_name":"Write","session_id":"s1","tool_input":{"file_path":"~/Code/clog/README.md"}}`
- **THEN** a `CODE` entry with `summary` `auto: wrote /Users/<user>/Code/clog/README.md`, `session` `s1` and `file` set to the same absolute path is appended

### Requirement: post-write-clog.sh path handling
A leading `~` in the payload path SHALL be expanded to the home directory; any other path SHALL be passed through unchanged, so a relative path stays relative.

#### Scenario: Relative path
- **WHEN** the payload path is `rel/x.txt`
- **THEN** the entry's `file` is `rel/x.txt`

### Requirement: pre-agent-clog.sh
On PreToolUse for Agent, the hook SHALL write an `ACTION` entry `dispatch <subagent_type> (<model>) — <description>` with `--repo` from the current directory's git root. It SHALL write nothing when `description` is empty.

#### Scenario: Dispatch with description
- **WHEN** the hook receives `{"tool_input":{"description":"audit thing","subagent_type":"Explore","model":"haiku"}}`
- **THEN** an `ACTION` entry with `summary` `dispatch Explore (haiku) — audit thing` is appended

#### Scenario: Dispatch without description
- **WHEN** the payload has no `description`
- **THEN** nothing is written

### Requirement: pre-agent-clog.sh summary defaults
The model part SHALL be omitted when `model` is absent. The type SHALL default to `claude` only when `subagent_type` is absent or null; an empty string SHALL yield `dispatch  — <description>`. The inline fallback path (no CLI resolvable) SHALL emit the same entry without `clog_version` and without `session`.

#### Scenario: Empty subagent type
- **WHEN** the payload has `"subagent_type":""` and `"description":"d1"`
- **THEN** the entry's `summary` is `dispatch  — d1`

### Requirement: Installer coverage
`setup.sh` SHALL symlink `post-action-log.sh`, `post-log-reminder.sh`, `post-edit-log-check.sh`, `post-write-clog.sh` and `pre-agent-clog.sh` into `~/.claude/hooks/`, and SHALL also symlink `bin/clog` there as `clog.sh`. A `clog.sh` whose `realpath` equals that of this repo's `bin/clog` (relative link, `/private` prefix or chained symlinks included) SHALL NOT count as an existing install; a link to another clone or a regular file SHALL. `$AI_LOG_ROOT` SHALL NOT.

#### Scenario: Symlinks after wiring
- **WHEN** `setup.sh` wires Claude Code
- **THEN** `~/.claude/hooks/` contains symlinks for all five hooks and `clog.sh`

#### Scenario: Re-run after install
- **WHEN** `~/.claude/hooks/clog.sh` links to this repo's `bin/clog` and `setup.sh` runs without `--migrate`
- **THEN** it does not stop with the existing-install warning

### Requirement: Installer hook registration
`setup.sh` SHALL register all five hooks in an existing `~/.claude/settings.json` through one routine, `register_hook EVENT TOOL HOOK_PATH`, called once per (event, tool, hook), and SHALL skip registration when the file is absent. Each call is evaluated independently, so an earlier registration never blocks a later one.

#### Scenario: Fresh install with settings.json
- **WHEN** `setup.sh` wires Claude Code and `settings.json` exists with none of the hooks registered
- **THEN** under `PostToolUse` it gains `post-action-log.sh` and `post-log-reminder.sh` on Bash, `post-edit-log-check.sh` and `post-write-clog.sh` on Edit, Write, MultiEdit and NotebookEdit, and `post-log-reminder.sh` on Agent; under `PreToolUse` it gains `pre-agent-clog.sh` on Agent

#### Scenario: Re-run with the edit hook present
- **WHEN** `post-edit-log-check.sh` is already registered but the Agent, `post-write-clog.sh` and `pre-agent-clog.sh` registrations are missing
- **THEN** the missing registrations are added and nothing already present is duplicated

### Requirement: Hook registration coverage check
A hook SHALL count as already registered when any entry under that event whose matcher covers the tool runs a command that contains the hook file name (`HOOK_NAME`). A matcher covers a tool when it is empty or absent, equals the tool, is a `|`-separated list containing it, or is a regex matching it. Hooks without a `command` SHALL be ignored, and a covered hook SHALL NOT be added again.

#### Scenario: Quoted, wrapped or suffixed command
- **WHEN** the command is `"$HOME/.claude/hooks/post-action-log.sh"`, `bash /x/post-log-reminder.sh --quiet`, or `/x/post-log-reminder.sh ` with a trailing space
- **THEN** the hook counts as registered and is not added again

#### Scenario: Differently named hook with the same suffix (accepted)
- **WHEN** the command is `/x/my-post-action-log.sh`
- **THEN** `post-action-log.sh` counts as registered, as it did before the stricter check

#### Scenario: Regex matcher already covers the edit tools
- **WHEN** `PostToolUse` has one entry with matcher `Edit|Write|MultiEdit|NotebookEdit` running both edit hooks
- **THEN** no entry is added for either hook

### Requirement: Hook registration placement
An uncovered hook SHALL be added to the first entry under the event whose matcher equals the tool exactly, else a new `{matcher: TOOL, hooks: [...]}` entry SHALL be appended. It SHALL NOT be added to a second entry with the same matcher.

#### Scenario: Two Bash entries
- **WHEN** `PostToolUse` has two entries with matcher `Bash` and neither runs `post-action-log.sh`
- **THEN** it is added to the first entry only

### Requirement: Hook registration write-through
`setup.sh` SHALL write settings by `cat` from a temp file into `~/.claude/settings.json`, never by `mv`, so a symlinked file keeps its link. It SHALL write only when `jq -S -c` of the new document differs from the old, and SHALL print `Registered` only then, else `already registered`.

#### Scenario: Fully registered file with different indentation
- **WHEN** every hook is already registered and the file is indented with four spaces
- **THEN** the file is byte-identical afterwards and every call prints `already registered`

### Requirement: Hook registration write failure
If the write fails (read-only file or symlink target), `register_hook` SHALL print one warning naming the path and the reason, leave the file unchanged, and return success so setup continues. The temp file SHALL be removed on every exit path.

#### Scenario: Read-only settings file
- **WHEN** `settings.json` is read-only and a hook is unregistered
- **THEN** a warning names the path and `Permission denied`, the file is unchanged, no temp file remains, and setup continues

### Requirement: Hook registration on invalid JSON
When `settings.json` is not valid JSON, `setup.sh` SHALL print one warning naming the file, skip all registration, leave no temp file behind and continue with exit status 0.

#### Scenario: Corrupt settings file
- **WHEN** `settings.json` contains truncated JSON
- **THEN** one warning is printed, the file is unchanged and `setup.sh` does not fail
