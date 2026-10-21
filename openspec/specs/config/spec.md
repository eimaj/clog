# Config Specification

## Purpose

How `lib/config.sh` resolves settings for the CLI and the hooks: the config file, its keys, the environment overrides and the two parsers. Reverse-engineered from the code at `b5d2927` (main) and verified by sourcing `load_config` with and without `yq` on PATH.

## Requirements

### Requirement: Config file location
The config file SHALL be `$CLOG_CONFIG` when set and non-empty, otherwise `~/.config/clog/config.yaml`. It SHALL be YAML with the keys in `config/config.yaml.example`.

#### Scenario: Override path
- **WHEN** `CLOG_CONFIG=/shared/team/clog.yaml` is set and that file exists
- **THEN** settings are read from that file and the default path is not consulted

### Requirement: Path and threshold keys
The loader SHALL export `log_root` as `CLOG_LOG_ROOT` (default `~/clog-logs`), `log_subdir` as `CLOG_LOG_SUBDIR` (default `claude`), `reports_root` as `CLOG_REPORTS_ROOT` (default `~/clog-logs/reports`) and `reminder_threshold_seconds` as `CLOG_REMINDER_THRESHOLD` (default `900`).

#### Scenario: Example config paths
- **WHEN** `config/config.yaml.example` is loaded
- **THEN** `CLOG_LOG_ROOT` is `$HOME/clog-logs`, `CLOG_LOG_SUBDIR` is `claude` and `CLOG_REMINDER_THRESHOLD` is `900`

#### Scenario: Empty config
- **WHEN** the config file exists but sets none of the keys
- **THEN** every variable holds its built-in default

### Requirement: Auto-commit keys
The loader SHALL export `auto_commit.enabled` as `CLOG_AUTO_COMMIT_ENABLED` (default `false`), `auto_commit.repo_root` as `CLOG_AUTO_COMMIT_REPO` (default empty) and `auto_commit.message` as `CLOG_AUTO_COMMIT_MSG` (default `docs(clog): auto-commit logs`).

#### Scenario: Example config auto-commit
- **WHEN** `config/config.yaml.example` is loaded
- **THEN** `CLOG_AUTO_COMMIT_ENABLED` is `false` and `CLOG_AUTO_COMMIT_REPO` is empty

### Requirement: Enum list keys
The loader SHALL export the block lists `families`, `kpis` and `agents` as `CLOG_FAMILIES`, `CLOG_KPIS` and `CLOG_AGENTS`, each a single space-separated string, defaulting to empty. An empty list SHALL disable the matching `--family` or `--kpi` validation.

#### Scenario: Example config lists
- **WHEN** `config/config.yaml.example` is loaded
- **THEN** `CLOG_FAMILIES` is `general skills tooling interactive` and `CLOG_KPIS` is `token_waste failure prompt_gap effective format_issue`

#### Scenario: No lists
- **WHEN** the config declares no `families`
- **THEN** `clog LEARNING "x" --family anything` writes the entry without a `validation` field

### Requirement: Exported but unused keys
The loader SHALL export `cli_path` as `CLOG_CLI_PATH` (default empty). `CLOG_CLI_PATH`, `CLOG_AGENTS` and `CLOG_REPORTS_ROOT` SHALL be available in the environment but are not read by the CLI or by any hook.

#### Scenario: cli_path set
- **WHEN** the config sets `cli_path: ~/.local/bin/clog`
- **THEN** `CLOG_CLI_PATH` is exported with the home directory expanded and no CLI or hook behaviour changes

### Requirement: Precedence
For each key, a non-empty environment variable SHALL win over the config file, and the config file SHALL win over the built-in default. An empty environment variable SHALL NOT override a config value.

#### Scenario: Env over config
- **WHEN** the config sets `log_root` and `CLOG_LOG_ROOT=/tmp/ci-logs` is exported
- **THEN** entries are written under `/tmp/ci-logs/<log_subdir>/`

#### Scenario: Config over default
- **WHEN** `CLOG_LOG_SUBDIR` is unset and the config sets `log_subdir: codex`
- **THEN** entries are written under `<log_root>/codex/`

#### Scenario: Empty env value
- **WHEN** the config sets `auto_commit.enabled: true` and `CLOG_AUTO_COMMIT_ENABLED=` (empty) is exported
- **THEN** `CLOG_AUTO_COMMIT_ENABLED` is `true`

### Requirement: Home expansion for path values
Values of `log_root`, `reports_root`, `auto_commit.repo_root` and `cli_path` SHALL have a leading `~` or `${HOME}` replaced with the home directory, whether they come from the config file or from the environment.

#### Scenario: Tilde from the environment
- **WHEN** `CLOG_LOG_ROOT='~/x'` is exported unexpanded (for example from an editor's env block)
- **THEN** entries are written under `$HOME/x/<log_subdir>/`, not under `./~/x`

### Requirement: Parser selection
The loader SHALL parse the file with `yq` (v4) when `yq` is on PATH, otherwise with a grep/sed/awk fallback.

#### Scenario: yq absent
- **WHEN** PATH contains no `yq`
- **THEN** the fallback parser runs and the CLI still writes entries

### Requirement: Parser parity
Both parsers SHALL produce the same values for the shapes used in `config/config.yaml.example`: flat `key: value` lines, the nested `auto_commit:` block, and block lists of `  - item` lines. In block lists, whole-line comments and blank lines SHALL be skipped, surrounding double quotes removed, and items joined with single spaces.

#### Scenario: Parity on the example config
- **WHEN** `load_config` is run against the example config with and without `yq` on PATH
- **THEN** `env | grep ^CLOG_` is identical

#### Scenario: Fallback with a list comment
- **WHEN** `yq` is absent and the `families:` block contains a `# comment` line between items
- **THEN** the comment line is skipped and the items on either side are both present

### Requirement: Fallback parser limits
The fallback parser SHALL NOT strip inline `# comments` from scalar values or list items, SHALL NOT remove single quotes around values, and SHALL NOT read inline lists such as `families: [a, b]`. It SHALL read `enabled:`, `repo_root:` and `message:` from the first indented line with that key anywhere in the file, not only under `auto_commit:`. `yq` handles all of these correctly.

#### Scenario: Fallback list item quoting
- **WHEN** `yq` is absent and a list has `- 'one'`, `- two # inline`, `- "three"`
- **THEN** the exported value is `'one' two # inline three` (with `yq` it is `one two three`)

#### Scenario: Fallback inline list
- **WHEN** `yq` is absent and the file has `families: [general, x]`
- **THEN** `CLOG_FAMILIES` is empty

#### Scenario: Fallback inline comment
- **WHEN** `yq` is absent and the file has `log_root: /x   # comment`
- **THEN** `CLOG_LOG_ROOT` is `/x   # comment`

### Requirement: Hook mode
When called with `--hook`, the loader SHALL return 0 silently if the config file is missing, without exporting any `CLOG_*` variable or default. Without `--hook` it SHALL print `clog: no config at <path>. Run setup.sh to create one.` to stderr and return 1.

#### Scenario: Hook with no config
- **WHEN** `load_config --hook` runs with no config file
- **THEN** it returns 0, prints nothing and `CLOG_LOG_ROOT` remains unset

### Requirement: Disable short-circuit
When `CLOG_DISABLE` is exactly `1`, the loader SHALL return 0 after locating the config file and before parsing it.

#### Scenario: Disabled
- **WHEN** `CLOG_DISABLE=1` and the config file exists
- **THEN** no `CLOG_*` value is read from the file
