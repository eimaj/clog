## ADDED Requirements

### Requirement: Logged-at marker
When `--time` overrides `time`, the entry SHALL carry `logged_at`, the local date and time it was actually written as `YYYY-MM-DDTHH:MM:SS`; entries without `--time` SHALL NOT carry it.

#### Scenario: Backfilled entry
- **WHEN** at 2026-01-03 09:00:00 the user runs `clog ACTION "x" --date 2026-01-02 --time 14:05:09`
- **THEN** the entry has `time` `14:05:09` and `logged_at` `2026-01-03T09:00:00`

#### Scenario: Normal entry
- **WHEN** the user runs `clog ACTION "x"`
- **THEN** the entry has no `logged_at` field

## MODIFIED Requirements

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
