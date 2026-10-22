import { randomBytes } from 'node:crypto';
import * as fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { serve } from '@hono/node-server';
import { createApp } from './app.ts';

/**
 * `clog serve [--port N]`: bind the HTTP API to loopback only and run until
 * SIGINT/SIGTERM. Port 0 asks the OS for a free port; the listening line on
 * stdout always carries the real one. The second stdout line carries the
 * bearer token (`CLOG_API_TOKEN` when set, else random per launch).
 */

export const DEFAULT_PORT = 4848;
const HOST = '127.0.0.1';
const MAX_PORT = 65_535;
const PORT_PATTERN = /^[0-9]{1,5}$/;
const SHUTDOWN_GRACE_MS = 2000;

class UsageError extends Error {}

function parsePort(args: string[]): number {
  if (args.length === 0) return DEFAULT_PORT;
  const [flag, raw] = args;
  if (flag !== '--port') throw new UsageError(`clog: unknown argument '${flag ?? ''}'`);
  if (args.length > 2) throw new UsageError(`clog: unknown argument '${args[2] ?? ''}'`);
  const value = raw ?? '';
  const port = PORT_PATTERN.test(value) ? Number.parseInt(value, 10) : Number.NaN;
  if (Number.isNaN(port) || port > MAX_PORT) {
    throw new UsageError(`clog: invalid --port '${value}'`);
  }
  return port;
}

export const SERVE_USAGE =
  'Usage: clog serve [--port N]   (default 127.0.0.1:4848; prints the API token on start)\n';

export async function runServe(argv: string[]): Promise<void> {
  if (argv[0] === '--help' || argv[0] === '-h') {
    process.stdout.write(SERVE_USAGE);
    return;
  }
  let port: number;
  try {
    port = parsePort(argv);
  } catch (err) {
    if (!(err instanceof UsageError)) throw err;
    process.stderr.write(`${err.message}\n`);
    process.exit(1);
  }

  // A blank value is treated as unset: HTTP clients cannot send a whitespace-only bearer.
  const envToken = process.env['CLOG_API_TOKEN']?.trim() ?? '';
  const token = envToken !== '' ? envToken : randomBytes(16).toString('hex');
  const app = createApp({ token });
  await new Promise<void>((resolve, reject) => {
    const server = serve({ fetch: app.fetch, hostname: HOST, port }, (info) => {
      process.stdout.write(`clog API listening on http://${HOST}:${info.port}\n`);
      process.stdout.write(`clog API token: ${token}\n`);
      resolve();
    });
    server.once('error', reject);

    const shutdown = (): void => {
      // server.close() drops idle keep-alive sockets; the timer caps how long
      // an in-flight request can hold the process open.
      setTimeout(() => process.exit(0), SHUTDOWN_GRACE_MS).unref();
      server.close((err) => {
        if (err) {
          process.stderr.write(`clog serve: ${err.message}\n`);
          process.exit(1);
        }
        process.exit(0);
      });
    };
    process.once('SIGINT', shutdown);
    process.once('SIGTERM', shutdown);
  });
}

const entry = process.argv[1];
if (entry !== undefined && fs.realpathSync(entry) === fileURLToPath(import.meta.url)) {
  runServe(process.argv.slice(2)).catch((err: unknown) => {
    const message = err instanceof Error ? err.message : String(err);
    process.stderr.write(`clog serve: ${message}\n`);
    process.exit(1);
  });
}
