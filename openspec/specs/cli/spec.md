# CLI Specification

## Purpose

The user-facing contract of `bin/clog`: positionals, flags, help, validation, exit codes and output streams. Reverse-engineered from the code at `b5d2927` (main) and verified by running the CLI against a scratch log root. This is the baseline; it describes what the tool does today, not what it should do. Proposed changes to this contract go through `openspec/changes/`.

## Requirements

### Requirement: Invocation shape
The CLI SHALL accept exactly two positional arguments, TYPE then summary, followed by zero or more long-form flags. Flags SHALL NOT be recognised before the positionals. There are no short flags other than `-h`.

#### Scenario: Flags after positionals
- **WHEN** the user runs `clog ACTION "deploy to staging" --repo my-repo --agent orchestrator`
- **THEN** an entry with `type` `ACTION`, `summary` `deploy to staging`, `repo` `my-repo`, `agent` `orchestrator` is appended and the exit code is 0

#### Scenario: Flag in the TYPE position
- **WHEN** the user runs `clog --repo x ACTION "s"`
- **THEN** stderr is `clog: unknown type '--repo' (expected DECISION | ACTION | CODE | PR | COMMIT | REPO | FOLLOWUP | LEARNING | LESSON)`, the exit code is 1 and nothing is written

### Requirement: Invocation through a symlink
The CLI SHALL resolve its own location through any chain of symlinks and SHALL load `lib/config.sh` and `lib/jsonl.sh` relative to the real file, so it works when installed as a symlink such as `~/.local/bin/clog` or `~/.claude/hooks/clog.sh`.

#### Scenario: Symlinked install
- **WHEN** `~/.local/bin/clog` is a symlink to `<repo>/bin/clog` and the user runs `clog ACTION "x"`
- **THEN** the entry is written exactly as when running `<repo>/bin/clog` directly

### Requirement: Help
The CLI SHALL print its usage text to stdout and exit 0 when the first argument is `--help` or `-h`. Help SHALL work without a config file and SHALL NOT be suppressed by `CLOG_DISABLE`. `--help` in any later position SHALL be treated as an ordinary argument.

#### Scenario: Help without config
- **WHEN** the user runs `clog --help` with `CLOG_CONFIG` pointing at a file that does not exist
- **THEN** stdout starts with `Usage: clog <TYPE> "<summary>" [flags]`, stderr is empty and the exit code is 0

#### Scenario: Help as a later argument
- **WHEN** the user runs `clog ACTION --help`
- **THEN** an entry with `summary` `--help` is appended and the exit code is 0

### Requirement: Missing positionals
The CLI SHALL exit 1 and print `clog: missing TYPE` or `clog: missing summary` followed by the usage text to stderr when the corresponding positional is absent or empty. Nothing SHALL be written.

#### Scenario: No arguments
- **WHEN** the user runs `clog`
- **THEN** stderr starts with `clog: missing TYPE`, stdout is empty and the exit code is 1

#### Scenario: Empty summary
- **WHEN** the user runs `clog ACTION ""`
- **THEN** stderr starts with `clog: missing summary` and the exit code is 1

### Requirement: TYPE validation
TYPE SHALL be one of `DECISION`, `ACTION`, `CODE`, `PR`, `COMMIT`, `REPO`, `FOLLOWUP`, `LEARNING`, `LESSON`, matched exactly and case-sensitively. Any other value SHALL exit 1 with a single stderr line `clog: unknown type '<value>' (expected DECISION | ACTION | CODE | PR | COMMIT | REPO | FOLLOWUP | LEARNING | LESSON)` and nothing written.

#### Scenario: Lowercase type
- **WHEN** the user runs `clog action "x"`
- **THEN** stderr is `clog: unknown type 'action' (expected …)` and the exit code is 1

#### Scenario: Each valid type
- **WHEN** the user runs `clog LESSON "Go interfaces are structural"`
- **THEN** an entry with `type` `LESSON` is appended and the exit code is 0

### Requirement: Summary content
The summary SHALL be stored verbatim as a JSON string. Double quotes, backslashes, newlines and tabs SHALL be JSON-escaped. A whitespace-only summary SHALL be accepted. No minimum length is enforced.

#### Scenario: Special characters
- **WHEN** the summary contains `"double"`, `'single'`, a backslash and a newline
- **THEN** the entry's `summary` field decodes back to the same characters and the line remains a single valid JSON object

#### Scenario: Whitespace-only summary
- **WHEN** the user runs `clog ACTION " "`
- **THEN** an entry with `summary` `" "` is appended and the exit code is 0

