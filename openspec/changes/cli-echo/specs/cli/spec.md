# Delta for cli

## ADDED Requirements

### Requirement: Echo flag
The CLI SHALL accept `--echo` (no value) after the two positionals. When given and the entry is appended, the CLI SHALL print the exact JSON line it appended to stdout, followed by a newline, and exit 0. When nothing is written (`CLOG_DISABLE=1`, or any validation failure) the CLI SHALL print nothing to stdout.

#### Scenario: Echo on success
- **WHEN** the user runs `clog ACTION "deploy" --repo r --echo`
- **THEN** stdout is the single line that was appended to the day's file and the exit code is 0

#### Scenario: Echo while disabled
- **WHEN** `CLOG_DISABLE=1` and the user runs `clog ACTION "x" --echo`
- **THEN** stdout is empty, nothing is written and the exit code is 0

#### Scenario: Echo on a rejected entry
- **WHEN** the user runs `clog ACTION "x" --date notadate --echo`
- **THEN** stdout is empty, stderr carries the invalid-date message and the exit code is 1

## MODIFIED Requirements

### Requirement: Success output
On success the CLI SHALL print nothing to stderr and SHALL exit 0. Stdout SHALL be empty unless `--echo` is given, in which case it SHALL contain exactly the appended line.
(Previously: on success the CLI printed nothing to stdout or stderr and exited 0.)

#### Scenario: Happy path
- **WHEN** the user runs `clog ACTION "happy path"`
- **THEN** stdout and stderr are empty, the exit code is 0 and one line was appended

#### Scenario: Happy path with echo
- **WHEN** the user runs `clog ACTION "happy path" --echo`
- **THEN** stdout is the appended line, stderr is empty and the exit code is 0
