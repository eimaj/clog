import { execFile } from 'node:child_process';
import { timingSafeEqual } from 'node:crypto';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Hono } from 'hono';
import type { Context, MiddlewareHandler } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { cors } from 'hono/cors';
import { loadClogConfig, readRootOf, repoRootOf, DISABLED_MESSAGE } from './config.ts';
import { HttpError, errorFromStderr, firstLine, toErrorResponse } from './errors.ts';
import type { ErrorBody } from './errors.ts';

/**
 * Every write spawns `bin/clog --echo`; the API never reimplements validation,
 * config precedence or the JSON line. Reads parse the daily JSONL files.
 * Routes are relative so the router can be mounted under any prefix.
 */

export interface ClogRouterOptions {
  /** The `bin/clog` to spawn for writes and to resolve config and docs from. */
  clogBin?: string;
  /**
   * When set, `GET /config`, `GET /entries` and `POST /entries` require
   * `Authorization: Bearer <token>` and answer 401 otherwise. When undefined the
   * router is open; the mounting app decides. `/health`, `/demo` and `/docs`
   * never need it. An empty string is rejected at construction.
   */
  token?: string;
}

export type Entry = Record<string, unknown>;

const API_VERSION = '1.0';
const ENTRY_TYPES = [
  'DECISION',
  'ACTION',
  'CODE',
  'PR',
  'COMMIT',
  'REPO',
  'FOLLOWUP',
  'LEARNING',
  'LESSON',
] as const;
const OPTIONAL_FIELDS = ['agent', 'repo', 'session', 'model', 'file', 'family', 'kpi', 'date'] as const;
const FILTER_FIELDS = ['type', 'repo', 'session', 'agent'] as const;
const DATE_PATTERN = /^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/;
const TAIL_PATTERN = /^[0-9]{1,5}$/;
// eslint-disable-next-line no-control-regex -- C0 and C1 control characters are the point
const CONTROL_CHAR_PATTERN = /[\u0000-\u001f\u007f-\u009f]/;
const MAX_TAIL = 10_000;
const SPAWN_TIMEOUT_MS = 10_000;
const SPAWN_MAX_BUFFER = 1024 * 1024;
// bin/clog falls back to these for `session`; a write must not inherit the launcher's.
const SESSION_ENV_KEYS = [
  'CLAUDE_CODE_SESSION_ID',
  'CLAUDE_SESSION_ID',
  'CODEX_SESSION_ID',
  'CURSOR_SESSION_ID',
];

function childEnv(): NodeJS.ProcessEnv {
  const env = { ...process.env };
  for (const key of SESSION_ENV_KEYS) delete env[key];
  return env;
}
const MAX_BODY_BYTES = 64 * 1024;
const DEMO_PAGE = 'demo.html';
const REFERENCE_PAGE = 'index.html';
const LOCAL_ORIGIN_PATTERN =/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;
const LOCAL_HOST_PATTERN = /^(localhost|127\.0\.0\.1)(:\d+)?$/i;

const DEFAULT_CLOG_BIN = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  '..',
  'bin',
  'clog',
);

