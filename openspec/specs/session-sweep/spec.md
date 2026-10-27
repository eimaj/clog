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
