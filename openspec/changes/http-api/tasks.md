# Tasks: http-api

## 1. Toolchain

- [x] 1.1 Add `package.json` (ESM, private, `hono` and `@hono/node-server`), `tsconfig.json` (strict, NodeNext, `erasableSyntaxOnly`), `eslint.config.js` and ignore `node_modules/` and `dist/`.

## 2. Server

- [x] 2.1 `src/server/errors.ts`: `HttpError` and the stderr-line to status/code mapping.
- [x] 2.2 `src/server/config.ts`: resolve config by running `lib/config.sh` `load_config`.
- [x] 2.3 `src/server/app.ts`: `createClogRouter` (health, config, entries write and read) and `createApp` (CORS, 64 KiB body limit).
- [x] 2.4 `tests/server.test.ts`: in-process tests for every route, error mapping, CORS and mounting.

## 3. Serve command

- [x] 3.1 `src/server/serve.ts`: `--port` parsing, loopback bind, listening line, SIGINT/SIGTERM.
- [x] 3.2 `bin/clog`: `serve` dispatch with the node and build checks, and the usage line.
- [x] 3.3 `tests/serve.test.ts`: child-process smoke against the built server.

## 4. Demo and static routes

- [x] 4.1 `docs/api/demo.html`: self-contained write form and filtered list.
- [x] 4.2 `GET /demo` and `GET /docs` routes.

## 5. Docs

- [x] 5.1 `README.md`: HTTP API section.
- [x] 5.2 `docs/api/index.html`: `serve` operation and the route table.

## 6. Verification

- [x] 6.1 `npm run check` passes and names the number of tests run.
- [x] 6.2 `npm run build` produces `dist/server/serve.js` and `clog serve` runs from it.
- [x] 6.3 `openspec validate http-api --strict` passes.
