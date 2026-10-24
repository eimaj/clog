# CLI harness

Black-box tests for `bin/clog`, `lib/config.sh` and `hooks/*.sh`, pinned to `openspec/specs/{cli,log-entry,config,hooks}/spec.md`. Plain bash; needs `jq` and `git` (`yq` is optional, the parity cases skip without it).

## Run

```bash
npm run check:cli                 # whole suite
bash tests/cli/run.sh hooks/      # only cases whose name contains "hooks/"
```

Output is `ok <name>` / `FAIL <name>: <detail>` / `skip <name>: <reason>` per case, then `N skipped` (only when something skipped; skips do not fail the run) and `N passed, M failed`. Exit 1 on any failure. A case named `c_hooks__push_line` prints as `hooks/push_line`; the optional argument is a substring filter on that printed name. It never touches `~/Code/logs` or `~/.config`: every case builds its own `mktemp -d` with a config copied from `config/config.yaml.example` and `CLOG_TAGS_FILE=/nonexistent`.

## Add a case

1. Add `c_<group>__<scenario>() { ... }` to `run.sh` (group is `cli`, `entry`, `config` or `hooks`). The runner treats every column-0 function whose name starts with `c_` as a case, so never give a helper that prefix. Each case runs in a subshell with a fresh scratch dir, so order does not matter.
2. Drive the tool with `runclog ARGS...`, `hook <hook-file>` (set `STDIN` first), or `dumpv <PATH> <cfg> [load_config args]` for config cases. Set `ENVX=(VAR=value)` to change the environment, `RUNDIR` for the working directory, `mkrepo DIR` for a git repo.
3. Assert with `expect <label> <rc> <stdout-pat> <stderr-pat>`, `expect_json <label> <file> <jq-expr> <expected> [line]`, `expect_file <label> <path> exists|absent|lines=N`, `expect_eq`.

Patterns: `-` any, `EMPTY`, `=exact`, `^prefix`, `~substring`, otherwise a glob. `-` also works for `<rc>`.

Hook fixtures that must contain a git verb the agent shell guard blocks (for example the push case) keep the verb in a variable, `local P=push`, so the file never spells the guarded phrase. Do not inline those.

When the spec disagrees with the code, do not change the code here: assert the real behaviour and put a `# KNOWN GAP: <spec file> "<scenario>" ...` comment directly above the case function. Remove the comment in the same commit that fixes the spec or the code. `grep -n 'KNOWN GAP' tests/cli/run.sh` lists the open ones (none at the time of writing).