### Requirement: Optional flags
The CLI SHALL accept `--agent NAME`, `--repo NAME`, `--session ID`, `--model NAME`, `--file PATH`, `--family FAMILY`, `--kpi KPI`, `--date YYYY-MM-DD` and `--tags a,b`. Each value SHALL be stored verbatim in the field of the same name (except `--date`, which selects the file, and `--tags`, which is merged into the `tags` array). When a flag is repeated, the last occurrence SHALL win.

#### Scenario: All flags
- **WHEN** the user runs `clog ACTION "all" --agent a --repo r --session s --model m --file /f --family tooling --kpi effective`
- **THEN** the entry contains `agent` `a`, `repo` `r`, `session` `s`, `model` `m`, `file` `/f`, `family` `tooling`, `kpi` `effective`

#### Scenario: Repeated flag
- **WHEN** the user runs `clog ACTION "x" --repo first --repo second`
- **THEN** the entry's `repo` is `second`

### Requirement: Tags flag
`--tags a,b` SHALL take a comma-separated list and append it to the machine default tags for this entry only. The resulting `tags` array SHALL have each item trimmed, empty items dropped and duplicates removed keeping the first occurrence, defaults first.

#### Scenario: Defaults plus explicit tags
- **WHEN** `CLOG_DEFAULT_TAGS=jbook` and the user runs `clog ACTION "x" --tags "release, jbook ,web"`
- **THEN** the entry's `tags` is `["jbook","release","web"]`

#### Scenario: Explicit tags without defaults
- **WHEN** no default tags are configured and the user runs `clog ACTION "x" --tags a,b`
- **THEN** the entry's `tags` is `["a","b"]`

### Requirement: Unrecognised arguments
After the two positionals, the CLI SHALL reject an unrecognised `--` argument, an extra positional, and a recognised value flag given as the final argument, each with exit 1 and a single stderr line, before anything is written.

#### Scenario: Unknown flag
- **WHEN** the user runs `clog ACTION "x" --bogus --repo r`
- **THEN** stderr is `clog: unknown flag '--bogus'`, the exit code is 1 and nothing is written

#### Scenario: Extra positional
- **WHEN** the user runs `clog ACTION deploy to staging`
- **THEN** stderr is `clog: unexpected argument 'to'`, the exit code is 1 and nothing is written

#### Scenario: Flag without a value
- **WHEN** the user runs `clog ACTION "x" --repo`
- **THEN** stderr is `clog: --repo needs a value`, the exit code is 1 and nothing is written

### Requirement: Repo autodetection
When `--repo` is omitted, `repo` SHALL be the basename of `git rev-parse --show-toplevel` run from the current directory. Outside a git repository the field SHALL be omitted.

#### Scenario: Inside a repo
- **WHEN** the user runs `clog ACTION "x"` from a directory inside `~/Code/clog`
- **THEN** the entry's `repo` is `clog`

#### Scenario: Outside a repo
- **WHEN** the user runs `clog ACTION "x"` from `/private/tmp`
- **THEN** the entry has no `repo` field

### Requirement: Session resolution
When `--session` is omitted, `session` SHALL be the first non-empty of `CLAUDE_CODE_SESSION_ID`, `CLAUDE_SESSION_ID`, `CODEX_SESSION_ID`, `CURSOR_SESSION_ID`. If none is set, or the resolved value is the literal `unknown` or empty, the field SHALL be omitted.

#### Scenario: Precedence
- **WHEN** `CLAUDE_CODE_SESSION_ID=ccs` and `CLAUDE_SESSION_ID=cs` are both set
- **THEN** the entry's `session` is `ccs`

#### Scenario: Sentinel value
- **WHEN** the user runs `clog ACTION "x" --session unknown`
- **THEN** the entry has no `session` field

### Requirement: Family and KPI validation
When the configured `families` list is non-empty and `--family` is not in it, the entry SHALL still be written and SHALL gain `validation` `unknown_family`. The same SHALL apply to `--kpi` against `kpis` with `unknown_kpi`. Both misses SHALL yield `unknown_family,unknown_kpi`. Validation SHALL be silent (no stderr, exit 0). When the configured list is empty, no validation SHALL occur for that flag.

#### Scenario: Both unknown
- **WHEN** the config declares the example lists and the user runs `clog LEARNING "x" --family nope --kpi nah`
- **THEN** the entry contains `"validation":"unknown_family,unknown_kpi"`, nothing is printed and the exit code is 0

#### Scenario: No lists configured
- **WHEN** the config declares no `families` or `kpis` and the user runs `clog LEARNING "x" --family bogus --kpi bogus`
- **THEN** the entry contains `family` and `kpi` but no `validation` field

