# Tasks: cli-echo

## 1. CLI

- [x] 1.1 Parse `--echo` in the flag loop of `bin/clog` (boolean, no value).
- [x] 1.2 After the append, print `$ENTRY` to stdout when `--echo` was given.
- [x] 1.3 Add the flag to the header comment and to `usage()`.

## 2. Docs

- [x] 2.1 `skills/clog/SKILL.md`: synopsis and a bullet.
- [x] 2.2 `README.md`: Quick start example.
- [x] 2.3 `docs/api/index.html`: synopsis, parameter row, response row.

## 3. Verification

- [x] 3.1 Against a scratch `CLOG_CONFIG`: `--echo` prints exactly the file's new last line; without `--echo` stdout is empty; `CLOG_DISABLE=1 … --echo` prints nothing and exits 0; `--echo` in the TYPE position is rejected as an unknown type.
- [x] 3.2 `openspec validate cli-echo --strict` passes.