function isEntryType(value: string): boolean {
  return (ENTRY_TYPES as readonly string[]).includes(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasBearerToken(header: string | undefined, token: string): boolean {
  const match = /^bearer (.+)$/i.exec(header ?? '');
  if (match?.[1] === undefined) return false;
  const given = Buffer.from(match[1]);
  const expected = Buffer.from(token);
  // timingSafeEqual throws on unequal lengths, and length is not the secret.
  return given.length === expected.length && timingSafeEqual(given, expected);
}

function describeType(value: unknown): string {
  if (value === undefined) return '';
  return typeof value === 'string' ? value : JSON.stringify(value);
}

function localDate(): string {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${now.getFullYear()}-${month}-${day}`;
}

function logFileName(date: string): string {
  return `${date.replaceAll('-', '')}.jsonl`;
}

function invalidDate(value: string): HttpError {
  return new HttpError(
    400,
    'invalid_date',
    `clog: invalid --date '${value}' (expected YYYY-MM-DD)`,
  );
}

interface ClogRun {
  exitCode: number;
  stdout: string;
  stderr: string;
}

function runClog(clogBin: string, args: string[]): Promise<ClogRun> {
  return new Promise((resolve, reject) => {
    execFile(
      clogBin,
      args,
      { encoding: 'utf-8', timeout: SPAWN_TIMEOUT_MS, maxBuffer: SPAWN_MAX_BUFFER, env: childEnv() },
      (error, stdout, stderr) => {
        if (error === null) {
          resolve({ exitCode: 0, stdout, stderr });
        } else if (error.killed === true) {
          reject(new HttpError(500, 'clog_timeout', 'clog: timed out after 10s'));
        } else if (typeof error.code === 'number') {
          resolve({ exitCode: error.code, stdout, stderr });
        } else {
          reject(new HttpError(500, 'clog_failed', `clog: cannot run ${clogBin}: ${error.message}`));
        }
      },
    );
  });
}

interface WriteRequest {
  type: string;
  summary: string;
  flags: string[];
  date: string | undefined;
}

async function parseWriteRequest(c: Context): Promise<WriteRequest> {
  // A cross-origin `text/plain` POST is a CORS "simple request": the browser
  // sends it without a preflight, so the content type is the only gate.
  const mediaType = (c.req.header('content-type') ?? '').split(';')[0]?.trim().toLowerCase();
  if (mediaType !== 'application/json') {
    throw new HttpError(
      415,
      'unsupported_media_type',
      'Content-Type must be application/json',
    );
  }
  let raw: unknown;
  try {
    raw = await c.req.json();
  } catch {
    throw new HttpError(400, 'invalid_json', 'request body must be valid JSON');
  }
  const body = isRecord(raw) ? raw : {};

  const type = body['type'];
  if (typeof type !== 'string' || !isEntryType(type)) {
    throw new HttpError(
      400,
      'invalid_type',
      `clog: unknown type '${describeType(type)}' (expected ${ENTRY_TYPES.join(' | ')})`,
    );
  }
  const summary = body['summary'];
  if (typeof summary !== 'string' || summary === '') {
    throw new HttpError(400, 'missing_summary', 'clog: missing summary');
  }

  // A NUL cannot be passed in an argv entry; spawn would throw. Reject up front.
  const nulField = [['summary', summary], ...OPTIONAL_FIELDS.map((f) => [f, body[f]] as const)].find(
    ([, v]) => typeof v === 'string' && v.includes('\u0000'),
  );
  if (nulField !== undefined) {
    throw new HttpError(400, 'invalid_field', `field '${nulField[0]}' must not contain NUL`);
  }

  const flags: string[] = [];
  let date: string | undefined;
  for (const field of OPTIONAL_FIELDS) {
    const value = body[field];
    if (value === undefined) continue;
    if (typeof value !== 'string') {
      throw new HttpError(400, 'invalid_field', `field '${field}' must be a string`);
    }
    flags.push(`--${field}`, value);
    if (field === 'date' && value !== '') date = value;
  }
  const tags = body['tags'];
  if (tags !== undefined) {
    if (!isStringArray(tags) || tags.length === 0 || tags.some((t) => t.trim() === '')) {
      throw new HttpError(400, 'invalid_field', "field 'tags' must be a non-empty array of non-empty strings");
    }
    // Control characters (C0/C1, including NUL and U+0085) would be stripped or
    // rejected by the CLI's jq trim, so refuse them here to keep the item intact.
    if (tags.some((t) => t.includes(',') || CONTROL_CHAR_PATTERN.test(t))) {
      throw new HttpError(400, 'invalid_field', "field 'tags' items must not contain commas or control characters");
    }
    // The CLI merges these after the machine defaults, trims and dedups.
    flags.push('--tags', tags.join(','));
  }
  return { type, summary, flags, date };
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((v) => typeof v === 'string');
}

/** The one JSON object `bin/clog --echo` prints, or undefined if stdout is anything else. */
function entryFromStdout(stdout: string): Entry | undefined {
  const line = stdout.trim();
  if (line === '' || line.includes('\n')) return undefined;
  const parsed = parseJsonLine(line);
  return isRecord(parsed) ? parsed : undefined;
}

function parseEntryLine(stdout: string): Entry {
  const entry = entryFromStdout(stdout);
  if (entry === undefined) {
    throw new HttpError(500, 'clog_failed', 'clog: unparseable output from bin/clog --echo');
  }
  return entry;
}

interface ReadQuery {
  date: string;
  filters: Array<[string, string]>;
  tag: string | undefined;
  tail: number | undefined;
}

function parseReadQuery(c: Context): ReadQuery {
  const date = c.req.query('date') ?? localDate();
  if (!DATE_PATTERN.test(date)) throw invalidDate(date);

  const type = c.req.query('type');
  if (type !== undefined && !isEntryType(type)) {
    throw new HttpError(
      400,
      'invalid_type',
      `clog: unknown type '${type}' (expected ${ENTRY_TYPES.join(' | ')})`,
    );
  }

  const rawTail = c.req.query('tail');
  let tail: number | undefined;
  if (rawTail !== undefined) {
    tail = TAIL_PATTERN.test(rawTail) ? Number.parseInt(rawTail, 10) : 0;
    if (tail < 1 || tail > MAX_TAIL) {
      throw new HttpError(400, 'invalid_tail', `tail must be an integer from 1 to ${MAX_TAIL}`);
    }
  }

  const filters: Array<[string, string]> = [];
  for (const field of FILTER_FIELDS) {
    const value = c.req.query(field);
    if (value !== undefined) filters.push([field, value]);
  }
  const tags = c.req.queries('tag') ?? [];
  if (tags.length > 1) {
    throw new HttpError(400, 'invalid_tag', 'tag may be given once');
  }
  const tag = tags[0]?.trim();
  if (tag === '') {
    throw new HttpError(400, 'invalid_tag', 'tag must be a non-empty string');
  }
  return { date, filters, tag, tail };
}

/** True when the entry's `tags` array contains `tag` (entries without tags never match). */
function hasTag(entry: Entry, tag: string): boolean {
  const tags = entry['tags'];
  return isStringArray(tags) && tags.includes(tag);
}

function isEnoent(err: unknown): boolean {
  return err instanceof Error && 'code' in err && err.code === 'ENOENT';
}

/** A day's log lines, with the corrupt ones dropped and counted. */
async function readEntries(file: string): Promise<{ records: Entry[]; skipped: number }> {
  let text: string;
  try {
    text = await fs.readFile(file, 'utf-8');
  } catch (err) {
    if (isEnoent(err)) return { records: [], skipped: 0 };
    throw err;
  }
  const records: Entry[] = [];
  let skipped = 0;
  for (const line of text.split('\n')) {
    if (line.trim() === '') continue;
    const parsed = parseJsonLine(line);
    if (isRecord(parsed)) records.push(parsed);
    else skipped += 1;
  }
  return { records, skipped };
}

function parseJsonLine(line: string): unknown {
  try {
    return JSON.parse(line);
  } catch {
    return undefined;
  }
}

async function readDocsPage(clogBin: string, file: string): Promise<string> {
  const page = path.join(await repoRootOf(clogBin), 'docs', 'api', file);
  try {
    return await fs.readFile(page, 'utf-8');
  } catch (err) {
    if (isEnoent(err)) {
      throw new HttpError(404, 'not_found', `docs/api/${file} not found`);
    }
    throw err;
  }
}

export const notFoundHandler =(c: Context): Response => {
  const body: ErrorBody = {
    error: { code: 'not_found', message: `no route for ${c.req.method} ${c.req.path}` },
  };
  return c.json(body, 404);
};

export const errorHandler = (err: Error, c: Context): Response => {
  const { status, body } = toErrorResponse(err);
  if (status === 500 && body.error.code === 'internal_error') {
    process.stderr.write(`clog serve: ${c.req.method} ${c.req.path}: ${err.message}\n`);
  }
  return c.json(body, status);
};

/**
 * The clog routes (`/health`, `/demo`, `/docs`, `/config`, `/entries`) as a
 * Hono app that can be mounted under any prefix. It is host-agnostic and
 * carries no Host allowlist, CORS or body limit: the mounting app owns those
 * (see `createApp`). Pass `token` to require bearer auth on the config and
 * entries routes; without it the router is open.
 */
export function createClogRouter(options: ClogRouterOptions = {}): Hono {
  const clogBin = path.resolve(options.clogBin ?? DEFAULT_CLOG_BIN);
  const { token } = options;
  if (token === '') throw new Error('createClogRouter: token must not be empty');
  const router = new Hono();

  const guard: MiddlewareHandler = async (c, next) => {
    if (token !== undefined && !hasBearerToken(c.req.header('authorization'), token)) {
      throw new HttpError(401, 'unauthorized', 'missing or invalid bearer token');
    }
    await next();
  };

  // `bin/clog` appends with a plain `echo >>`, which is not atomic past the pipe
  // buffer, so overlapping writes can interleave. One spawn at a time per router.
  let writes: Promise<unknown> = Promise.resolve();
  const serialised = <T>(task: () => Promise<T>): Promise<T> => {
    const result = writes.then(task);
    // The chain only waits for settlement; `result` still rejects to its caller.
    writes = result.catch(() => undefined);
    return result;
  };

  router.onError(errorHandler);
  router.notFound(notFoundHandler);

  router.get('/health', (c) => c.json({ ok: true, version: API_VERSION, clogBin }, 200));

  // Served from the repo so the pages get a real http://127.0.0.1 origin; a
  // file:// page sends `Origin: null`, which the CORS rule rejects by design.
  router.get('/demo', async (c) => c.html(await readDocsPage(clogBin, DEMO_PAGE)));
  router.get('/docs', async (c) => c.html(await readDocsPage(clogBin, REFERENCE_PAGE)));

  router.get('/config', guard, async (c) => c.json(await loadClogConfig(clogBin), 200));

  router.post('/entries', guard, async (c) => {
    const request = await parseWriteRequest(c);
    // The CLI would exit 0 without writing; there is no entry to return.
    if (process.env['CLOG_DISABLE'] === '1') {
      throw new HttpError(503, 'disabled', DISABLED_MESSAGE);
    }
    const args = [request.type, request.summary, ...request.flags, '--echo'];
    const run = await serialised(() => runClog(clogBin, args));
    // A child that printed its entry line and then failed (e.g. the auto-commit
    // step) did write the entry: report 201 with the first stderr line as a warning.
    let warning: string | undefined;
    let entry: Entry;
    if (run.exitCode !== 0) {
      const written = entryFromStdout(run.stdout);
      if (written === undefined) throw errorFromStderr(run.exitCode, run.stderr);
      entry = written;
      warning = firstLine(run.stderr);
    } else {
      if (run.stdout.trim() === '') throw new HttpError(503, 'disabled', DISABLED_MESSAGE);
      entry = parseEntryLine(run.stdout);
    }
    const config = await loadClogConfig(clogBin);
    const date = request.date ?? localDate();
    const file = path.join(readRootOf(config), logFileName(date));
    return c.json(warning === undefined ? { entry, file } : { entry, file, warning }, 201);
  });

  router.get('/entries', guard, async (c) => {
    const query = parseReadQuery(c);
    const config = await loadClogConfig(clogBin);
    const file = path.join(readRootOf(config), logFileName(query.date));

    const { records, skipped } = await readEntries(file);
    let entries = records.filter((e) => query.filters.every(([field, value]) => e[field] === value));
    if (query.tag !== undefined) entries = entries.filter((e) => hasTag(e, query.tag as string));
    if (query.tail !== undefined) entries = entries.slice(-query.tail);
    return c.json({ date: query.date, file, entries, skipped }, 200);
  });

  return router;
}

export function createApp(options: ClogRouterOptions = {}): Hono {
  const app = new Hono();

  // DNS-rebinding guard: a rebound page is same-origin to the attacker's name,
  // so CORS never applies; the Host header is what gives it away.
  app.use('*', async (c, next) => {
    const host = c.req.header('host') ?? new URL(c.req.url).host;
    if (!LOCAL_HOST_PATTERN.test(host)) {
      throw new HttpError(403, 'forbidden_host', `host '${host}' is not allowed`);
    }
    await next();
  });

  app.use(
    '*',
    cors({
      origin: (origin) => (LOCAL_ORIGIN_PATTERN.test(origin) ? origin : null),
      allowMethods: ['GET', 'POST', 'OPTIONS'],
      allowHeaders: ['Content-Type', 'Authorization'],
    }),
  );

  app.use(
    '*',
    bodyLimit({
      maxSize: MAX_BODY_BYTES,
      onError: (c) => {
        const body: ErrorBody = {
          error: {
            code: 'payload_too_large',
            message: `request body exceeds ${MAX_BODY_BYTES} bytes`,
          },
        };
        return c.json(body, 413);
      },
    }),
  );

  app.onError(errorHandler);
  app.notFound(notFoundHandler);
  app.route('/', createClogRouter(options));
  return app;
}
