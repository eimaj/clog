# Delta for cli

## ADDED Requirements

### Requirement: Serve subcommand
When the first argument is `serve`, the CLI SHALL hand the remaining arguments to the compiled HTTP server and SHALL do so before loading the config. The server is documented in the `http-api` spec.

#### Scenario: Serve without a config
- **WHEN** `CLOG_CONFIG` points at a missing file and the user runs `clog serve --port 0`
- **THEN** the server starts and prints its listening line

### Requirement: Serve preconditions
`clog serve` SHALL print `clog: node is required for 'clog serve'` and exit 1 when `node` is not on PATH. It SHALL print `clog: run 'npm run build' first` and exit 1 when `dist/server/serve.js` does not exist.

#### Scenario: Not built
- **WHEN** `dist/` does not exist and the user runs `clog serve`
- **THEN** stderr is `clog: run 'npm run build' first` and the exit code is 1

### Requirement: Serve usage line
The usage text SHALL include the line `  clog serve [--port N]   start the local HTTP API (default 127.0.0.1:4848)`.

#### Scenario: Help lists serve
- **WHEN** the user runs `clog --help`
- **THEN** stdout contains `clog serve [--port N]` and the exit code is 0
