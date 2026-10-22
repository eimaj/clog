import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { after, afterEach, before, beforeEach, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { Hono } from 'hono';
import { createApp, createClogRouter } from '../src/server/app.ts';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CLOG_BIN = path.join(REPO_ROOT, 'bin', 'clog');
const TYPES = [
  'DECISION',
  'ACTION',
  'CODE',
  'PR',
  'COMMIT',
  'REPO',
  'FOLLOWUP',
  'LEARNING',
  'LESSON',
];
const ENV_KEYS = [
  'CLOG_CONFIG',
  'CLOG_TAGS_FILE',
  'CLOG_DISABLE',
  'CLOG_LOG_ROOT',
  'CLOG_LOG_SUBDIR',
  'CLOG_REPORTS_ROOT',
  'CLOG_FAMILIES',
  'CLOG_KPIS',
  'CLOG_AGENTS',
  'CLOG_AUTO_COMMIT_ENABLED',
  'CLOG_AUTO_COMMIT_REPO',
];

interface ErrorBody {
  error: { code: string; message: string };
}

interface Written {
  entry: Record<string, unknown>;
  file: string;
}

interface Listed {
  date: string;
  file: string;
  entries: Array<Record<string, unknown>>;
  skipped: number;
}

let tmp: string;
let logRoot: string;
let readRoot: string;
let configPath: string;
let app: Hono;
const savedEnv = new Map<string, string | undefined>();

function writeScratchConfig(): void {
  const example = fs.readFileSync(path.join(REPO_ROOT, 'config', 'config.yaml.example'), 'utf-8');
  fs.writeFileSync(configPath, example.replaceAll('${HOME}/clog-logs', logRoot), 'utf-8');
}

before(() => {
  for (const key of ENV_KEYS) savedEnv.set(key, process.env[key]);
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'clog-server-'));
  logRoot = path.join(tmp, 'logs');
  readRoot = path.join(logRoot, 'claude');
  configPath = path.join(tmp, 'config.yaml');
  writeScratchConfig();
  app = createApp();
});

after(() => {
  for (const [key, value] of savedEnv) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  fs.rmSync(tmp, { recursive: true, force: true });
});

beforeEach(() => {
  for (const key of ENV_KEYS) delete process.env[key];
  process.env['CLOG_CONFIG'] = configPath;
  process.env['CLOG_TAGS_FILE'] = '/nonexistent';
});

afterEach(() => {
  fs.rmSync(logRoot, { recursive: true, force: true });
});

function send(
  target: Hono,
  method: string,
  route: string,
  body?: unknown,
  headers: Record<string, string> = {},
): Promise<Response> {
  const init: RequestInit = { method, headers };
  if (body !== undefined) {
    init.body = typeof body === 'string' ? body : JSON.stringify(body);
    init.headers = { 'Content-Type': 'application/json', ...headers };
  }
  return Promise.resolve(target.request(route, init));
}

function request(
  method: string,
  route: string,
  body?: unknown,
  headers: Record<string, string> = {},
): Promise<Response> {
  return send(app, method, route, body, headers);
}

