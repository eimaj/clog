# Change: cli-echo

## Why

`bin/clog` prints nothing on success, so any caller that needs the entry it just wrote (a script, the planned HTTP API) has to read the log file back and guess that the last line is its own. That guess is wrong whenever a hook writes in the same instant. The CLI already has the line in `$ENTRY`; handing it back costs one `echo`.

## What Changes

- New flag `--echo`: after a successful append, print the exact JSON line that was written to stdout.
- Under `CLOG_DISABLE=1` nothing is written and nothing is printed (unchanged exit 0).
- The "Success output" requirement of the `cli` spec is modified: stdout is empty on success *unless* `--echo` is given.
- Usage text, `skills/clog/SKILL.md`, `README.md` and `docs/api/index.html` document the flag.

## Impact

- Affected specs: `cli` (one ADDED requirement, one MODIFIED requirement).
- Affected code: `bin/clog` only (flag parse, one conditional `echo`).
- Not affected: entry format, file naming, hooks, config. Hooks never pass `--echo`, so their behaviour is byte-identical.
