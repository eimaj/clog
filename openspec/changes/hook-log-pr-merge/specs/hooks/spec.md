## MODIFIED Requirements

### Requirement: post-action-log.sh triggers
On PostToolUse for Bash, the hook SHALL read `tool_input.command` and write `COMMIT` entries when the command contains `git commit`, else a `PR` entry when it contains `gh pr create`, else an `ACTION` entry `merged PR #<n> (<repo>)` when it contains `gh pr merge`, else an `ACTION` entry `pushed <branch> (<repo>)` when it contains `git push`. The `PR` summary SHALL be the `--title "…"` value. The merge summary SHALL carry `#<n>` only when a number directly follows `gh pr merge`, and the `(<repo>)` suffix only when the repository resolves.

#### Scenario: Commit with message
- **WHEN** the hook receives `{"tool_input":{"command":"git commit -m \"feat(x): hook test\""}}`
- **THEN** a `COMMIT` entry with `summary` `feat(x): hook test` is appended

#### Scenario: Unrelated command
- **WHEN** the command is `ls`
- **THEN** nothing is written

#### Scenario: Merge with a number
- **WHEN** the command is `gh pr merge 27 --squash` in a repository named `proj`
- **THEN** one `ACTION` entry `merged PR #27 (proj)` is written

#### Scenario: Merge without a number
- **WHEN** the command is `gh pr merge --auto` in a repository named `proj`
- **THEN** one `ACTION` entry `merged PR (proj)` is written

#### Scenario: Merge chained with a push
- **WHEN** the command is `gh pr merge 27 && git push`
- **THEN** one `ACTION` entry `merged PR #27 (proj)` is written and no push entry
