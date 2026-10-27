---
name: clog-sweep-sessions
description: Sweep named Claude Code sessions (by session id, closed or running, any day) for unlogged state-changes and backfill them on the right session, day and time. Use when /pm-end or /pa-eod needs every session of a project checked, or when the user says "sweep sessions <ids>", "clog sweep these sessions", or "backfill clogs for session <id>". For the current session only, use clog-sweep.
model: haiku
---

# clog-sweep-sessions

> For type definitions, `--family`/`--kpi` tables, and when-to-log rules: [`config/rules.md`](../../config/rules.md). This skill is the cross-session sibling of [`clog-sweep`](../clog-sweep/SKILL.md); it reuses that skill's scout prompt and leaves it unchanged.

## Trigger

**Use when:**
- conductor's `/pm-end` or `/pa-eod` calls it with session ids
- the user says "sweep sessions <ids>" (optionally with `--date YYYY-MM-DD`, repeatable, to limit the days)

**Do not use when:** sweeping only the current session ("clog it") — use `clog-sweep`.
**Inputs:** one or more session ids; optional dates.

## Scripts

All in `scripts/`, bash + jq. Deterministic work lives there; only the scan in step 2 is AI judgement.

| Script | Job |
| --- | --- |
| `resolve.sh <sid>…` | One JSON line per sid: `{sid,transcript,dates}`, `{sid,status:"no_transcript"}`, or `{sid,transcript,status:"unreadable"}` |
| `logs-for.sh <date>…` | Day-file path per date; exits 1 when clog is disabled |
| `gaps.sh <sid>` | Candidate records on stdin minus those already logged for that session within ±60 s |
| `backfill-cmds.sh <sid>` | Gap records on stdin become `clog` backfill commands plus the paired LEARNING |

## Steps

Run once per session. A session that fails never stops the others.

1. **Resolve.** `scripts/resolve.sh <sid>…`. For `no_transcript` or `unreadable`, record that status and move on. If the caller gave `--date`, sweep only those dates; otherwise every date in `dates`.

2. **Dispatch one scout per session** (in Claude Code: `subagent_type=general-purpose`). Use the Mode B scout prompt from [`clog-sweep`](../clog-sweep/SKILL.md#mode-b--backfill) with two changes:
   - the transcript is that session's `transcript`, and the logs are the files from `scripts/logs-for.sh <date>…` for the dates being swept;
   - replace its output format with **JSON lines, no prose**, one per miss, times in the **local timezone** (transcript timestamps are UTC):
     ```
     {"date":"YYYY-MM-DD","time":"HH:MM:SS","type":"CODE","summary":"…","why":"<pattern that defeated logging>","file":"/optional/path"}
     ```
     `time` is the time of the tool call, not now. `why` names a pattern from [clog-sweep's list](../clog-sweep/SKILL.md#patterns-to-name-in-the-learning).

   Dispatch the scouts in parallel when there is more than one session.

3. **Filter to real gaps.** Pipe the scout's records through `scripts/gaps.sh <sid>`. It drops any action that already has an entry for that session within ±60 s on its day, including entries an earlier run backfilled, so a second run over the same session reports zero gaps and writes nothing. Its output is the gap list; trust it over the scout's own log check.

4. **Build the backfill commands.** Pipe the gap records to `scripts/backfill-cmds.sh <sid>`. Every emitted line carries `--session <sid> --date <day> --time <action time>`; each action is followed by its paired LEARNING. Do not hand-write backfill lines.

5. **Execute the emitted block as-is.** No approval pause. Skip when there are no gaps. The entries land in the action's day file with `time` set to the action time and `logged_at` set to now.

## Notes

- Long sessions: if a transcript is too big for one scout, narrow it to a time range per scout and merge the records.
- Never run the scout against the current folder's transcript by path guess; always use `resolve.sh`.

## Signal Keywords
<!-- Comma-separated terms the skills collector uses to attribute learnings to this skill -->
clog-sweep-sessions, sweep sessions, sweep session, backfill session, cross-session sweep, pm-end sweep, pa-eod sweep, unlogged actions, session sweep
