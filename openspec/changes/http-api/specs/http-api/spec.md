# Delta for http-api

## Purpose

A local HTTP service, started by `clog serve`, that writes entries by spawning `bin/clog --echo` and reads the daily JSONL files. The CLI remains the single source of truth for validation, config precedence and the JSON line.

## ADDED Requirements

### Requirement: Listening
The server SHALL listen on `127.0.0.1` only, on port 4848 unless `--port N` is given, and SHALL print exactly two stdout lines, `clog API listening on http://127.0.0.1:<port>` then `clog API token: <token>`. `--port 0` SHALL pick a free port and the first line SHALL carry the real one.

#### Scenario: Free port
- **WHEN** the user runs `clog serve --port 0`
- **THEN** the listening line names a real port and `GET /health` on it answers 200

#### Scenario: Chosen port
- **WHEN** the user runs `clog serve --port N` for a free port N
- **THEN** the listening line names port N

### Requirement: Port validation
A `--port` value that is not an integer from 0 to 65535 SHALL print `clog: invalid --port '<v>'` to stderr and exit 1.

#### Scenario: Not a number
- **WHEN** the user runs `clog serve --port abc`
- **THEN** stderr is `clog: invalid --port 'abc'` and the exit code is 1

### Requirement: Shutdown
The server SHALL run until SIGINT or SIGTERM and SHALL then exit 0.

#### Scenario: Interrupt
- **WHEN** the server receives SIGINT
- **THEN** the process exits 0

### Requirement: Health route
`GET /health` SHALL answer 200 with `{ ok: true, version: "1.0", clogBin }`, where `clogBin` is the absolute path of the `bin/clog` in use.

#### Scenario: Health
- **WHEN** a client requests `GET /health`
- **THEN** the body has `ok` true and `version` `1.0`

### Requirement: Config route
`GET /config` SHALL answer 200 with `{ configPath, logRoot, logSubdir, families, kpis }` resolved by `lib/config.sh`, with the lists split on single spaces and empty lists as `[]`.

#### Scenario: Resolved values
- **WHEN** the config declares four families and `GET /config` is requested
- **THEN** `families` has four items

### Requirement: Missing config
When no config file exists, `GET /config`, `GET /entries` and `POST /entries` SHALL answer 503 `no_config` with the CLI's own message, also when `CLOG_DISABLE=1` is set. The server SHALL still start.

#### Scenario: No config
- **WHEN** `CLOG_CONFIG` points at a missing file and a client requests `GET /config`
- **THEN** the status is 503 and `error.code` is `no_config`

### Requirement: Write by spawning the CLI
`POST /entries` SHALL spawn `bin/clog <type> <summary> [flags] --echo` with an argv array, never a shell string, passing only the supplied flags. The child SHALL NOT inherit the launcher's session variables, so `session` is present only when the body supplies it; an omitted `repo` is autodetected from the server's working directory. The server SHALL use the `bin/clog` next to its own module, not the one on PATH.

#### Scenario: Written entry equals CLI entry
- **WHEN** the same type, summary and flags are written through the API and the CLI
- **THEN** the two lines are identical apart from `time`

### Requirement: Write request body
The body SHALL be a JSON object with string `type` and `summary`, optional string `agent`, `repo`, `session`, `model`, `file`, `family`, `kpi` and `date`, and optional `tags`: a non-empty array of non-empty strings without commas or C0/C1 control characters, passed to the CLI as `--tags` so the entry's `tags` is the server's default tags followed by these, trimmed and deduplicated.

#### Scenario: Optional fields
- **WHEN** a client posts `family` and `kpi` along with type and summary
- **THEN** the entry carries both fields

#### Scenario: Tags in the body
- **WHEN** the server runs with `CLOG_DEFAULT_TAGS=jbook` and a client posts `tags: ["release", "jbook"]`
- **THEN** the entry's `tags` is `["jbook","release"]`

#### Scenario: Bad tags
- **WHEN** a client posts `tags: "release"` or `tags: ["a,b"]` or `tags: []`
- **THEN** the status is 400 and `error.code` is `invalid_field`

### Requirement: Write input checks
Before spawning, the server SHALL answer 400 for a body that is not JSON (`invalid_json`), a `type` that is not one of the nine (`invalid_type`), an absent or empty `summary` (`missing_summary`) and a non-string optional field (`invalid_field`). Messages for the first three SHALL match the CLI's.

#### Scenario: Lowercase type
- **WHEN** a client posts type `action`
- **THEN** the status is 400, `error.code` is `invalid_type` and nothing is written