async function expectError(res: Response, status: number, code: string): Promise<ErrorBody> {
  assert.equal(res.status, status);
  const text = await res.text();
  assert.doesNotMatch(text, /\bat \S+ \(|\\n\s+at /, 'error body must not carry a stack trace');
  const body = JSON.parse(text) as ErrorBody;
  assert.equal(body.error.code, code);
  assert.equal(typeof body.error.message, 'string');
  return body;
}

function post(body: unknown): Promise<Response> {
  return request('POST', '/entries', body);
}

function lastLine(file: string): string {
  const lines = fs.readFileSync(file, 'utf-8').trimEnd().split('\n');
  return lines[lines.length - 1] ?? '';
}

function withoutTime(line: string): string {
  return line.replace(/"time":"[0-9:]{8}"/, '"time":"T"');
}

function seed(date: string, lines: string[]): string {
  fs.mkdirSync(readRoot, { recursive: true });
  const file = path.join(readRoot, `${date.replaceAll('-', '')}.jsonl`);
  fs.writeFileSync(file, lines.join('\n') + '\n', 'utf-8');
  return file;
}

function localDay(): string {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${now.getFullYear()}-${month}-${day}`;
}

const line = (fields: Record<string, string>): string =>
  JSON.stringify({ time: '10:00:00', summary: 's', ...fields });

describe('GET /health', () => {
  it('reports ok, the API version and the clog binary in use', async () => {
    const res = await request('GET', '/health');
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { ok: true, version: '1.0', clogBin: CLOG_BIN });
  });
});

describe('static pages', () => {
  it('serves docs/api/demo.html at /demo and docs/api/index.html at /docs', async () => {
    for (const [route, file] of [
      ['/demo', 'demo.html'],
      ['/docs', 'index.html'],
    ] as const) {
      const res = await request('GET', route);
      assert.equal(res.status, 200);
      assert.match(res.headers.get('content-type') ?? '', /text\/html/);
      assert.equal(await res.text(), fs.readFileSync(path.join(REPO_ROOT, 'docs', 'api', file), 'utf-8'));
    }
  });

  it('demo page carries the port field, write form, filtered list and error panel', () => {
    const html = fs.readFileSync(path.join(REPO_ROOT, 'docs', 'api', 'demo.html'), 'utf-8');
    for (const id of ['port', 'token', 'type', 'summary', 'repo', 'family', 'kpi', 'f-type', 'f-tail', 'entries', 'error-body']) {
      assert.match(html, new RegExp(`id="${id}"`), `missing #${id}`);
    }
    assert.match(html, /POST/);
    assert.match(html, /\/entries/);
  });

  it('demo page script is syntactically valid', () => {
    const html = fs.readFileSync(path.join(REPO_ROOT, 'docs', 'api', 'demo.html'), 'utf-8');
    const script = /<script>([\s\S]*?)<\/script>/.exec(html)?.[1];
    assert.ok(script, 'inline script present');
    // Compiles without running it; throws SyntaxError on a typo.
    assert.doesNotThrow(() => new Function(script));
  });
});

describe('GET /config', () => {
  it('returns the values resolved from the scratch config', async () => {
    const res = await request('GET', '/config');
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), {
      configPath,
      logRoot,
      logSubdir: 'claude',
      families: ['general', 'skills', 'tooling', 'interactive'],
      kpis: ['token_waste', 'failure', 'prompt_gap', 'effective', 'format_issue'],
    });
  });

  it('honours env overrides the way the CLI does', async () => {
    process.env['CLOG_FAMILIES'] = 'one two';
    const body = (await (await request('GET', '/config')).json()) as { families: string[] };
    assert.deepEqual(body.families, ['one', 'two']);
  });

  it('answers 503 no_config when the config file is missing', async () => {
    process.env['CLOG_CONFIG'] = path.join(tmp, 'missing.yaml');
    const body = await expectError(await request('GET', '/config'), 503, 'no_config');
    assert.match(body.error.message, /^clog: no config at /);
  });

  it('is not changed by a multi-line parent env var that mimics a CLOG_ line', async () => {
    process.env['CLOG_TEST_HIJACK'] = 'x\nCLOG_LOG_SUBDIR=hijacked\nCLOG_FAMILIES=evil';
    try {
      const body = (await (await request('GET', '/config')).json()) as { logSubdir: string; families: string[] };
      assert.equal(body.logSubdir, 'claude');
      assert.deepEqual(body.families, ['general', 'skills', 'tooling', 'interactive']);
    } finally {
      delete process.env['CLOG_TEST_HIJACK'];
    }
  });

  it('answers 503 disabled under CLOG_DISABLE=1', async () => {
    process.env['CLOG_DISABLE'] = '1';
    await expectError(await request('GET', '/config'), 503, 'disabled');
  });

  it('answers 500 internal_error without a stack when the binary is absent', async () => {
    const res = await send(createApp({ clogBin: path.join(tmp, 'absent') }), 'GET', '/config');
    const body = await expectError(res, 500, 'internal_error');
    assert.equal(body.error.message, 'internal server error');
  });
});

