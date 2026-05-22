# clog — Logging Rules

Single source of truth for **when** to log, **what** type to use, and **what** anti-patterns to avoid. Every skill and persona in this repo links here rather than restating these rules.

---

## 1. Type Definitions

| Type | When to use |
|------|-------------|
| `ACTION` | Any non-code state change: agent dispatched, tool called, file moved, API call made, config changed, setup completed |
| `DECISION` | A tradeoff resolved: choice between two approaches, naming decision, architecture choice, scope call |
| `CODE` | A file edited or created that changes runtime behavior: new function, bug fix, refactor, test added |
| `PR` | Pull request opened, updated, or merged |
| `COMMIT` | A git commit landed (auto-logged by `post-action-log.sh`) |
| `REPO` | Repo-level events: git init, new repo cloned, repo archived |
| `FOLLOWUP` | Something to revisit: discovered anomaly, deferred decision, open question, known debt |
| `LEARNING` | A finding that changes future behavior: prompt gap discovered, pattern identified, correction to prior claim |

**Rule**: when uncertain between ACTION and DECISION, ask: "did this produce an artifact or change external state?" → ACTION. "Did this resolve a tradeoff?" → DECISION.

---

## 2. When to Log

Log **immediately** after:

- **Post-edit**: any `Edit` / `Write` / `NotebookEdit` tool call that changes runtime behavior → `CODE`
- **Post-dispatch**: any subagent dispatched, MCP mutation called, or external API invoked → `ACTION`
- **Post-tradeoff**: any planning choice between two approaches → `DECISION`
- **Post-correction**: any claim you made earlier that turned out to be wrong → `LEARNING` (log the correction before the fix, not after)
- **Post-discovery**: a grep or Read finding that changes the implementation approach → `LEARNING --kpi effective`
- **Pre-reply**: before every user-facing reply after a state-changing tool call — name the ACTION or LEARNING in one sentence and log it

**Do not batch.** Each event gets its own log line, in real time.

---

## 3. What to Include

### Summary quality

- Minimum ~20 characters. Be specific: "add session fallback chain in bin/clog" beats "updated clog".
- Use imperative voice for CODE/ACTION: "add", "fix", "remove", "dispatch", "commit".
- For DECISION: include the option chosen and why: "use yq with grep/sed fallback — avoids mandatory yq dep".
- For LEARNING: name the *pattern*, not the symptom: "rapid-fire edit chain — checkpoint deferred until end" beats "forgot to log".

### `--kpi` selection (LEARNING entries)

| KPI | When |
|-----|------|
| `token_waste` | A large context was consumed producing something that had to be thrown away |
| `failure` | A discipline or rule was known but not followed |
| `prompt_gap` | A skill or prompt didn't remind the agent of a rule it needed |
| `effective` | A pattern or approach worked especially well — worth repeating |
| `format_issue` | Output format was wrong, causing downstream parse failures |

### `--agent` rubric

Use `--agent` when the entry is produced by a named agent role, not the user or the base session. Examples: `orchestrator`, `writer`, `reviewer`, `retro`, `planner`. Omit when logging from the base interactive session.

### `--family` rubric (LEARNING entries)

| Family | When |
|--------|------|
| `general` | Cross-cutting finding not specific to a tool or skill domain |
| `skills` | Finding about a skill file: trigger gaps, wrong command, missing steps |
| `tooling` | Finding about a tool API, hook behavior, or external system |
| `interactive` | Finding about the discipline in live interactive sessions |

Custom families defined in your `~/.config/clog/config.yaml` are also valid.

---

## 4. Anti-Patterns

**Batching** — logging multiple events in a single entry. Each event is independently searchable and revertable. Use one `clog` call per event.

**Backfilling silently** — discovering missed entries and logging them without a paired `LEARNING`. Every miss is evidence of a discipline gap. Name the gap.

**Vague summaries** — entries like "did stuff", "updated file", "progress". These are noise in retros. If you can't name the action specifically, log a FOLLOWUP to circle back.

**Silent corrections** — when a previously-logged claim turns out to be wrong, log a `LEARNING` that names what was wrong and why. Do not just silently log a corrected ACTION as if the first never happened.

**Subagent claim as parent log** — when a subagent reports "Action logged", that is the subagent's log entry. The parent/orchestrator must log its own entry for the dispatch and any observations.

**Skipping post-edit checkpoints** — every `Edit`/`Write` call that changes behavior is a `CODE` candidate. The `post-action-log.sh` hook covers `git commit`/`push`/`gh pr`; it does not cover in-session edits.
