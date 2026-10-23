# clog — Integrations

Per-tool installation notes and caveats.

---

## Claude Code

**Support level:** Full — hooks + skills.

### Install

Run `./setup.sh` from the clog repo root. The installer:
1. Symlinks the five hooks (`post-action-log.sh`, `post-log-reminder.sh`, `post-edit-log-check.sh`, `post-write-clog.sh`, `pre-agent-clog.sh`) into `~/.claude/hooks/`
2. Symlinks all `skills/*/` into `~/.claude/skills/`
3. Registers them in `~/.claude/settings.json`: `post-action-log.sh` and `post-log-reminder.sh` under `PostToolUse > Bash`; `post-log-reminder.sh` under `PostToolUse > Agent`; `post-edit-log-check.sh` and `post-write-clog.sh` under `PostToolUse > Edit`, `Write`, `MultiEdit` and `NotebookEdit`; `pre-agent-clog.sh` under `PreToolUse > Agent`
4. Optionally appends `persona/PERSONA.md` to `~/.claude/CLAUDE.md`

### Hook registration format

The installer adds the following to `settings.json`, writing absolute paths (your `$HOME`, shown here as `/Users/you`):
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "/Users/you/.claude/hooks/post-action-log.sh"},
          {"type": "command", "command": "/Users/you/.claude/hooks/post-log-reminder.sh"}
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [{"type": "command", "command": "/Users/you/.claude/hooks/post-log-reminder.sh"}]
      },
      {
        "matcher": "Edit",
        "hooks": [
          {"type": "command", "command": "/Users/you/.claude/hooks/post-edit-log-check.sh"},
          {"type": "command", "command": "/Users/you/.claude/hooks/post-write-clog.sh"}
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [{"type": "command", "command": "/Users/you/.claude/hooks/pre-agent-clog.sh"}]
      }
    ]
  }
}
```

The `Edit` entry is repeated for `Write`, `MultiEdit` and `NotebookEdit` with the same two commands.

### Manual hook registration

If you prefer to edit `settings.json` by hand, add the entries above under `PostToolUse` and `PreToolUse`. All five hooks exit 0 always — they will not block any tool call. Re-running `setup.sh` is safe: a hook is skipped when any entry whose matcher covers the tool (exact name, `A|B` list, regex or empty matcher) already runs it, so an existing `Edit|Write|...` entry is respected. Only missing hooks are added, to the first entry whose matcher equals the tool, and `settings.json` is rewritten in place, so a symlinked file keeps its link. If `settings.json` is not valid JSON, the installer warns and registers nothing.

### Skills

Claude Code discovers skills in `~/.claude/skills/`. After install, invoke by name in any session:
```
/clog-day
/clog-lessons
```

---

## Codex

**Support level:** Skills only.

### Install

Run `./setup.sh` and select Codex when prompted. The installer symlinks `skills/*/` into `~/.codex/skills/`.

### Caveats

Codex does not currently expose a `PostToolUse` hooks API. None of the five hooks (`post-action-log.sh`, `post-log-reminder.sh`, `post-edit-log-check.sh`, `post-write-clog.sh`, `pre-agent-clog.sh`) can be registered for Codex sessions.

This means:
- `git commit`, `git push`, and `gh pr create` are **not** auto-logged in Codex sessions. Log them manually with `clog COMMIT "..."` etc.
- The 15-minute staleness reminder does not fire in Codex sessions.

When Codex exposes a hooks API, this file will be updated.

---

## Cursor

**Support level:** Skills only.

### Install

Run `./setup.sh` and select Cursor when prompted. The installer symlinks `skills/*/` into `~/.cursor/skills/`.

### Caveats

Cursor does not currently expose a PostToolUse (or equivalent) hooks API. The same limitations as Codex apply: no auto-logging for commits/pushes/PRs, no staleness reminder.

Skills are fully functional — invoke them from the Cursor agent panel.

---

## OpenCode

**Support level:** Skills only.

### Install

Run `./setup.sh` and select OpenCode when prompted. The installer symlinks `skills/*/` into `~/.config/opencode/skills/`.

### Caveats

OpenCode does not currently expose a hooks API. Same limitations as Codex and Cursor.

---

## Standalone (no AI tool)

You can use `bin/clog` without any AI tool integration. Add it to your PATH:

```bash
export PATH="$HOME/clog/bin:$PATH"
```

And log manually from any shell:
```bash
clog ACTION "deployed to staging" --repo my-repo
```

The hooks and skills won't activate without an AI tool, but the JSONL log, the `clog-day`/`clog-week` reports, and the retro skills are all usable via direct invocation.
