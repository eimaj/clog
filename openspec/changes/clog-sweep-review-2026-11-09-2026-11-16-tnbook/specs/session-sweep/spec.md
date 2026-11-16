## ADDED Requirements

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
