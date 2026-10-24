# CLI harness

Black-box tests for `bin/clog`, `lib/config.sh` and `hooks/*.sh`, pinned to `openspec/specs/{cli,log-entry,config,hooks}/spec.md`. Plain bash; needs `jq` and `git` (`yq` is optional, the parity cases skip without it).

## Run

```bash
npm run check:cli                 # whole suite
bash tests/cli/run.sh hooks/      # only cases whose name contains "hooks/"
```

Output is `ok <name>` / `FAIL <name>: <detail>` / `skip <name>: <reason>` per case, then `N passed, M failed`. Exit 1 on any failure. It never touches `~/Code/logs` or `~/.config`: every case builds its own `mktemp -d` with a config copied from `config/config.yaml.example` and `CLOG_TAGS_FILE=/nonexistent`.

## Add a case

1. Add `c_<group>__<scenario>() { ... }` to `run.sh` (group is `cli`, `entry`, `config` or `hooks`). The runner finds it by name and runs it in a subshell with a fresh scratch dir, so order does not matter.
2. Drive the tool with `runclog ARGS...`, `hook <hook-file>` (set `STDIN` first), or `dumpv <PATH> <cfg> [load_config args]` for config cases. Set `ENVX=(VAR=value)` to change the environment, `RUNDIR` for the working directory, `mkrepo DIR` for a git repo.
3. Assert with `expect <label> <rc> <stdout-pat> <stderr-pat>`, `expect_json <label> <file> <jq-expr> <expected> [line]`, `expect_file <label> <path> exists|absent|lines=N`, `expect_eq`.

Patterns: `-` any, `EMPTY`, `=exact`, `^prefix`, `~substring`, otherwise a glob.

When the spec disagrees with the code, do not change the code here: assert the real behaviour and mark the case with a `# KNOWN GAP` comment.
