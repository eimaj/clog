# clog

Structured JSONL session logging for AI coding tools. Drop it into Claude Code, Codex, Cursor, or OpenCode — every decision, action, learning, and PR lands in a timestamped log the same day it happens.

> 🧰 Part of a four-repo toolkit. `clog` is the substrate the others log into — see [eimaj/toolkit](https://github.com/eimaj/toolkit) for how it composes with [dev-prompter](https://github.com/eimaj/dev-prompter), [orchestrate](https://github.com/eimaj/orchestrate), and [project-manager](https://github.com/eimaj/project-manager). Standalone use needs none of them.

---

## 🕵️ What it does

`clog` appends a single JSON line to a daily `.jsonl` file every time you or an agent logs something:

```json
{"time":"14:32:01","type":"DECISION","summary":"use yq with grep/sed fallback — avoids mandatory dep","repo":"my-repo","session":"abc123"}
{"time":"14:33:15","type":"CODE","summary":"add session fallback chain in bin/clog","repo":"my-repo","file":"bin/clog"}
{"time":"14:45:00","type":"LEARNING","summary":"rapid-fire edit chain — checkpoint deferred at each pause","family":"interactive","kpi":"failure"}
{"time":"14:50:22","type":"LEARNING","summary":"skill misfire","family":"unknown","kpi":"failure","validation":"unknown_family"}
{"time":"15:02:09","type":"ACTION","summary":"cut release 26.15","repo":"my-repo","tags":["jbook","release"]}
```

The `validation` field is appended when `--family` or `--kpi` values don't match those declared in your config — entries are never rejected, only flagged so retros can surface drift.

Nine entry types (`ACTION`, `DECISION`, `CODE`, `PR`, `COMMIT`, `REPO`, `FOLLOWUP`, `LEARNING`, `LESSON`) cover every meaningful event in a session. The log is append-only, plain text, and readable with any JSON tool.

Five Claude Code hooks log commits, pushes and PRs, every file edit, and every subagent dispatch that carries a description, and warn when the log goes stale (that warning also writes a `LEARNING` entry tagged `hook-post-log`). An optional local HTTP API (`clog serve`) lets a web page or another tool write and read entries. Retro skills turn the raw log into reports and improvement proposals.

---

## 🤔 But... why?

My AI coding sessions are amnesia in fast-forward. The model autocompacts, you `/clear`, you context-switch, the IDE crashes — and the reasoning behind the last three hours evaporates. The diff stays, but the _why_ doesn't. Worse, the small judgement calls — "we picked yq over jq because of the macOS install story", "this skill misfired because the trigger was too generic", "the hook silently swallowed the error" — never make it into git history at all.

`clog` is a discipline, not a tool. The tool is a thin bash CLI plus a handful of hooks and skills. The discipline is: when something meaningful happens — a decision is resolved, a file is edited, an agent is dispatched — you write one line about it before moving on to the next action. Three things fall out of that:

- **Sessions become resumable.** Tomorrow-you (or a fresh agent) reads today's log and knows what was tried, what stuck, and what to avoid. No "let me re-derive the context" tax.
- **Retros become cheap.** `clog-lessons` reads a week of `LEARNING` entries, clusters them by `family` + `kpi`, and proposes concrete edits to your `CLAUDE.md` and `~/.claude/skills/` files as diffs (never auto-applied). The system that improves your prompts is reading data you already produced as a side effect of working.
- **Agents stop lying to themselves.** A subagent that returns "✅ logged the action" hasn't logged anything in _your_ session. The `clog-sweep` skill catches that gap explicitly. The Ledger persona prevents it inline.

The schema is intentionally simple: timestamp, type, summary, a handful of optional tags. Nothing to migrate. Nothing to host. One JSONL file per day, append-only, readable by `jq`, `grep`, `tail -f`, or your eyes. If you stop using clog tomorrow, you still own every entry you ever wrote.

Cost: one bash call per logged event (≈0 LLM tokens) and the cognitive overhead of naming what you just did.

---

## 🚀 Install

```bash
git clone https://github.com/eimaj/clog.git ~/clog
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

Overwrite an existing `config.yaml` without being asked:

```bash
./setup.sh --force
```

The installer detects which AI coding tools are present, lets you select which to install into, writes `~/.config/clog/config.yaml`, symlinks the five hooks and the skills, and registers the hooks in Claude Code's `settings.json` (`PostToolUse` and `PreToolUse`). Re-running `./setup.sh` after an install is safe: it skips any hook an existing matcher already covers (including `A|B` and regex matchers), adds only what is missing, and writes through a symlinked `settings.json`. Invalid JSON there makes it warn and register nothing.

---

### 🤝 Migrating from a previous install

If you have an existing `~/.claude/hooks/clog.sh` that is not a link resolving to this repo's `bin/clog` (a real file, or a link to another clone), or `CLOG_BIN` is set, `setup.sh` stops and asks for `--migrate`. `$AI_LOG_ROOT` is no longer a marker:

```bash
./setup.sh --migrate
```

The installer will:

1. Back up `~/.claude/hooks/clog.sh` → `clog.sh.pre-clog-pkg.bak`
2. Back up any real-file copies of the five hooks (`post-action-log.sh`, `post-log-reminder.sh`, `post-edit-log-check.sh`, `post-write-clog.sh`, `pre-agent-clog.sh`) the same way
3. Symlink the new `bin/clog` in their place (a regular file at `~/.local/bin/clog` is backed up the same way)
4. Ask for a log root (default `~/clog-logs`; type your existing log directory) and write `~/.config/clog/config.yaml`, overwriting an existing one only after a prompt (`--force` skips the prompt)

Other config fields (`families`, `kpis`, `cli_path`) use defaults — review the generated file after setup and add any custom `--family` values your existing agents use.

Your existing log files are never deleted or moved; the only renames are the `.pre-clog-pkg.bak` backups above.

---

## ⚡ Quick start

```bash
# Show the full flag reference
clog --help

# Print the entry as written (for scripts and the HTTP API)
clog ACTION "deploy to staging" --echo

# Tag one entry (machine default tags from CLOG_DEFAULT_TAGS or ~/.config/clog/tags.local come first)
clog ACTION "cut release 26.15" --tags release,web

# Log an action
clog ACTION "dispatch orchestrator for phase 2 planning"

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

# Backfill onto another day and time (the entry also gets logged_at = now)
clog ACTION "deployed hotfix" --date 2026-01-02 --time 14:05:09
```

`clog --help` lists every flag. For the type table, `--family` and `--kpi` rubrics, see [config/rules.md](config/rules.md); for exit codes and error messages, [docs/api/index.html](docs/api/index.html).

---

## ⚙️ Configuration

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

cli_path: ""
```

**Field explanations:**

| Field                        | Default                                                       | Description                                                    |
| ---------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------- |
| `log_root`                   | `~/clog-logs`                                                 | Directory where daily JSONL files live                         |
| `log_subdir`                 | `claude`                                                      | Subdirectory under `log_root` (e.g., one per tool)             |
| `auto_commit.enabled`        | `false`                                                       | Auto-commit the log dir to a git repo after each entry         |
| `auto_commit.repo_root`      | `""`                                                          | Path to git repo that contains `log_root`                      |
| `auto_commit.message`        | `"docs(clog): auto-commit logs"`                              | Commit message, used verbatim                                  |
| `reports_root`               | `~/clog-logs/reports`                                         | Output root for retro skill reports                            |
| `reminder_threshold_seconds` | `900`                                                         | Seconds of inactivity before staleness warning (0 = off)       |
| `families`                   | `[general, skills, tooling, interactive]`                     | Valid values for `--family`, checked on every type              |
| `kpis`                       | `[token_waste, failure, prompt_gap, effective, format_issue]` | Valid values for `--kpi`                                       |
| `cli_path`                   | `""`                                                          | Path to the `clog` binary, written by `setup.sh` for skills. Exported as `CLOG_CLI_PATH` but not used by the CLI, the hooks, or any shipped skill |

**Config path override:**

```bash
export CLOG_CONFIG=~/.config/clog/config.yaml   # the default (XDG_CONFIG_HOME is not consulted)
export CLOG_CONFIG=/shared/team/clog.yaml        # shared team config
```

**Env var overrides** (applied after config, useful for CI). A non-empty env var beats the config file, which beats the built-in default:

```bash
export CLOG_LOG_ROOT=/tmp/ci-logs
export CLOG_DISABLE=1   # silence all logging (CI, automated contexts)
```

Variables that override config: `CLOG_LOG_ROOT`, `CLOG_LOG_SUBDIR`, `CLOG_REPORTS_ROOT`, `CLOG_REMINDER_THRESHOLD`, `CLOG_AUTO_COMMIT_ENABLED`, `CLOG_AUTO_COMMIT_REPO`, `CLOG_AUTO_COMMIT_MSG`, `CLOG_FAMILIES`, `CLOG_KPIS`, `CLOG_CLI_PATH`.

**Environment-only variables** (no config key):

| Variable | Default | Description |
| --- | --- | --- |
| `CLOG_BIN` | unset | Full path to the `clog` binary. The hooks use it when `clog` is not on PATH, before falling back to the repo's `bin/clog`. `post-write-clog.sh` ignores it |
| `CLOG_EDIT_THRESHOLD` | `3` | Edit count at which `post-edit-log-check.sh` warns when no new log entry has appeared (default: on the 3rd edit, and every edit after it); `0` disables the warning |
| `CLOG_DEFAULT_TAGS` | unset | Comma-separated tags added to every entry, before any `--tags`. Beats the tags file |
| `CLOG_TAGS_FILE` | `~/.config/clog/tags.local` | File holding one comma-separated line of default tags (not one tag per line: newlines are removed without a separator), read when `CLOG_DEFAULT_TAGS` is empty. Kept outside the config so it stays machine-local |
| `CLOG_API_TOKEN` | unset (random per launch) | Bearer token `clog serve` requires on `/config` and `/entries`. Blank means random |

---

## 🛠️ The retro skills

Install into Claude Code and invoke by name:

| Skill          | Output                                                                                                 |
| -------------- | ------------------------------------------------------------------------------------------------------ |
| `clog-sweep`   | Two modes: **backfill** (finds misses, auto-applies + paired LEARNINGs) and **audit-only** (gaps report, no backfill) |
| `clog-sweep-sessions` | Like `clog-sweep` for named session ids on any day (closed panes included): backfills each miss with `--session/--date/--time` and returns one JSON result per session |
| `clog-day`     | Daily markdown report grouped by type                                                                  |
| `clog-week`    | Weekly aggregation: velocity, top decisions, learnings by cluster                                      |
| `clog-lessons` | Reads LEARNING entries, clusters by family+kpi, proposes skill edits as **diffs** (never auto-applies) |
| `clog-replay`  | Reconstruct a prompt from past JSONL log entries — guided search, cluster context, fill-in-the-blanks prompt reconstruction |
| `clog-search`  | Search historical JSONL logs by date, keyword, repo, or type — jq-driven, produces a formatted markdown report |

A typical Friday flow:

```
clog-sweep (audit) → clog-sweep (backfill) → clog-lessons → clog-week
```

---

## 🪵 Proactive logging

Two complementary layers, both optional:

### 💁 Ledger persona (recommended)

Add the `persona/PERSONA.md` fragment to your `CLAUDE.md` to make any session proactively log-aware:

```bash
cat persona/PERSONA.md >> ~/.claude/CLAUDE.md
```

The setup installer offers to do this for you when `~/.claude/CLAUDE.md` already exists. Ledger watches every tool call and flags unlogged state-changes inline — no retroactive sweep needed.

---

## 🔌 Per-tool integration

See [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md) for tool-specific details.

| Tool        | Hooks                                                              | Skills | Notes                            |
| ----------- | ------------------------------------------------------------------ | ------ | -------------------------------- |
| Claude Code | Full — 5 hooks: `post-action-log` (commits/pushes/PRs), `post-log-reminder` (staleness warn on Bash + Agent), `post-edit-log-check` (edit-log checks), `post-write-clog` (auto CODE entry per edit), `pre-agent-clog` (ACTION entry per Agent dispatch) | Yes    | Hooks auto-register via setup.sh when `~/.claude/settings.json` exists |
| Codex       | No                                                                 | Yes    | No hooks API exposed yet         |
| Cursor      | No                                                                 | Yes    | No hooks API exposed yet         |
| OpenCode    | No                                                                 | Yes    | No hooks API exposed yet         |

---

## 🌐 HTTP API

`clog serve` starts a local HTTP service so a browser or another tool can write and read entries. Every write spawns `bin/clog --echo`, so validation, config precedence and the JSON line stay in the CLI. It needs Node on PATH: Node 20 or newer to run, Node 24 or newer for the test suite, which relies on Node's built-in TypeScript support. `bin/clog` itself stays dependency-free (bash + jq).

```bash
npm install
npm run build
clog serve              # http://127.0.0.1:4848
clog serve --port 0     # free port; the real one is printed
```

The server prints two lines, `clog API listening on http://127.0.0.1:<port>` and `clog API token: <token>`, and runs until SIGINT/SIGTERM. The token is random per launch (set `CLOG_API_TOKEN` to choose one); send it as `Authorization: Bearer <token>` on `/config` and `/entries`. Open `http://127.0.0.1:<port>/demo` for a page that writes and lists entries, or `/docs` for the reference.

| Route            | Success                                              | Notes                                                                                   |
| ---------------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `GET /health`    | `{ ok, version, clogBin }`                           |                                                                                         |
| `GET /config`    | `{ configPath, logRoot, logSubdir, families, kpis }` | 401 `unauthorized` without the token; 503 `disabled` under `CLOG_DISABLE=1` (checked first, as the CLI does); otherwise 503 `no_config` until a config exists |
| `POST /entries`  | 201 `{ entry, file, warning? }`                      | 401 `unauthorized`; body `{ type, summary, agent?, repo?, session?, model?, file?, family?, kpi?, date?, tags?: string[] }` (no NUL in any field; `tags` items must not contain commas or control characters and are added after the server's default tags, trimmed and deduplicated); `repo` defaults to the git repo containing the server's working directory, or is absent when there is none; `session` is absent unless supplied; `warning` when the CLI wrote the entry then exited non-zero; writes run one at a time |
| `GET /entries`   | `{ date, file, entries, skipped }`                   | 401 `unauthorized`; query `date`, `type`, `repo`, `session`, `agent`, `tag` (entry's `tags` contains it; once only), `tail` (1 to 10000); default day today (also for an empty `date`; a repeated `date` is 400); 503 `no_config` / `disabled` as for `/config` |
| `GET /demo`, `GET /docs` | HTML                                         |                                                                                         |

**Errors** are always `{ "error": { "code", "message" } }`; when the CLI rejected the entry, `message` is its stderr line verbatim. Statuses: 400 bad input (`invalid_json`, `invalid_type`, `missing_summary`, `invalid_field`, `invalid_date`, `invalid_tag`, `invalid_tail`), 401 `unauthorized`, 403 `forbidden_host`, 413 body over 64 KiB, 415 `unsupported_media_type`, 404 unknown route, 503 `no_config` or `disabled` (`CLOG_DISABLE=1`), 500 `clog_failed` / `clog_timeout` (10 s; the CLI's whole process group is killed), 500 `internal_error` (message `internal server error`, never a stack, for any unexpected failure).

**Bind and CORS:** listens on `127.0.0.1` only; the bearer token above is the only credential, so any local page that knows it can read and write. CORS allows only `http://localhost[:port]` and `http://127.0.0.1[:port]` origins; a `file://` page (`Origin: null`) is refused, which is why the demo is served by the server itself. `POST /entries` needs `Content-Type: application/json`, and `createApp` answers 403 `forbidden_host` unless `Host` is `127.0.0.1` or `localhost` (optional port).

**Mounting:** `createClogRouter({ clogBin?, token?, spawnTimeoutMs? })` from `src/server/app.ts` returns a Hono router with relative routes, so another Hono app can mount it, e.g. `app.route('/clog', createClogRouter({ token }))`. `createClogRouter` carries no Host/CORS/body-limit guards; pass `token` to require bearer auth; the mounting app owns the rest.

**Development:** `clog serve` runs `dist/`, which goes stale after `src/` edits until you run `npm run build` (`npm run serve` runs the built server directly, skipping `bin/clog`'s node and build checks). `npm run check` runs lint, typecheck (`src` and `tests`), the node tests, then the bash CLI harness (`npm run check:cli`, see `tests/cli/README.md`); every test uses a scratch config and never touches your real log root.

---

## 📐 Schema reference

See [docs/SCHEMA.md](docs/SCHEMA.md) for the full JSONL field reference and example entries, or open [docs/api/index.html](docs/api/index.html) for the browsable CLI and HTTP reference (types, flags, exit codes, config, env, hooks, routes, and a command builder).

The behavioural contract is the set of OpenSpec baselines in [openspec/specs/](openspec/specs/) (`cli`, `config`, `log-entry`, `hooks`, `session-sweep`) plus the `cli-echo` and `http-api` changes still under `openspec/changes/`; `tests/cli/run.sh` and the node tests pin every scenario in them. Propose a behaviour change as an `openspec/changes/<name>/` delta before changing code.

---

## ❓ FAQ

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
