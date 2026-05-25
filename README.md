# clog

Structured JSONL session logging for AI coding tools. Drop it into Claude Code, Codex, Cursor, or OpenCode — every decision, action, learning, and PR lands in a timestamped log the same day it happens.

---

## What it does

`clog` appends a single JSON line to a daily `.jsonl` file every time you or an agent logs something:

```json
{"time":"14:32:01","type":"DECISION","summary":"use yq with grep/sed fallback — avoids mandatory dep","repo":"my-repo","session":"abc123"}
{"time":"14:33:15","type":"CODE","summary":"add session fallback chain in bin/clog","file":"bin/clog","repo":"my-repo"}
{"time":"14:45:00","type":"LEARNING","summary":"rapid-fire edit chain — checkpoint deferred at each pause","family":"interactive","kpi":"failure"}
```

Nine entry types (`ACTION`, `DECISION`, `CODE`, `PR`, `COMMIT`, `REPO`, `FOLLOWUP`, `LEARNING`, `LESSON`) cover every meaningful event in a session. The log is append-only, plain text, and readable with any JSON tool.

Auto-hooks catch `git commit`, `git push`, and `gh pr create` events. Five retro skills turn the raw log into reports and improvement proposals (see [The five retro skills](#the-five-retro-skills) below).

---

## But... why?

AI coding sessions are amnesia in fast-forward. The model autocompacts, you `/clear`, you context-switch, the IDE crashes — and the reasoning behind the last three hours evaporates. The diff stays, but the _why_ doesn't. Worse, the small judgement calls — "we picked yq over jq because of the macOS install story", "this skill misfired because the trigger was too generic", "the hook silently swallowed the error" — never make it into git history at all.

`clog` is a discipline, not a tool. The tool is about a hundred lines of bash. The discipline is: when something meaningful happens, you write one line about it before the next thing happens. Three things fall out of that:

- **Sessions become resumable.** Tomorrow-you (or a fresh agent) reads today's log and knows what was tried, what stuck, and what to avoid. No "let me re-derive the context" tax.
- **Retros become cheap.** `clog-lessons` reads a week of `LEARNING` entries, clusters them by `family` + `kpi`, and proposes concrete skill edits as diffs. The model that improves your prompts is reading data you already produced as a side effect of working.
- **Agents stop lying to themselves.** A subagent that returns "✅ logged the action" hasn't logged anything in _your_ session. The `clog-gaps` skill catches that gap explicitly. The Ledger persona prevents it inline.

The schema is intentionally simple: timestamp, type, summary, a handful of optional tags. Nothing to migrate. Nothing to host. One JSONL file per day, append-only, readable by `jq`, `grep`, `tail -f`, or your eyes. If you stop using clog tomorrow, you still own every entry you ever wrote.

Cost: one bash call per logged event (≈0 LLM tokens) and the cognitive overhead of naming what you just did.

---

## Install

```bash
git clone https://github.com/your-user/clog.git ~/clog
cd ~/clog
./setup.sh
```

Preview changes without executing:

```bash
./setup.sh --dry-run
```

Migrate an existing install:

```bash
./setup.sh --migrate
```

The installer detects which AI coding tools are present, lets you select which to install into, writes `~/.config/clog/config.yaml`, symlinks hooks and skills, and registers the `PostToolUse` hooks in Claude Code's `settings.json`.

---

## Migrating from a previous install

If you have an existing `~/.claude/hooks/clog.sh`:

```bash
./setup.sh --migrate
```

The installer will:

1. Back up `~/.claude/hooks/clog.sh` → `clog.sh.pre-clog-pkg.bak`
2. Back up `post-action-log.sh` and `post-log-reminder.sh` the same way
3. Symlink the new `bin/clog` in their place
4. Write a fresh `~/.config/clog/config.yaml` with your `log_root` pre-filled to the existing log directory

Other config fields (`families`, `kpis`, `cli_path`) use defaults — review the generated file after setup and add any custom `--family` values your existing agents use.

Your existing log files are never deleted or moved unless you explicitly confirm the move during setup.

---

## Quick start

```bash
# Log an action
clog ACTION "dispatch clog-keeper after planning burst"

# Log a decision
clog DECISION "use yq with grep/sed fallback — avoids mandatory dep"

# Log a code change
clog CODE "add session fallback chain in bin/clog" --file bin/clog

# Log a learning
clog LEARNING "rapid-fire chain skipped all checkpoints" \
     --family interactive --kpi failure

# Log something to revisit
clog FOLLOWUP "investigate whether Cursor exposes hooks API"

# Repo and session are auto-detected; override when needed
clog ACTION "deploy to staging" --repo my-repo --agent orchestrator
```

For the full type table, `--family`, and `--kpi` reference, see [skills/clog/SKILL.md](skills/clog/SKILL.md).

---

## Configuration

If you ran `setup.sh`, this file already exists at `~/.config/clog/config.yaml`. To write it manually or review the schema, copy `config/config.yaml.example`:

```yaml
log_root: "${HOME}/clog-logs"
log_subdir: "claude"

auto_commit:
  enabled: false
  repo_root: ""
  message: "docs(clog): auto-commit logs"

reports_root: "${HOME}/clog-logs/reports"
reminder_threshold_seconds: 900

families:
  - general
  - skills
  - tooling
  - interactive
kpis:
  - token_waste
  - failure
  - prompt_gap
  - effective
  - format_issue

agents: []

cli_path: ""
```

**Field explanations:**

| Field                        | Default                                                       | Description                                                    |
| ---------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------- |
| `log_root`                   | `~/clog-logs`                                                 | Directory where daily JSONL files live                         |
| `log_subdir`                 | `claude`                                                      | Subdirectory under `log_root` (e.g., one per tool)             |
| `auto_commit.enabled`        | `false`                                                       | Auto-commit the log dir to a git repo after each entry         |
| `auto_commit.repo_root`      | `""`                                                          | Path to git repo that contains `log_root`                      |
| `auto_commit.message`        | `"docs(clog): auto-commit logs"`                              | Commit message template                                        |
| `reports_root`               | `~/clog-logs/reports`                                         | Output root for retro skill reports                            |
| `reminder_threshold_seconds` | `900`                                                         | Seconds of inactivity before staleness warning (0 = off)       |
| `families`                   | `[general, skills, tooling, interactive]`                     | Valid values for `--family` on LEARNING entries                |
| `kpis`                       | `[token_waste, failure, prompt_gap, effective, format_issue]` | Valid values for `--kpi`                                       |
| `agents`                     | `[]`                                                          | Optional registry of valid agent names (empty = no validation) |
| `cli_path`                   | `""`                                                          | Path to the `clog` binary, set by `setup.sh`; skills use this as a fallback when `clog` is not on PATH |

**Config path override:**

```bash
export CLOG_CONFIG=~/.config/clog/config.yaml   # default XDG location
export CLOG_CONFIG=/shared/team/clog.yaml        # shared team config
```

**Env var overrides** (applied after config, useful for CI):

```bash
export CLOG_LOG_ROOT=/tmp/ci-logs
export CLOG_DISABLE=1   # silence all logging (CI, automated contexts)
```

---

## The five retro skills

Install into Claude Code and invoke by name:

| Skill          | Trigger               | Output                                                                                                 |
| -------------- | --------------------- | ------------------------------------------------------------------------------------------------------ |
| `clog-it`      | "clog it", "backfill" | Retroactive sweep — finds unlogged state-changes, proposes backfill + paired LEARNINGs                 |
| `clog-day`     | "clog day [date]"     | Daily markdown report grouped by type                                                                  |
| `clog-week`    | "clog week [date]"    | Weekly aggregation: velocity, top decisions, learnings by cluster                                      |
| `clog-lessons` | "clog lessons"        | Reads LEARNING entries, clusters by family+kpi, proposes skill edits as **diffs** (never auto-applies) |
| `clog-gaps`    | "clog gaps [date]"    | Scans transcript + JSONL for unlogged actions, missing `--kpi`, vague summaries                        |

A typical Friday flow:

```
clog-gaps → clog-it → clog-lessons → clog-week
```

---

## Proactive logging

### Ledger persona

Add the `persona/PERSONA.md` fragment to your `CLAUDE.md` to make any session proactively log-aware:

```bash
cat persona/PERSONA.md >> ~/.claude/CLAUDE.md
```

The setup installer will offer to do this. Ledger watches every tool call and flags unlogged state-changes inline — no retroactive sweep needed.

### clog-keeper agent

After a burst of work, dispatch `clog-keeper` as a subagent — load `agents/clog-keeper.md` as its system prompt (or use your tool's equivalent subagent invocation). It scans the last N tool calls, diffs against the JSONL, and proposes exact `clog` commands for any gaps — with paired LEARNINGs naming why each was missed.

---

## Per-tool integration

See [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md) for tool-specific details.

| Tool        | Hooks              | Skills | Notes                            |
| ----------- | ------------------ | ------ | -------------------------------- |
| Claude Code | Full (PostToolUse) | Yes    | Hooks auto-register via setup.sh |
| Codex       | No                 | Yes    | No hooks API exposed yet         |
| Cursor      | No                 | Yes    | No hooks API exposed yet         |
| OpenCode    | No                 | Yes    | No hooks API exposed yet         |

---

## Schema reference

See [docs/SCHEMA.md](docs/SCHEMA.md) for the full JSONL field reference and example entries.

---

## FAQ

**Why is auto-commit off by default?**
Auto-committing every log entry creates noisy git history. If you want auto-commit, point `auto_commit.repo_root` at a dedicated notes repo (not your project repo) and enable it. The `docs(clog): auto-commit logs` message keeps it identifiable and filterable.

**How do I silence logging temporarily?**

```bash
export CLOG_DISABLE=1
# ... run CI, automation, or anything that shouldn't produce log entries ...
unset CLOG_DISABLE
```

**How do I share config across machines?**
Put `~/.config/clog/config.yaml` in your personal dotfiles repo and symlink it on each machine. The file is gitignored in the clog repo itself — keep it in your own dotfiles where you control access.

**Can I use a different log path per project?**
Use `$CLOG_CONFIG` to point at a per-project config, or set `$CLOG_LOG_ROOT` as an env override in your project's `.env` or shell wrapper.