### Requirement: Bearer token
`GET /config`, `GET /entries` and `POST /entries` SHALL require `Authorization: Bearer <token>` (constant-time compare) else 401 `unauthorized`, checked before the body is parsed. `/health`, `/demo`, `/docs` and preflights SHALL NOT need it. `createClogRouter({ token })` SHALL enforce it inside the router; with no `token` the router is open.

#### Scenario: Missing token
- **WHEN** a client requests `GET /entries` with no Authorization header
- **THEN** the status is 401 and `error.code` is `unauthorized`

#### Scenario: Right token
- **WHEN** a client sends `Authorization: Bearer <token>` with a valid write
- **THEN** the status is 201

#### Scenario: Oversized request without a token
- **WHEN** a client posts more than 64 KiB to `/entries` with no Authorization header through `createApp`
- **THEN** the status is 413, because the app-level body limit runs before the router's token check, and nothing is written

### Requirement: Token source
`clog serve` SHALL use `CLOG_API_TOKEN` when it is non-blank after trimming, else a random 32-hex-character token per launch, and SHALL print it as the second stdout line `clog API token: <token>`. The token SHALL NOT appear in any response body.

#### Scenario: Blank environment token
- **WHEN** `CLOG_API_TOKEN` is set to whitespace only
- **THEN** a random 32-hex-character token is generated and printed

#### Scenario: Fixed environment token
- **WHEN** `CLOG_API_TOKEN=fixed-token-123`
- **THEN** `clog API token: fixed-token-123` is printed and that value authorises requests

### Requirement: Serialised writes
The router SHALL run at most one `bin/clog` write child at a time per instance; concurrent `POST /entries` SHALL queue. Reads SHALL NOT be queued.

#### Scenario: Parallel writes
- **WHEN** 20 clients post 20 KiB summaries at once
- **THEN** all answer 201 and the day file has 20 intact lines

### Requirement: NUL rejected
A `summary` or optional field containing U+0000 SHALL answer 400 `invalid_field` before anything is spawned.

#### Scenario: NUL in summary
- **WHEN** a client posts a summary containing a NUL character
- **THEN** the status is 400 and `error.code` is `invalid_field`

### Requirement: Write succeeded with warning
When the CLI exits non-zero but stdout holds exactly one parseable JSON object line, the entry was written and the server SHALL answer 201 `{ entry, file, warning }`, with `warning` the first stderr line.

#### Scenario: Auto-commit fails
- **WHEN** the CLI prints the entry and then exits 2 with stderr `git: commit failed`
- **THEN** the status is 201 and `warning` is `git: commit failed`

### Requirement: Write success
A write that the CLI accepts SHALL answer 201 `{ entry, file }`, where `entry` is the echoed line parsed and `file` is the absolute path of that day's file. An entry carrying `validation` SHALL still be a 201.

#### Scenario: Unknown family
- **WHEN** a client posts `family` `nope`
- **THEN** the status is 201 and `entry.validation` is `unknown_family`

### Requirement: Write failure mapping
CLI stderr starting `clog: unknown type`, `clog: invalid --date` or `clog: missing summary` SHALL map to 400 (`invalid_type`, `invalid_date`, `missing_summary`); `clog: no config at` SHALL map to 503 `no_config`. Exit 0 with empty stdout SHALL map to 503 `disabled`. Any other non-zero exit, a missing binary or unparseable stdout SHALL map to 500 `clog_failed`. The first stderr line SHALL be the `message`.

#### Scenario: Bad date
- **WHEN** a client posts `date` `../../evil`
- **THEN** the status is 400, `error.code` is `invalid_date` and no file is created outside the read root

### Requirement: Write timeout
A `bin/clog` child that runs longer than 10 seconds SHALL be killed and answered with 500 `clog_timeout`.

#### Scenario: Stuck child
- **WHEN** the spawned CLI does not exit within 10 seconds
- **THEN** the status is 500 and `error.code` is `clog_timeout`

### Requirement: Disabled logging
When `CLOG_DISABLE` is exactly `1` in the server's environment and a config file exists, `POST /entries`, `GET /config` and `GET /entries` SHALL answer 503 `disabled` after the config file is found and before anything is spawned or read, whether or not a log root is also set in the environment. With no config file all three answer `no_config`.

#### Scenario: Disabled
- **WHEN** the server runs with `CLOG_DISABLE=1` and a client posts an entry
- **THEN** the status is 503 and nothing is written

#### Scenario: Disabled reads
- **WHEN** the server runs with `CLOG_DISABLE=1` and a client requests `GET /entries`
- **THEN** the status is 503 and `error.code` is `disabled`

