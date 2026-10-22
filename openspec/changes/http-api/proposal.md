# Change: http-api

## Why

Browsers and other tools cannot write a clog entry without shelling out. A local HTTP service lets a web UI (and, later, `crrt serve`) log and read entries while the CLI stays the single source of truth for validation, config precedence and the JSON line.

## What Changes

- New subcommand `clog serve [--port N]`: a Hono server on `127.0.0.1` (default port 4848) compiled from TypeScript to `dist/`.
- Every write spawns `bin/clog --echo`; the echoed line is returned as the entry. The server never reimplements the CLI's rules.
- New read surface over the daily JSONL files: `GET /entries` with date, type, repo, session, agent and tail filters, plus `GET /config` and `GET /health`.
- `POST /entries` requires a JSON content type and `createApp` allows only local `Host` headers, so a foreign web page cannot write through the browser.
- `clog serve` prints a per-launch bearer token (or uses `CLOG_API_TOKEN`); `GET /config`, `GET /entries` and `POST /entries` require it, so another local web page cannot read or forge entries.
- Writes run one `bin/clog` at a time, and a write that succeeded but exited non-zero answers 201 with a `warning`.
- The routes are exported as `createClogRouter` so another Hono app can mount them under a prefix; pass `token` to require bearer auth, the mounting app owns Host, CORS and body limits.
- A self-contained demo page (`GET /demo`) and the reference page (`GET /docs`) are served from `docs/api/`.
- `bin/clog` dispatches `serve` after the `--help` check and before the config load; `usage()` gains one line.

## Impact

- Affected specs: `http-api` (new capability), `cli` (three ADDED requirements).
- Affected code: `bin/clog` (dispatch and usage line only), new `src/server/`, new toolchain files (`package.json`, `tsconfig.json`, `eslint.config.js`).
- Not affected: entry format, file naming, hooks, config. The CLI's behaviour for every other invocation is byte-identical.
