# clog — JSONL Schema Reference

Each log entry is a single JSON object on one line in the daily `.jsonl` file at `<log_root>/<log_subdir>/YYYYMMDD.jsonl`.

---

## Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `time` | string | yes | `HH:MM:SS` — wall-clock time of the entry |
| `type` | string | yes | One of: `ACTION`, `DECISION`, `CODE`, `PR`, `COMMIT`, `REPO`, `FOLLOWUP`, `LEARNING` |
| `summary` | string | yes | Human-readable description of the event |
| `repo` | string | no | Git repo basename — auto-detected from `git rev-parse --show-toplevel` or explicit `--repo` |
| `session` | string | no | Session ID from `$CLAUDE_SESSION_ID`, `$CODEX_SESSION_ID`, or `$CURSOR_SESSION_ID` |
| `agent` | string | no | Agent role that produced this entry (e.g., `orchestrator`, `writer`, `retro`) |
| `model` | string | no | Model name used in the session |
| `file` | string | no | Relative file path — used with `CODE` entries |
| `family` | string | no | `LEARNING` only — domain family (e.g., `interactive`, `skills`) |
| `kpi` | string | no | `LEARNING` only — quality KPI (e.g., `failure`, `prompt_gap`) |
| `commit` | string | no | Short git SHA — auto-added by `post-action-log.sh` for `COMMIT` entries |
| `clog_version` | string | no | Schema version (e.g., `"1.0"`) — emitted once per file on first write of the day |
| `validation` | string | no | `unknown_family` or `unknown_kpi` — set when a flag value is not in the config enum list |

---

## Example entries

### ACTION
```json
{"time":"09:15:22","type":"ACTION","summary":"dispatch clog-keeper after planning burst","agent":"orchestrator","repo":"my-repo","session":"sess-abc123"}
```

### DECISION
```json
{"time":"09:32:44","type":"DECISION","summary":"use yq with grep/sed fallback — avoids mandatory dep","repo":"my-repo"}
```

### CODE
```json
{"time":"10:01:05","type":"CODE","summary":"add session fallback chain in bin/clog","file":"bin/clog","repo":"clog"}
```

### PR
```json
{"time":"11:45:00","type":"PR","summary":"[CLOG-12] add post-log-reminder hook","repo":"clog"}
```

### COMMIT (auto-logged)
```json
{"time":"11:46:33","type":"COMMIT","summary":"feat(hooks): add post-log-reminder","repo":"clog","commit":"a3f9b12"}
```

### REPO
```json
{"time":"08:00:01","type":"REPO","summary":"git init ~/Code/clog — new public clog package","repo":"clog","clog_version":"1.0"}
```

### FOLLOWUP
```json
{"time":"14:22:10","type":"FOLLOWUP","summary":"investigate whether Cursor exposes hooks API"}
```

### LEARNING
```json
{"time":"15:00:00","type":"LEARNING","summary":"rapid-fire edit chain — checkpoint deferred at each pause until the chain ended","family":"interactive","kpi":"failure","agent":"orchestrator","repo":"my-repo"}
```

### LEARNING with validation warning
```json
{"time":"15:05:00","type":"LEARNING","summary":"unknown family used in retro","family":"retro-specific","kpi":"prompt_gap","validation":"unknown_family"}
```

---

## File naming

Files are named `YYYYMMDD.jsonl` (e.g., `20260522.jsonl`) in the configured `log_root/log_subdir/` directory.

The `clog_version` field appears only in the first entry of a new daily file, allowing readers to detect the schema generation without scanning all entries.

---

## Reading the log

```bash
# All entries today
jq '.' ~/clog-logs/claude/$(date +%Y%m%d).jsonl

# All LEARNING entries with kpi
jq 'select(.type == "LEARNING" and .kpi != null)' ~/clog-logs/claude/$(date +%Y%m%d).jsonl

# All entries for a repo
jq 'select(.repo == "my-repo")' ~/clog-logs/claude/$(date +%Y%m%d).jsonl

# Count by type
jq -s 'group_by(.type) | map({type: .[0].type, count: length})' ~/clog-logs/claude/$(date +%Y%m%d).jsonl
```