describe('POST /entries', () => {
  for (const type of TYPES) {
    it(`writes ${type} byte-for-byte like bin/clog (ignoring time)`, async () => {
      const args = ['hello world', '--agent', 'a', '--repo', 'r', '--session', 's1', '--model', 'm'];
      const res = await post({
        type,
        summary: 'hello world',
        agent: 'a',
        repo: 'r',
        session: 's1',
        model: 'm',
        date: '2026-01-03',
      });
      assert.equal(res.status, 201);
      const written = (await res.json()) as Written;
      assert.equal(written.file, path.join(readRoot, '20260103.jsonl'));

      execFileSync(CLOG_BIN, [type, ...args, '--date', '2026-01-04'], { env: process.env });
      const cliLine = lastLine(path.join(readRoot, '20260104.jsonl'));
      const apiLine = lastLine(written.file);
      assert.equal(withoutTime(apiLine), withoutTime(cliLine));
      assert.deepEqual(written.entry, JSON.parse(apiLine));
    });
  }

  it('carries every optional field through to the entry', async () => {
    const res = await post({
      type: 'LEARNING',
      summary: 'all fields',
      agent: 'a',
      repo: 'r',
      session: 's',
      model: 'm',
      file: 'f.ts',
      family: 'general',
      kpi: 'failure',
      date: '2026-01-05',
    });
    assert.equal(res.status, 201);
    const { entry } = (await res.json()) as Written;
    assert.deepEqual(
      { ...entry, time: 'T' },
      {
        time: 'T',
        type: 'LEARNING',
        summary: 'all fields',
        agent: 'a',
        repo: 'r',
        session: 's',
        model: 'm',
        file: 'f.ts',
        family: 'general',
        kpi: 'failure',
        clog_version: '1.0',
      },
    );
  });

  it('defaults the reported file to today in local time', async () => {
    const res = await post({ type: 'ACTION', summary: 'today', repo: 'r' });
    assert.equal(res.status, 201);
    const { file } = (await res.json()) as Written;
    assert.equal(file, path.join(readRoot, `${localDay().replaceAll('-', '')}.jsonl`));
    assert.ok(fs.existsSync(file));
  });

  it('treats an empty date like an omitted one and writes to today', async () => {
    const res = await post({ type: 'ACTION', summary: 'today', repo: 'r', date: '' });
    assert.equal(res.status, 201);
    const { file } = (await res.json()) as Written;
    assert.equal(file, path.join(readRoot, `${localDay().replaceAll('-', '')}.jsonl`));
    assert.ok(fs.existsSync(file));
  });

  it('still answers 201 and carries validation for an unknown family', async () => {
    const res = await post({ type: 'LEARNING', summary: 'x', family: 'nope', date: '2026-01-03' });
    assert.equal(res.status, 201);
    const { entry } = (await res.json()) as Written;
    assert.equal(entry['validation'], 'unknown_family');
  });

  it('keeps a summary that looks like a flag as a plain summary', async () => {
    const res = await post({ type: 'ACTION', summary: '--help', repo: 'r', date: '2026-01-03' });
    assert.equal(res.status, 201);
    const { entry } = (await res.json()) as Written;
    assert.equal(entry['summary'], '--help');
  });

  const rejected: Array<[string, unknown, string, string]> = [
    ['unknown type', { type: 'NOPE', summary: 'x' }, 'invalid_type', "clog: unknown type 'NOPE'"],
    ['lowercase type', { type: 'action', summary: 'x' }, 'invalid_type', "clog: unknown type 'action'"],
    ['missing type', { summary: 'x' }, 'invalid_type', "clog: unknown type ''"],
    ['non-string type', { type: 7, summary: 'x' }, 'invalid_type', "clog: unknown type '7'"],
    ['help in the type position', { type: '--help', summary: 'x' }, 'invalid_type', "clog: unknown type '--help'"],
    ['missing summary', { type: 'ACTION' }, 'missing_summary', 'clog: missing summary'],
    ['empty summary', { type: 'ACTION', summary: '' }, 'missing_summary', 'clog: missing summary'],
    ['non-string summary', { type: 'ACTION', summary: 5 }, 'missing_summary', 'clog: missing summary'],
    ['non-string field', { type: 'ACTION', summary: 'x', repo: 5 }, 'invalid_field', "field 'repo' must be a string"],
    ['null field', { type: 'ACTION', summary: 'x', kpi: null }, 'invalid_field', "field 'kpi' must be a string"],
    ['NUL in the summary', { type: 'ACTION', summary: 'a\u0000b' }, 'invalid_field', "field 'summary' must not contain NUL"],
    ['NUL in an optional field', { type: 'ACTION', summary: 'x', repo: 'r\u0000' }, 'invalid_field', "field 'repo' must not contain NUL"],
    ['bad date text', { type: 'ACTION', summary: 'x', date: 'notadate' }, 'invalid_date', "clog: invalid --date 'notadate' (expected YYYY-MM-DD)"],
    ['compact date', { type: 'ACTION', summary: 'x', date: '20260103' }, 'invalid_date', "clog: invalid --date '20260103' (expected YYYY-MM-DD)"],
    ['traversal date', { type: 'ACTION', summary: 'x', date: '../../evil' }, 'invalid_date', "clog: invalid --date '../../evil' (expected YYYY-MM-DD)"],
  ];
  for (const [name, body, code, message] of rejected) {
    it(`rejects ${name} with 400 ${code}`, async () => {
      const res = await post(body);
      const err = await expectError(res, 400, code);
      assert.ok(err.error.message.startsWith(message), err.error.message);
    });
  }

  it('writes nothing outside the read root for a traversal date', async () => {
    fs.mkdirSync(readRoot, { recursive: true });
    const before = fs.readdirSync(tmp).sort();
    await post({ type: 'ACTION', summary: 'x', date: '../../evil' });
    assert.deepEqual(fs.readdirSync(tmp).sort(), before);
    assert.equal(fs.existsSync(path.join(tmp, 'evil.jsonl')), false);
    assert.deepEqual(fs.readdirSync(readRoot), []);
  });

  it('rejects a body that is not JSON with 400 invalid_json', async () => {
    await expectError(await post('{not json'), 400, 'invalid_json');
  });

  it('rejects a cross-origin text/plain POST with 415 and writes nothing', async () => {
    const res = await request(
      'POST',
      '/entries',
      JSON.stringify({ type: 'ACTION', summary: 'forged', date: '2026-01-03' }),
      { 'Content-Type': 'text/plain', Origin: 'https://evil.example' },
    );
    await expectError(res, 415, 'unsupported_media_type');
    assert.equal(fs.existsSync(readRoot), false);
  });

  it('rejects a POST with no content type with 415 and writes nothing', async () => {
    const res = await app.request('/entries', {
      method: 'POST',
      body: JSON.stringify({ type: 'ACTION', summary: 'forged', date: '2026-01-03' }),
    });
    await expectError(res, 415, 'unsupported_media_type');
    assert.equal(fs.existsSync(readRoot), false);
  });

  it('accepts application/json with parameters', async () => {
    const res = await request(
      'POST',
      '/entries',
      { type: 'ACTION', summary: 'ok', date: '2026-01-03' },
      { 'Content-Type': 'application/json; charset=utf-8' },
    );
    assert.equal(res.status, 201);
  });

  it('accepts a body of exactly 64 KiB and rejects one byte more', async () => {
    const sized = (bytes: number): string => {
      const base = JSON.stringify({ type: 'ACTION', summary: '', date: '2026-01-03' });
      return JSON.stringify({
        type: 'ACTION',
        summary: 'x'.repeat(bytes - Buffer.byteLength(base)),
        date: '2026-01-03',
      });
    };
    const exact = sized(65536);
    assert.equal(Buffer.byteLength(exact), 65536);
    assert.equal((await post(exact)).status, 201);
    const over = sized(65537);
    assert.equal(Buffer.byteLength(over), 65537);
    await expectError(await post(over), 413, 'payload_too_large');
  });

  it('rejects a body over 64 KiB with 413 payload_too_large', async () => {
    const res = await post({ type: 'ACTION', summary: 'x'.repeat(65 * 1024) });
    await expectError(res, 413, 'payload_too_large');
  });

  it('serialises parallel large writes so the day file stays line-parseable', async () => {
    const summary = 'x'.repeat(20 * 1024);
    const responses = await Promise.all(
      Array.from({ length: 20 }, (_, i) =>
        post({ type: 'ACTION', summary: `${i}:${summary}`, repo: 'r', date: '2026-01-03' }),
      ),
    );
    assert.deepEqual(
      responses.map((r) => r.status),
      Array.from({ length: 20 }, () => 201),
    );
    const listed = (await (await request('GET', '/entries?date=2026-01-03')).json()) as Listed;
    assert.equal(listed.skipped, 0);
    assert.equal(listed.entries.length, 20);
  });

  it('answers 503 disabled without spawning when CLOG_DISABLE=1', async () => {
    process.env['CLOG_DISABLE'] = '1';
    await expectError(await post({ type: 'ACTION', summary: 'x', date: '2026-01-03' }), 503, 'disabled');
    assert.equal(fs.existsSync(readRoot), false);
  });

  it('answers 503 no_config with the CLI message when there is no config', async () => {
    process.env['CLOG_CONFIG'] = path.join(tmp, 'missing.yaml');
    const err = await expectError(await post({ type: 'ACTION', summary: 'x' }), 503, 'no_config');
    assert.match(err.error.message, /^clog: no config at /);
  });

  describe('child failures', () => {
    // A throwaway repo layout (bin/clog plus a lib symlink) so the config
    // loader, which resolves lib/config.sh from the binary's location, works.
    function fakeClog(name: string, script: string): Hono {
      const root = path.join(tmp, name);
      fs.mkdirSync(path.join(root, 'bin'), { recursive: true });
      fs.symlinkSync(path.join(REPO_ROOT, 'lib'), path.join(root, 'lib'));
      const bin = path.join(root, 'bin', 'clog');
      fs.writeFileSync(bin, `#!/usr/bin/env bash\n${script}\n`, { mode: 0o755 });
      return createApp({ clogBin: bin });
    }

    it('spawns one bin/clog at a time', async () => {
      const lock = path.join(tmp, 'lock');
      const fake = fakeClog(
        'fake-lock',
        `if ! mkdir "${lock}" 2>/dev/null; then echo "overlap" >&2; exit 2; fi
sleep 0.05
echo '{"time":"T","type":"ACTION","summary":"s"}'
rmdir "${lock}"`,
      );
      const responses = await Promise.all(
        Array.from({ length: 8 }, () => send(fake, 'POST', '/entries', { type: 'ACTION', summary: 'x' })),
      );
      assert.deepEqual(
        responses.map((r) => r.status),
        Array.from({ length: 8 }, () => 201),
      );
    });

    it('answers 201 with a warning when the child printed the entry and then exited non-zero', async () => {
      const res = await send(
        fakeClog('fake-warn', `echo '{"time":"T","type":"ACTION","summary":"x"}'; echo "git: commit failed" >&2; echo more >&2; exit 2`),
        'POST',
        '/entries',
        { type: 'ACTION', summary: 'x', date: '2026-01-03' },
      );
      assert.equal(res.status, 201);
      const body = (await res.json()) as Written & { warning: string };
      assert.deepEqual(body.entry, { time: 'T', type: 'ACTION', summary: 'x' });
      assert.equal(body.file, path.join(readRoot, '20260103.jsonl'));
      assert.equal(body.warning, 'git: commit failed');
    });

    it('still maps a non-zero exit with two stdout lines to 500 clog_failed', async () => {
      const res = await send(fakeClog('fake-two', `echo '{"a":1}'; echo '{"b":2}'; exit 2`), 'POST', '/entries', {
        type: 'ACTION',
        summary: 'x',
      });
      await expectError(res, 500, 'clog_failed');
    });

    it('maps exit 127 to 500 clog_failed', async () => {
      const res = await send(fakeClog('fake-127', 'echo "boom" >&2; exit 127'), 'POST', '/entries', {
        type: 'ACTION',
        summary: 'x',
      });
      const err = await expectError(res, 500, 'clog_failed');
      assert.equal(err.error.message, 'boom');
    });

    it('maps any other non-zero exit to 500 clog_failed', async () => {
      const res = await send(fakeClog('fake-2', 'exit 2'), 'POST', '/entries', {
        type: 'ACTION',
        summary: 'x',
      });
      await expectError(res, 500, 'clog_failed');
    });

    it('maps exit 0 with unparseable stdout to 500 clog_failed', async () => {
      const res = await send(fakeClog('fake-junk', 'echo not-json'), 'POST', '/entries', {
        type: 'ACTION',
        summary: 'x',
      });
      await expectError(res, 500, 'clog_failed');
    });

    it('maps exit 0 with empty stdout to 503 disabled', async () => {
      const res = await send(fakeClog('fake-empty', 'exit 0'), 'POST', '/entries', {
        type: 'ACTION',
        summary: 'x',
      });
      await expectError(res, 503, 'disabled');
    });

    it('maps a missing binary to 500 clog_failed', async () => {
      const res = await send(createApp({ clogBin: path.join(tmp, 'absent') }), 'POST', '/entries', {
        type: 'ACTION',
        summary: 'x',
      });
      await expectError(res, 500, 'clog_failed');
    });
  });
});