### Requirement: Write content type
`POST /entries` SHALL require `Content-Type: application/json` (parameters allowed) and SHALL otherwise answer 415 `unsupported_media_type` before parsing the body or spawning.

#### Scenario: Cross-origin text/plain
- **WHEN** a client posts with `Content-Type: text/plain` and `Origin: https://evil.example`
- **THEN** the status is 415 and nothing is written

### Requirement: Host allowlist
`createApp` SHALL answer 403 `forbidden_host` for a `Host` header that is not `127.0.0.1` or `localhost`, each with an optional port, before CORS is evaluated. `createClogRouter` SHALL NOT check the host.

#### Scenario: Foreign host
- **WHEN** a request carries `Host: attacker.example:4848`
- **THEN** the status is 403 and `error.code` is `forbidden_host`

### Requirement: Read route
`GET /entries` SHALL answer 200 `{ date, file, entries, skipped }` for `<log_root>/<log_subdir>/<YYYYMMDD>.jsonl`, defaulting `date` to today in local time. The file SHALL be read fresh on every request.

#### Scenario: Default day
- **WHEN** a client requests `GET /entries` without a date
- **THEN** `date` is today and `entries` holds that day's entries

### Requirement: Read filters
`type`, `repo`, `session` and `agent` SHALL filter by exact match; `tag` SHALL keep entries whose `tags` array contains the trimmed value (entries without `tags` never match); all SHALL be ANDed. `tail=N` SHALL keep the last N entries after filtering. An empty or repeated `tag` SHALL be 400 `invalid_tag`.

#### Scenario: Tail after filter
- **WHEN** a client requests `?repo=a&tail=2`
- **THEN** the last two entries with repo `a` are returned

#### Scenario: Tag filter
- **WHEN** a client requests `?tag=release`
- **THEN** only entries whose `tags` contains `release` are returned

### Requirement: Read validation
`date` SHALL match `YYYY-MM-DD` as in the CLI (`invalid_date`), except that an empty `date` means today, `type` SHALL be one of the nine (`invalid_type`) and `tail` SHALL be an integer from 1 to 10000 (`invalid_tail`); each failure SHALL be a 400.

#### Scenario: Bad tail
- **WHEN** a client requests `?tail=0`
- **THEN** the status is 400 and `error.code` is `invalid_tail`

### Requirement: Missing and corrupt data
A missing day file SHALL answer 200 with `entries: []`. A line that is not a JSON object SHALL be skipped and counted in `skipped`.

#### Scenario: Corrupt line
- **WHEN** a day file holds one valid line and one broken line
- **THEN** `entries` has one item and `skipped` is 1

### Requirement: Error shape
Every error body SHALL be `{ error: { code, message } }`. No body SHALL contain a stack trace. An unexpected failure SHALL answer 500 `internal_error` with the message `internal server error`. Unknown routes and unsupported methods SHALL answer 404 `not_found`; `HEAD` on a GET route SHALL answer like GET without a body.

#### Scenario: Unknown route
- **WHEN** a client requests `GET /nope`
- **THEN** the status is 404 and `error.code` is `not_found`

### Requirement: Body limit
A request body over 64 KiB SHALL answer 413 `payload_too_large`.

#### Scenario: Oversized body
- **WHEN** a client posts a 65 KiB summary
- **THEN** the status is 413 and nothing is written

### Requirement: CORS
The server SHALL allow cross-origin requests only from origins matching `^http://(localhost|127\.0\.0\.1)(:\d+)?$`, echoing the origin, for `GET, POST, OPTIONS` and the `Content-Type` and `Authorization` headers. Any other origin, including `null`, SHALL get no allow header. A preflight SHALL answer 204.

#### Scenario: Foreign origin
- **WHEN** a request carries `Origin: https://example.com`
- **THEN** the response has no `Access-Control-Allow-Origin` header

### Requirement: Static pages
`GET /demo` SHALL serve `docs/api/demo.html` and `GET /docs` SHALL serve `docs/api/index.html`, both as `text/html`. The demo page SHALL load no external script, stylesheet or asset.

#### Scenario: Demo page
- **WHEN** a client requests `GET /demo`
- **THEN** the status is 200 and the body is the demo page

### Requirement: Mountable router
The routes SHALL be exported as `createClogRouter(options)` with relative paths only, so another Hono app can mount them under a prefix. The router SHALL carry no Host, CORS or body-limit guard; the mounting app owns those.

#### Scenario: Mounted under a prefix
- **WHEN** the router is mounted at `/clog`
- **THEN** `GET /clog/health` answers 200
