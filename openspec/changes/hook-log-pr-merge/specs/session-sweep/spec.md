## ADDED Requirements

### Requirement: Logged merges are not reported as gaps
`clog-sweep` and `clog-sweep-sessions` SHALL skip a single `gh pr merge` command without `--auto` as auto-logged, because `post-action-log.sh` logs it, SHALL check `gh` with an option before the subcommand (`gh -R <repo> pr merge`) against the log because the hook does not match it, and SHALL keep checking every part of a chained command.

#### Scenario: Merge logged by the hook
- **WHEN** the transcript holds `gh pr merge 27` and the day's log has the `merged PR #27` entry
- **THEN** it is not reported as missing

#### Scenario: Merge chained with an unlogged mutation
- **WHEN** the transcript holds `gh pr merge 27 && git tag v1`
- **THEN** the `git tag` part is checked against the log