describe('GET /entries', () => {
  const today = localDay();

  function list(query = ''): Promise<Response> {
    return request('GET', `/entries${query}`);
  }

  beforeEach(() => {
    seed(today, [
      line({ type: 'ACTION', repo: 'a', session: 's1', agent: 'x', summary: 'one' }),
      line({ type: 'CODE', repo: 'b', session: 's1', agent: 'y', summary: 'two' }),
      line({ type: 'ACTION', repo: 'a', session: 's2', agent: 'x', summary: 'three' }),
      line({ type: 'ACTION', repo: 'a', session: 's1', agent: 'y', summary: 'four' }),
    ]);
    seed('2026-02-09', [line({ type: 'PR', summary: 'yesterday' })]);
  });

  it('defaults to today and reports the file', async () => {
    const body = (await (await list()).json()) as Listed;
    assert.equal(body.date, today);
    assert.equal(body.file, path.join(readRoot, `${today.replaceAll('-', '')}.jsonl`));
    assert.equal(body.entries.length, 4);
    assert.equal(body.skipped, 0);
  });

  it('selects another day with date', async () => {
    const body = (await (await list('?date=2026-02-09')).json()) as Listed;
    assert.deepEqual(
      body.entries.map((e) => e['summary']),
      ['yesterday'],
    );
  });

  for (const [field, value, expected] of [
    ['type', 'CODE', ['two']],
    ['repo', 'a', ['one', 'three', 'four']],
    ['session', 's2', ['three']],
    ['agent', 'y', ['two', 'four']],
  ] as const) {
    it(`filters exactly on ${field}`, async () => {
      const body = (await (await list(`?${field}=${value}`)).json()) as Listed;
      assert.deepEqual(
        body.entries.map((e) => e['summary']),
        expected,
      );
    });
  }

  it('does not treat a filter as a prefix match', async () => {
    const body = (await (await list('?repo=')).json()) as Listed;
    assert.deepEqual(body.entries, []);
  });

  it('ANDs filters together', async () => {
    const body = (await (await list('?type=ACTION&session=s1&agent=y')).json()) as Listed;
    assert.deepEqual(
      body.entries.map((e) => e['summary']),
      ['four'],
    );
  });

  it('keeps the last N after filtering with tail', async () => {
    const body = (await (await list('?repo=a&tail=2')).json()) as Listed;
    assert.deepEqual(
      body.entries.map((e) => e['summary']),
      ['three', 'four'],
    );
  });

  it('returns an empty list for a day with no file', async () => {
    const body = (await (await list('?date=2026-01-01')).json()) as Listed;
    assert.deepEqual(body.entries, []);
    assert.equal(body.skipped, 0);
  });

  it('skips and counts corrupt lines', async () => {
    seed('2026-03-01', [line({ type: 'ACTION', summary: 'ok' }), '{broken', '"a string"', '', line({ type: 'CODE', summary: 'ok2' })]);
    const body = (await (await list('?date=2026-03-01')).json()) as Listed;
    assert.equal(body.entries.length, 2);
    assert.equal(body.skipped, 2);
  });

  it('reads the file fresh on every request', async () => {
    await list();
    fs.appendFileSync(path.join(readRoot, `${today.replaceAll('-', '')}.jsonl`),line({ type: 'LESSON', summary: 'late' }) + '\n');
    const body = (await (await list('?type=LESSON')).json()) as Listed;
    assert.equal(body.entries.length, 1);
  });

  const invalid: Array<[string, string, string]> = [
    ['date=notadate', 'invalid_date', "clog: invalid --date 'notadate' (expected YYYY-MM-DD)"],
    ['date=20260210', 'invalid_date', "clog: invalid --date '20260210'"],
    ['date=2026-13-01', 'invalid_date', "clog: invalid --date '2026-13-01'"],
    ['date=../../evil', 'invalid_date', "clog: invalid --date '../../evil'"],
    ['type=nope', 'invalid_type', "clog: unknown type 'nope'"],
    ['type=action', 'invalid_type', "clog: unknown type 'action'"],
    ['tail=0', 'invalid_tail', 'tail must be'],
    ['tail=-1', 'invalid_tail', 'tail must be'],
    ['tail=abc', 'invalid_tail', 'tail must be'],
    ['tail=1.5', 'invalid_tail', 'tail must be'],
    ['tail=10001', 'invalid_tail', 'tail must be'],
  ];
  for (const [query, code, message] of invalid) {
    it(`rejects ${query} with 400 ${code}`, async () => {
      const err = await expectError(await list(`?${query}`), 400, code);
      assert.ok(err.error.message.startsWith(message), err.error.message);
    });
  }

  it('accepts the tail bounds 1 and 10000', async () => {
    assert.equal((await list('?tail=1')).status, 200);
    assert.equal((await list('?tail=10000')).status, 200);
  });

  it('answers 503 no_config when there is no config', async () => {
    process.env['CLOG_CONFIG'] = path.join(tmp, 'missing.yaml');
    await expectError(await list(), 503, 'no_config');
  });

  it('answers 503 disabled under CLOG_DISABLE=1', async () => {
    process.env['CLOG_DISABLE'] = '1';
    await expectError(await list(), 503, 'disabled');
  });
});

