## ADDED Requirements

### Requirement: Deterministic candidate extraction
`clog-sweep-sessions` SHALL find candidate actions with `scripts/extract.sh <transcript>`, which reads the transcript with jq and prints one JSON record per state-changing assistant tool call, `{timestamp, type, summary, why}` plus `file` for edits, with the call's UTC timestamp without fractional seconds. It SHALL NOT dispatch a subagent to scan a transcript. Non-JSON lines and non-assistant records SHALL be skipped.

#### Scenario: Huge transcript
- **WHEN** the transcript is larger than any Read limit
- **THEN** every candidate is still found, because jq streams the whole file

### Requirement: Candidate types
`extract.sh` SHALL report Edit, Write, MultiEdit and NotebookEdit calls as `CODE`, and Agent and Task dispatches, MCP calls whose tool name carries a mutating verb, and Bash calls that change repo or remote state as `ACTION`.

#### Scenario: Edit call
- **WHEN** the transcript holds an assistant `Edit` call on `/r/a/b.go` at `2026-11-19T15:21:39.270Z`
- **THEN** extract prints `{"timestamp":"2026-11-19T15:21:39Z","type":"CODE",…,"file":"/r/a/b.go"}`

#### Scenario: Read-only calls
- **WHEN** the transcript holds only `Read` calls, a `list_issues` MCP call and a Bash `git status`
- **THEN** extract prints nothing

### Requirement: Bash mutations follow the hook rules
`extract.sh` SHALL split a Bash command on `&&`, `||`, `;`, `|` and newlines and check every part. It SHALL skip a call only when its single mutating part is a `git commit`, `git push`, `gh pr create`, or `gh pr merge` without `--auto`, because `post-action-log.sh` logs those; a part with `--dry-run` changes nothing and is ignored. A part with an option before the subcommand (`git -C <dir> commit|push`, `gh -R <repo> pr merge`) SHALL be reported.

#### Scenario: Single commit
- **WHEN** the Bash command is `git commit -m "x"`
- **THEN** extract prints nothing

#### Scenario: Commit through -C
- **WHEN** the Bash command is `git -C /r commit -m "x"`
- **THEN** extract prints one `ACTION` record

#### Scenario: Merge chained with a tag
- **WHEN** the Bash command is `gh pr merge 27 && git tag v1`
- **THEN** extract prints one `ACTION` record naming the chain

### Requirement: Gap review before backfill
Before building backfill commands, the sweeping agent SHALL review the gap list from `gaps.sh`: it MAY drop a record that changed nothing and MAY rewrite `summary`, `why` and `kpi` in plain language, and it SHALL NOT add records or change a record's `type`, `date` or `time`.

#### Scenario: Read-only false positive
- **WHEN** a gap record's Bash command only listed worktrees
- **THEN** the record is dropped and nothing is backfilled for it

### Requirement: clog-sweep uses the shared pipeline
`clog-sweep` SHALL find the current session's gaps with the same `extract.sh | localize.sh | gaps.sh` pipeline and gap review, and SHALL NOT dispatch a scout subagent. Audit mode SHALL propose commands from `backfill-cmds.sh` without running them; backfill mode SHALL run them through `run-backfill.sh`.

#### Scenario: Long session
- **WHEN** "clog it" runs in a session whose transcript is larger than any Read limit
- **THEN** every candidate is still checked and no `/compact` is needed first

#### Scenario: Audit only
- **WHEN** the user says "clog gaps"
- **THEN** the missing entries are listed with proposed commands and nothing is written to the log
