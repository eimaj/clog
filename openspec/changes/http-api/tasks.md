# Tasks: http-api

## 1. Toolchain

- [x] 1.1 Add `package.json` (ESM, private, `hono` and `@hono/node-server`), `tsconfig.json` (strict, NodeNext, `erasableSyntaxOnly`), `eslint.config.js` and ignore `node_modules/` and `dist/`.

## 2. Server

- [x] 2.1 `src/server/errors.ts`: `HttpError` and the stderr-line to status/code mapping.
- [x] 2.2 `src/server/config.ts`: resolve config by running `lib/config.sh` `load_config`.
- [x] 2.3 `src/server/app.ts`: `createClogRouter` (health, config, entries write and read) and `createApp` (CORS, 64 KiB body limit).
- [x] 2.4 `tests/server.test.ts`: in-process tests for every route, error mapping, CORS and mounting.
- [x] 2.5 `src/server/app.ts`: `POST /entries` requires `Content-Type: application/json` (415 `unsupported_media_type` before parsing or spawning), so a non-preflighted cross-origin form or text POST cannot write.
- [x] 2.6 `src/server/app.ts`: `createApp` rejects any `Host` other than `127.0.0.1` or `localhost` (optional port) with 403 `forbidden_host`, before CORS and the body limit; the router stays host-agnostic.

- [x] 2.7 `src/server/config.ts`: the loader prints `env -0` and splits on NUL, so a multi-line parent env var cannot forge a `CLOG_*` line.
- [x] 2.8 `src/server/app.ts`: one `bin/clog` write child at a time per router (promise chain); reads are not queued.
- [x] 2.9 `src/server/app.ts`: `token` option; `GET /config`, `GET /entries` and `POST /entries` require `Authorization: Bearer` (401 `unauthorized`); `Authorization` added to CORS `allowHeaders`.
- [x] 2.10 `src/server/app.ts`: NUL in a field is 400 `invalid_field`; a child that echoed one JSON line then exited non-zero is 201 with `warning`.
- [x] 2.11 `src/server/app.ts`: optional `tags: string[]` in the write body, passed as `--tags`; non-array, empty, comma or NUL items are 400 `invalid_field`.
- [x] 2.12 `src/server/app.ts`: `GET /entries?tag=` keeps entries whose `tags` contains the value; empty `tag` is 400 `invalid_tag`.
- [x] 2.13 `src/server/app.ts`: the write child's env drops `CLAUDE_CODE_SESSION_ID`, `CLAUDE_SESSION_ID`, `CODEX_SESSION_ID`, `CURSOR_SESSION_ID`, so `session` appears only when the body supplies it.
- [x] 2.14 `src/server/app.ts`: under `CLOG_DISABLE=1`, `POST /entries` resolves the config first, so a missing config is 503 `no_config` on all three guarded routes.
- [x] 2.15 `src/server/app.ts`: an empty `GET /entries?date=` means today, as in the CLI and on POST.
- [x] 2.16 `tests/server.test.ts`: `HEAD /health` is 200 with an empty body and `HEAD /nope` is 404.

## 3. Serve command

- [x] 3.1 `src/server/serve.ts`: `--port` parsing, loopback bind, listening line, SIGINT/SIGTERM.
- [x] 3.2 `bin/clog`: `serve` dispatch with the node and build checks, and the usage line.
- [x] 3.3 `tests/serve.test.ts`: child-process smoke against the built server, including `--port N`, loopback-only bind and the token.
- [x] 3.4 `src/server/serve.ts`: per-launch token (`CLOG_API_TOKEN` or random), printed as the second stdout line; `serve --help` usage line.

## 4. Demo and static routes

- [x] 4.1 `docs/api/demo.html`: self-contained write form and filtered list, with a token field sent as `Authorization`.
- [x] 4.2 `GET /demo` and `GET /docs` routes.

## 5. Docs

- [x] 5.1 `README.md`: HTTP API section.
- [x] 5.2 `docs/api/index.html`: `serve` operation and the route table.

## 6. Verification

- [x] 6.1 `npm run check` passes and names the number of tests run.
- [x] 6.2 `npm run build` produces `dist/server/serve.js` and `clog serve` runs from it.
- [x] 6.3 `openspec validate http-api --strict` passes.
