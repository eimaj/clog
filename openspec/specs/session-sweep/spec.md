# session-sweep Specification

## Purpose
Sweeps one or more named Claude Code sessions for state-changing actions that were never logged, backfills them on the right session and day, and reports per session so callers such as conductor's `/pm-end` and `/pa-eod` can use the result directly.

## Requirements

### Requirement: Target named sessions
`clog-sweep-sessions` SHALL accept one or more session ids and sweep each one, whether or not it is the current session or still running.

#### Scenario: Closed pane
- **WHEN** it is given the id of a session whose pane has closed
- **THEN** that session is swept like any other

### Requirement: Find transcripts by id
The skill SHALL find each transcript at `~/.claude/projects/*/<sid>.jsonl` without depending on the current folder, and SHALL report a session whose transcript is missing with `status: "no_transcript"` instead of failing the whole run.

#### Scenario: Missing transcript
- **WHEN** one of three ids has no transcript
- **THEN** the other two are swept and that one is reported as `no_transcript`

### Requirement: Compare against the right days
The skill SHALL compare each transcript with the log files for every date the session ran, or only the dates given with `--date`.

#### Scenario: Session across midnight
- **WHEN** a session ran from 23:00 to 01:00
- **THEN** both days' log files are read for it

### Requirement: Backfill on session and date
Each unlogged action SHALL be backfilled with `--session <sid>`, `--date <day of the action>` and `--time <time of the action>`, paired with one LEARNING naming why it was missed, as `clog-sweep` pairs them.

#### Scenario: Yesterday's gap
- **WHEN** a gap is found in yesterday's part of a session
- **THEN** the backfilled entry and its LEARNING are written to yesterday's file with that session id, the action's time, and a `logged_at` of now

### Requirement: No duplicate backfill
Running the skill again on the same sessions SHALL NOT backfill an action that already has a matching entry, including one this skill wrote earlier.

#### Scenario: Re-run
- **WHEN** the skill runs twice on the same session
- **THEN** the second run reports zero gaps and writes nothing

### Requirement: Per-session result
The skill SHALL return one JSON object per session with `sid`, `transcript`, `dates`, `gaps`, `backfilled`, `learnings` and `status`, plus the human-readable punch list.

#### Scenario: Caller reads result
- **WHEN** `/pa-eod` calls the skill for four sessions
- **THEN** it receives four JSON objects it can put in its report without reading the log

### Requirement: clog-sweep unchanged
`clog-sweep` SHALL keep its current-session behavior; cross-session sweeping MUST live only in `clog-sweep-sessions`.

#### Scenario: Existing trigger
- **WHEN** the user says "clog it"
- **THEN** `clog-sweep` runs on the current session exactly as before

### Requirement: Unlogged merges are state-changers
`clog-sweep` and `clog-sweep-sessions` SHALL treat `gh pr merge` and any other Bash-run mutation that no hook logs as a state-changing action, and SHALL skip as auto-logged only the actions `post-action-log.sh` actually logs.

#### Scenario: Merge with no log entry
- **WHEN** the transcript holds a `gh pr merge` call and the day's log has no matching entry within the window
- **THEN** it is reported as a missing entry with a proposed `clog ACTION` command

#### Scenario: Auto-logged action
- **WHEN** the transcript holds a `git commit` that `post-action-log.sh` logged
- **THEN** it is not reported as missing

### Requirement: Helper fallback is announced
When `clog-sweep` cannot resolve the `clog-sweep-sessions` helper scripts, it SHALL tell the user it fell back to a current-session inline scan and SHALL name that days other than the transcript's last day were not checked.

#### Scenario: Helper skill not installed
- **WHEN** `clog-sweep` runs and `clog-sweep-sessions/scripts/resolve.sh` does not exist
- **THEN** the sweep still runs on the current session and its summary line states the fallback and that earlier session days were not checked

### Requirement: Logged merges are not reported as gaps
`clog-sweep` and `clog-sweep-sessions` SHALL skip a single `gh pr merge` command without `--auto` as auto-logged, because `post-action-log.sh` logs it, SHALL check `gh` with an option before the subcommand (`gh -R <repo> pr merge`) against the log because the hook does not match it, and SHALL keep checking every part of a chained command.

#### Scenario: Merge logged by the hook
- **WHEN** the transcript holds `gh pr merge 27` and the day's log has the `merged PR #27` entry
- **THEN** it is not reported as missing

#### Scenario: Merge chained with an unlogged mutation
- **WHEN** the transcript holds `gh pr merge 27 && git tag v1`
- **THEN** the `git tag` part is checked against the log