describe('CORS', () => {
  const allowed = ['http://localhost:5173', 'http://127.0.0.1:4747', 'http://localhost'];
  for (const origin of allowed) {
    it(`echoes ${origin}`, async () => {
      const res = await request('GET', '/health', undefined, { Origin: origin });
      assert.equal(res.headers.get('access-control-allow-origin'), origin);
    });
  }

  it('answers a preflight with exactly 204 and the allowed methods', async () => {
    const res = await request('OPTIONS', '/entries', undefined, {
      Origin: 'http://localhost:5173',
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers': 'Content-Type',
    });
    assert.equal(res.status, 204);
    assert.equal(res.headers.get('access-control-allow-origin'), 'http://localhost:5173');
    const methods = (res.headers.get('access-control-allow-methods') ?? '').split(',').map((m) => m.trim());
    assert.deepEqual(methods.sort(), ['GET', 'OPTIONS', 'POST']);
    assert.match(res.headers.get('access-control-allow-headers') ?? '', /Content-Type/i);
  });

  for (const origin of ['https://example.com', 'http://localhost.evil.com', 'null']) {
    it(`sends no allow header for ${origin}`, async () => {
      const res = await request('GET', '/health', undefined, { Origin: origin });
      assert.equal(res.headers.get('access-control-allow-origin'), null);
    });
  }
});

