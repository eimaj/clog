# Cowork logging snippet

Paste the block below into any new Cowork project's instructions to enable clog.
Replace `<prefix>` with a short project slug (e.g. `council-weekly`, `ads-infra`).

**Before pasting:** connect these three folders to the project
(Claude can request them itself if you ask, or add them via the folder picker):

- `~/Code/clog`
- `~/Code/logs`
- `~/.config/clog`

---

## Logging

Everything in this project is logged via clog. Log all connector calls, file
writes, decisions, failures, and task start/end. Log before acting, log the
result, log failures immediately — do not batch or skip.

Setup (once per task, before the first clog call): the Cowork sandbox rebuilds
each session and `clog` is NOT on PATH there. Run:
`bash /sessions/*/mnt/clog/bin/cowork-bootstrap.sh`
This requires the folders ~/Code/clog, ~/Code/logs, and ~/.config/clog to be
connected to the project. If they aren't, request them with the folder-access
tool, then re-run the bootstrap. If it still fails, note the failure in chat
and continue the task without logging.

Signature: `"$HOME/.local/bin/clog" <TYPE> "<summary>"` where TYPE is one of
ACTION | CODE | DECISION | FOLLOWUP | LEARNING. Bare `clog` will not resolve in
the sandbox — always use the full path. All summaries in this project use the
`<prefix>:` prefix.

Logging pattern for every unit of work:
- At task start: `"$HOME/.local/bin/clog" ACTION "<prefix>: task started"`
- Before each significant step: ACTION describing what is starting
- After each step: ACTION with the result (include counts, e.g. "14 msgs scanned")
- Before writing any file: CODE with the path and one-line purpose
- On any decision between alternatives: DECISION with what was decided and why
- On any failure or empty source: FOLLOWUP with the reason — immediately, not at the end
- At task end: `"$HOME/.local/bin/clog" ACTION "<prefix>: task complete — <one-line outcome>"`
