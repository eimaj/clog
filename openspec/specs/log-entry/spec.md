# Log Entry Specification

## Purpose

The on-disk contract: where entries go and what each JSON line contains. Reverse-engineered from `bin/clog` and `lib/jsonl.sh` at `b5d2927` (main). Readers (`clog-day`, `clog-week`, `clog-lessons`, `clog-search`, `clog-replay`) depend on this shape.

## Requirements

### Requirement: File location and naming
Entries SHALL be appended to `<log_root>/<log_subdir>/YYYYMMDD.jsonl`, where the date is the local calendar date at write time or the `--date` value with dashes removed. The directory SHALL be created on demand. Files SHALL only ever be appended to by the CLI.

#### Scenario: First entry of a day
- **WHEN** no file exists for today and an entry is written
- **THEN** the directory and the file are created and the file contains exactly one line

### Requirement: One JSON object per line
Each entry SHALL be a single-line JSON object terminated by a newline, produced with `jq -c`. Values SHALL be JSON-escaped so any summary remains one line.

#### Scenario: Multi-line summary
- **WHEN** the summary contains a newline
- **THEN** the file gains exactly one line containing `\n` inside the summary string

### Requirement: Required fields
Every entry SHALL contain `time` (string `HH:MM:SS`, local wall-clock at write, or the `--time` value when given), `type` (one of the nine types) and `summary` (string), in that order, as the first three keys.

#### Scenario: Minimal entry
- **WHEN** the user runs `clog FOLLOWUP "investigate hooks API"` outside a git repo with no session variable set, appending to a day file that already exists
- **THEN** the line is `{"time":"HH:MM:SS","type":"FOLLOWUP","summary":"investigate hooks API"}` with no other keys (on a fresh day file the same entry also carries `"clog_version":"1.0"`)

### Requirement: Optional fields and key order
After the required fields the entry SHALL contain, in this order and only when non-empty: `agent`, `repo`, `session`, `model`, `file`, `family`, `kpi`, `clog_version`, `tags`, `logged_at`, then `validation` when set by the CLI. The hook `post-action-log.sh` MAY append `commit` after all of these. Empty string values SHALL be omitted, never written as `""` or `null`.

#### Scenario: Full entry
- **WHEN** every flag is supplied, including `--time`, on the first entry of a new file with an unknown family and default tags configured
- **THEN** the keys appear in the order `time, type, summary, agent, repo, session, model, file, family, kpi, clog_version, tags, logged_at, validation`

### Requirement: Tags field
`tags` SHALL be a JSON array of strings built from the machine default tags followed by the entry's `--tags` value, split on `,`, each item trimmed, empty items dropped, duplicates removed keeping the first occurrence. It SHALL be absent when neither source is set. A value consisting only of commas or whitespace SHALL yield `[]`.

#### Scenario: Default tags configured
- **WHEN** `CLOG_DEFAULT_TAGS=jbook` and the user runs `clog ACTION "x"`
- **THEN** the entry contains `"tags":["jbook"]`

#### Scenario: No default tags
- **WHEN** neither `CLOG_DEFAULT_TAGS` nor the tags file is set
- **THEN** the entry has no `tags` key

### Requirement: Schema version marker
`clog_version` SHALL be `"1.0"` on the first entry the CLI writes to a file that did not exist, and SHALL be absent on every later entry in that file. The `pre-agent-clog.sh` inline fallback SHALL do the same; the `post-action-log.sh` inline fallback SHALL NOT carry it.

#### Scenario: Second entry
- **WHEN** a second entry is written to an existing file
- **THEN** it has no `clog_version` key

### Requirement: Validation marker
`validation` SHALL be one of `unknown_family`, `unknown_kpi` or `unknown_family,unknown_kpi`, present only when the CLI rejected a `--family` or `--kpi` value against a non-empty configured list.

#### Scenario: Unknown family only
- **WHEN** `--family nope --kpi failure` is given with the example lists configured
- **THEN** `validation` is `unknown_family`

### Requirement: Commit marker
`commit` SHALL be a short git SHA added only by `hooks/post-action-log.sh` to a `COMMIT` entry when it can resolve the repository from the command it observed. The CLI has no flag to set it.

#### Scenario: Hook-logged commit
- **WHEN** the Bash hook observes `cd ~/Code/clog && git commit -m "feat(x): y"`
- **THEN** the last line of today's file is a `COMMIT` entry with `summary` `feat(x): y` and `commit` set to the new HEAD's short SHA

### Requirement: Logged-at marker
When `--time` overrides `time`, the entry SHALL carry `logged_at`, the local date and time it was actually written as `YYYY-MM-DDTHH:MM:SS`; entries without `--time` SHALL NOT carry it.

#### Scenario: Backfilled entry
- **WHEN** at 2026-01-03 09:00:00 the user runs `clog ACTION "x" --date 2026-01-02 --time 14:05:09`
- **THEN** the entry has `time` `14:05:09` and `logged_at` `2026-01-03T09:00:00`

#### Scenario: Normal entry
- **WHEN** the user runs `clog ACTION "x"`
- **THEN** the entry has no `logged_at` field