### Requirement: Date override
`--date` SHALL match `^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$`. A matching value SHALL select the file `YYYYMMDD.jsonl` for that date; the entry's `time` SHALL remain the current wall-clock time. Any non-matching value SHALL exit 1 with the single stderr line `clog: invalid --date '<value>' (expected YYYY-MM-DD)` and nothing written. Calendar validity beyond those ranges SHALL NOT be checked. An empty value SHALL be treated as no override.

#### Scenario: Backfill
- **WHEN** the user runs `clog ACTION "x" --date 2026-01-02`
- **THEN** the entry is appended to `<log_root>/<log_subdir>/20260102.jsonl`

#### Scenario: Path traversal attempt
- **WHEN** the user runs `clog ACTION "x" --date ../../evil`
- **THEN** stderr is `clog: invalid --date '../../evil' (expected YYYY-MM-DD)`, the exit code is 1 and no file is created anywhere

#### Scenario: Compact date
- **WHEN** the user runs `clog ACTION "x" --date 20260103`
- **THEN** the exit code is 1 with the invalid-date message

#### Scenario: Impossible day in range
- **WHEN** the user runs `clog ACTION "x" --date 2026-02-30`
- **THEN** the entry is appended to `20260230.jsonl` and the exit code is 0

### Requirement: Success output
On success the CLI SHALL print nothing to stdout or stderr and SHALL exit 0.

#### Scenario: Happy path
- **WHEN** the user runs `clog ACTION "happy path"`
- **THEN** stdout and stderr are empty, the exit code is 0 and one line was appended

### Requirement: Disable switch
When `CLOG_DISABLE` is exactly `1`, the CLI SHALL exit 0 without writing or printing anything, for any arguments, whether or not a config file exists. Other values of `CLOG_DISABLE` SHALL have no effect.

#### Scenario: Disabled
- **WHEN** `CLOG_DISABLE=1` and the user runs `clog ACTION "x"`
- **THEN** nothing is written and the exit code is 0

#### Scenario: Disabled but no config
- **WHEN** `CLOG_DISABLE=1` and `CLOG_CONFIG` points at a missing file
- **THEN** nothing is written, nothing is printed and the exit code is 0

#### Scenario: Other truthy value
- **WHEN** `CLOG_DISABLE=true` and the user runs `clog ACTION "x"`
- **THEN** the entry is written

### Requirement: Missing config
When the config file does not exist and `CLOG_DISABLE` is not `1`, the CLI SHALL print `clog: no config at <path>. Run setup.sh to create one.` to stderr and exit 1 before reading any argument other than `--help`/`-h`.

#### Scenario: No config
- **WHEN** `CLOG_CONFIG=/nonexistent/cfg.yaml` and the user runs `clog ACTION "x"`
- **THEN** stderr is `clog: no config at /nonexistent/cfg.yaml. Run setup.sh to create one.` and the exit code is 1

### Requirement: Unwritable destination
When the log directory cannot be created or the log file cannot be appended, the CLI SHALL exit 1 with the underlying shell error on stderr and SHALL NOT print a `clog:`-prefixed message.

#### Scenario: Read-only directory
- **WHEN** `<log_root>/<log_subdir>` exists with mode 555
- **THEN** stderr contains `Permission denied` and the exit code is 1

### Requirement: Missing jq
When `jq` is not on PATH, the CLI SHALL fail with exit 127 and `jq: command not found` on stderr. No dependency check precedes the failure.

#### Scenario: jq absent
- **WHEN** PATH contains no `jq` and the user runs `clog ACTION "x"`
- **THEN** the exit code is 127

### Requirement: Auto-commit
When `auto_commit.enabled` resolves to `true` and `auto_commit.repo_root` is non-empty, the CLI SHALL, after appending the entry, run `git -C <repo_root> add -- <log directory>` (the absolute path, which git accepts inside the worktree) and then `git commit` with `auto_commit.message`. A failing `git add` or `git commit` SHALL be ignored. The entry SHALL remain on disk whatever the outcome.

#### Scenario: Disabled by default
- **WHEN** the config leaves `auto_commit.enabled` at `false`
- **THEN** no git command runs after the entry is appended

### Requirement: Auto-commit failures do not fail the CLI
A failing `git add` or `git commit` during auto-commit SHALL NOT change the CLI's outcome: the entry is already written, the exit status is 0 and nothing is printed for the failure. The CLI SHALL NOT depend on GNU `realpath`.

#### Scenario: Enabled on macOS
- **WHEN** auto-commit is enabled with `repo_root` set to a git repository containing the log directory, on macOS
- **THEN** the entry is written, the exit code is 0 and a commit containing the log file exists

#### Scenario: Git failure
- **WHEN** auto-commit is enabled and `repo_root` is not a git repository
- **THEN** the entry is written, the exit code is 0 and nothing is printed