describe('bearer token', () => {
  const token = 'a'.repeat(32);
  const secured = createApp({ token });
  const bearer = (value: string): Record<string, string> => ({ Authorization: `Bearer ${value}` });
  const routes: Array<[string, string, unknown]> = [
    ['GET', '/config', undefined],
    ['GET', '/entries', undefined],
    ['POST', '/entries', { type: 'ACTION', summary: 'x', date: '2026-01-03' }],
  ];

  for (const [method, route, body] of routes) {
    const headersFor: Array<[string, Record<string, string>]> = [
      ['no header', {}],
      ['a wrong token of the same length', bearer('b'.repeat(32))],
      ['a wrong token of another length', bearer('short')],
      ['the wrong scheme', { Authorization: `Basic ${token}` }],
      ['an empty bearer', { Authorization: 'Bearer ' }],
    ];
    for (const [name, headers] of headersFor) {
      it(`${method} ${route} answers 401 unauthorized with ${name}`, async () => {
        const err = await expectError(await send(secured, method, route, body, headers), 401, 'unauthorized');
        assert.equal(err.error.message, 'missing or invalid bearer token');
        assert.equal(fs.existsSync(readRoot), false, 'nothing written');
      });
    }

    it(`${method} ${route} passes with the right token`, async () => {
      const res = await send(secured, method, route, body, bearer(token));
      assert.equal(res.status, method === 'POST' ? 201 : 200);
    });
  }

  it('checks the token before parsing the body', async () => {
    const res = await send(secured, 'POST', '/entries', '{not json');
    await expectError(res, 401, 'unauthorized');
  });

  for (const route of ['/health', '/demo', '/docs']) {
    it(`serves ${route} without a token`, async () => {
      assert.equal((await send(secured, 'GET', route)).status, 200);
    });
  }

  it('answers a CORS preflight with 204 and no token, and allows the Authorization header', async () => {
    const res = await send(secured, 'OPTIONS', '/entries', undefined, {
      Origin: 'http://localhost:5173',
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers': 'Authorization, Content-Type',
    });
    assert.equal(res.status, 204);
    assert.match(res.headers.get('access-control-allow-headers') ?? '', /Authorization/i);
  });

  it('protects a bare router mounted with a token', async () => {
    const host = new Hono();
    host.route('/clog', createClogRouter({ token }));
    await expectError(await send(host, 'GET', '/clog/entries'), 401, 'unauthorized');
    assert.equal((await send(host, 'GET', '/clog/entries', undefined, bearer(token))).status, 200);
  });

  it('leaves the router open without a token option', async () => {
    assert.equal((await send(createClogRouter(), 'GET', '/config')).status, 200);
  });

  it('refuses an empty token at construction', () => {
    assert.throws(() => createClogRouter({ token: '' }), /token must not be empty/);
  });
});

