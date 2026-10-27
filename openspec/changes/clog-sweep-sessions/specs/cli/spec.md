## ADDED Requirements

### Requirement: Time override
`--time` SHALL match `^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$`. A matching value SHALL become the entry's `time`, with or without `--date`. Any non-matching value SHALL exit 1 with the single stderr line `clog: invalid --time '<value>' (expected HH:MM:SS)` and nothing written. In this and the `--date` message, a value containing control characters SHALL be printed in `printf %q` form so the line stays single. An empty value SHALL be treated as no override.

#### Scenario: Backfill with time
- **WHEN** the user runs `clog ACTION "x" --date 2026-01-02 --time 14:05:09`
- **THEN** the entry is appended to `20260102.jsonl` with `time` `14:05:09`

#### Scenario: Invalid time
- **WHEN** the user runs `clog ACTION "x" --time 25:00:00`
- **THEN** stderr is `clog: invalid --time '25:00:00' (expected HH:MM:SS)`, the exit code is 1 and nothing is written

#### Scenario: Short form rejected
- **WHEN** the user runs `clog ACTION "x" --time 14:05`
- **THEN** the exit code is 1 with the invalid-time message

## MODIFIED Requirements

### Requirement: Optional flags
The CLI SHALL accept `--agent NAME`, `--repo NAME`, `--session ID`, `--model NAME`, `--file PATH`, `--family FAMILY`, `--kpi KPI`, `--date YYYY-MM-DD`, `--time HH:MM:SS` and `--tags a,b`. Each value SHALL be stored verbatim in the field of the same name (except `--date`, which selects the file, `--time`, which sets `time`, and `--tags`, which is merged into the `tags` array). When a flag is repeated, the last occurrence SHALL win.

#### Scenario: All flags
- **WHEN** the user runs `clog ACTION "all" --agent a --repo r --session s --model m --file /f --family tooling --kpi effective`
- **THEN** the entry contains `agent` `a`, `repo` `r`, `session` `s`, `model` `m`, `file` `/f`, `family` `tooling`, `kpi` `effective`

#### Scenario: Repeated flag
- **WHEN** the user runs `clog ACTION "x" --repo first --repo second`
- **THEN** the entry's `repo` is `second`

### Requirement: Unrecognised arguments
After the two positionals, the CLI SHALL reject an unrecognised `--` argument, an extra positional, a recognised value flag given as the final argument, and a recognised value flag followed by another recognised flag name (`--agent`, `--repo`, `--session`, `--model`, `--file`, `--family`, `--kpi`, `--date`, `--time`, `--tags`, `--echo`) instead of a value, each with exit 1 and a single stderr line, before anything is written.

#### Scenario: Unknown flag
- **WHEN** the user runs `clog ACTION "x" --bogus --repo r`
- **THEN** stderr is `clog: unknown flag '--bogus'`, the exit code is 1 and nothing is written

#### Scenario: Extra positional
- **WHEN** the user runs `clog ACTION deploy to staging`
- **THEN** stderr is `clog: unexpected argument 'to'`, the exit code is 1 and nothing is written

#### Scenario: Flag without a value
- **WHEN** the user runs `clog ACTION "x" --repo`
- **THEN** stderr is `clog: --repo needs a value`, the exit code is 1 and nothing is written

#### Scenario: Flag followed by a flag
- **WHEN** the user runs `clog ACTION "x" --repo --echo`
- **THEN** stderr is `clog: --repo needs a value`, the exit code is 1 and nothing is written

#### Scenario: Value that merely starts with dashes
- **WHEN** the user runs `clog ACTION "x" --repo --not-a-flag --echo`
- **THEN** the entry's `repo` is `--not-a-flag` and the entry is echoed

#### Scenario: Time without a value
- **WHEN** the user runs `clog ACTION "x" --time`
- **THEN** stderr is `clog: --time needs a value`, the exit code is 1 and nothing is written

### Requirement: Date override
`--date` SHALL match `^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$`. A matching value SHALL select the file `YYYYMMDD.jsonl` for that date; the entry's `time` SHALL remain the current wall-clock time unless `--time` is given. Any non-matching value SHALL exit 1 with the single stderr line `clog: invalid --date '<value>' (expected YYYY-MM-DD)` and nothing written. Calendar validity beyond those ranges SHALL NOT be checked. An empty value SHALL be treated as no override.

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