describe('Host allowlist', () => {
  for (const host of ['127.0.0.1', '127.0.0.1:4848', 'localhost', 'localhost:4848', 'LOCALHOST:9']) {
    it(`serves Host ${host}`, async () => {
      const res = await request('GET', '/health', undefined, { Host: host });
      assert.equal(res.status, 200);
    });
  }

  for (const host of ['attacker.example:4848', 'localhost.evil.com', '127.0.0.1.evil.com:4848', '[::1]:4848']) {
    it(`rejects Host ${host} with 403 forbidden_host`, async () => {
      const res = await request('GET', '/health', undefined, { Host: host });
      await expectError(res, 403, 'forbidden_host');
    });
  }

  it('rejects a foreign Host before CORS and before writing', async () => {
    const res = await request(
      'POST',
      '/entries',
      { type: 'ACTION', summary: 'rebind', date: '2026-01-03' },
      { Host: 'attacker.example:4848', Origin: 'http://localhost:5173' },
    );
    await expectError(res, 403, 'forbidden_host');
    assert.equal(res.headers.get('access-control-allow-origin'), null);
    assert.equal(fs.existsSync(readRoot), false);
  });

  it('leaves the bare router host-agnostic', async () => {
    const res = await send(createClogRouter(), 'GET', '/health', undefined, {
      Host: 'attacker.example:4848',
    });
    assert.equal(res.status, 200);
  });
});

describe('errors and mounting', () => {
  it('answers an unknown route with a 404 in the error shape', async () => {
    const err = await expectError(await request('GET', '/nope'), 404, 'not_found');
    assert.equal(err.error.message, 'no route for GET /nope');
  });

  it('answers a wrong method on a known path with a 404 in the error shape', async () => {
    const err = await expectError(await request('DELETE', '/entries'), 404, 'not_found');
    assert.equal(err.error.message, 'no route for DELETE /entries');
  });

  it('works when the router is mounted under a prefix', async () => {
    const host = new Hono();
    host.route('/clog', createClogRouter());
    const health = await send(host, 'GET', '/clog/health');
    assert.equal(health.status, 200);
    assert.equal(((await health.json()) as { ok: boolean }).ok, true);
    const config = await send(host, 'GET', '/clog/config');
    assert.equal(config.status, 200);
    assert.equal((await send(host, 'GET', '/health')).status, 404);
  });
});

describe('tags', () => {
  it('merges body tags after the default tags, trimmed and deduplicated, like bin/clog', async () => {
    process.env['CLOG_DEFAULT_TAGS'] = 'jbook';
    try {
      const res = await post({ type: 'ACTION', summary: 'tags', tags: ['release', ' jbook ', 'web', 'release'], date: '2026-01-05' });
      assert.equal(res.status, 201);
      const written = (await res.json()) as Written;
      assert.deepEqual(written.entry['tags'], ['jbook', 'release', 'web']);

      execFileSync(CLOG_BIN, ['ACTION', 'tags', '--tags', 'release, jbook ,web,release', '--date', '2026-01-06'], { env: process.env });
      const cliLine = lastLine(path.join(readRoot, '20260106.jsonl'));
      assert.equal(withoutTime(lastLine(written.file)), withoutTime(cliLine));
    } finally {
      delete process.env['CLOG_DEFAULT_TAGS'];
    }
  });

  it('writes only the body tags when no defaults are configured', async () => {
    const res = await post({ type: 'ACTION', summary: 'tags only', tags: ['a', 'b'], date: '2026-01-05' });
    assert.equal(res.status, 201);
    assert.deepEqual(((await res.json()) as Written).entry['tags'], ['a', 'b']);
  });

  for (const [name, tags] of [
    ['a string', 'release'],
    ['an empty array', []],
    ['a blank item', ['a', ' ']],
    ['a comma inside an item', ['a,b']],
    ['a non-string item', ['a', 1]],
    ['NUL inside an item', ['a\u0000']],
  ] as const) {
    it(`rejects ${name} with 400 invalid_field`, async () => {
      const res = await post({ type: 'ACTION', summary: 'x', tags, date: '2026-01-05' });
      await expectError(res, 400, 'invalid_field');
    });
  }

  it('filters GET /entries by tag and rejects an empty tag', async () => {
    await post({ type: 'ACTION', summary: 'tagged', tags: ['release'], date: '2026-01-07' });
    await post({ type: 'ACTION', summary: 'untagged', date: '2026-01-07' });
    const hit = (await (await request('GET', '/entries?date=2026-01-07&tag=release')).json()) as Listed;
    assert.deepEqual(hit.entries.map((e) => e['summary']), ['tagged']);
    const miss = (await (await request('GET', '/entries?date=2026-01-07&tag=nope')).json()) as Listed;
    assert.deepEqual(miss.entries, []);
    await expectError(await request('GET', '/entries?date=2026-01-07&tag='), 400, 'invalid_tag');
  });
});
