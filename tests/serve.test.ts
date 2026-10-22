import assert from 'node:assert/strict';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import type { ChildProcess } from 'node:child_process';
import * as fs from 'node:fs';
import * as net from 'node:net';
import * as os from 'node:os';
import * as path from 'node:path';
import { after, before, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

// Child-process smoke: builds dist/, then runs the real `bin/clog serve`.

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CLOG_BIN = path.join(REPO_ROOT, 'bin', 'clog');
const LISTENING = /^clog API listening on http:\/\/127\.0\.0\.1:(\d+)\nclog API token: (\S+)\n$/;
const STARTUP_TIMEOUT_MS = 15_000;

let tmp: string;
let env: NodeJS.ProcessEnv;

before(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'clog-serve-'));
  const logRoot = path.join(tmp, 'logs');
  const example = fs.readFileSync(path.join(REPO_ROOT, 'config', 'config.yaml.example'), 'utf-8');
  fs.writeFileSync(path.join(tmp, 'config.yaml'), example.replaceAll('${HOME}/clog-logs', logRoot));
  env = {
    ...process.env,
    CLOG_CONFIG: path.join(tmp, 'config.yaml'),
    CLOG_TAGS_FILE: '/nonexistent',
  };
  delete env['CLOG_DISABLE'];
  delete env['CLOG_LOG_ROOT'];
  delete env['CLOG_LOG_SUBDIR'];
  execFileSync('npm', ['run', 'build'], { cwd: REPO_ROOT, stdio: 'pipe' });
});

after(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

interface Running {
  child: ChildProcess;
  port: number;
  token: string;
  stdout: string;
  exited: Promise<number | null>;
}

const auth = (server: Running): Record<string, string> => ({ Authorization: `Bearer ${server.token}` });

function startServer(args: string[], childEnv: NodeJS.ProcessEnv = env): Promise<Running> {
  return new Promise((resolve, reject) => {
    const child = spawn(CLOG_BIN, ['serve', ...args], { env: childEnv, stdio: ['ignore', 'pipe', 'pipe'] });
    const exited = new Promise<number | null>((done) => child.once('exit', (code) => done(code)));
    let stdout = '';
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error(`no listening line within ${STARTUP_TIMEOUT_MS}ms: ${JSON.stringify(stdout)}`));
    }, STARTUP_TIMEOUT_MS);
    child.stdout?.on('data', (chunk: Buffer) => {
      stdout += chunk.toString('utf-8');
      const match = LISTENING.exec(stdout);
      if (match?.[1] !== undefined && match[2] !== undefined) {
        clearTimeout(timer);
        resolve({ child, port: Number.parseInt(match[1], 10), token: match[2], stdout, exited });
      }
    });
    child.once('error', reject);
  });
}

function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const probe = net.createServer();
    probe.once('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const address = probe.address();
      const port = typeof address === 'object' && address !== null ? address.port : 0;
      probe.close(() => resolve(port));
    });
  });
}

function nonLoopbackAddress(): string | undefined {
  return Object.values(os.networkInterfaces())
    .flat()
    .find((a) => a !== undefined && a.family === 'IPv4' && !a.internal)?.address;
}

async function stop(server: Running, signal: NodeJS.Signals = 'SIGINT'): Promise<number | null> {
  server.child.kill(signal);
  return server.exited;
}

describe('clog serve', () => {
  it('starts on a free port, answers /health and exits 0 on SIGINT', async () => {
    const server = await startServer(['--port', '0']);
    assert.ok(server.port > 0);
    const res = await fetch(`http://127.0.0.1:${server.port}/health`);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { ok: true, version: '1.0', clogBin: CLOG_BIN });
    assert.equal(await stop(server), 0);
  });

  it('listens on the port given with --port N and prints it', async () => {
    const port = await freePort();
    const server = await startServer(['--port', String(port)]);
    try {
      assert.equal(server.port, port);
      assert.match(server.stdout, new RegExp(`^clog API listening on http://127\\.0\\.0\\.1:${port}\\n`));
      assert.equal((await fetch(`http://127.0.0.1:${port}/health`)).status, 200);
    } finally {
      assert.equal(await stop(server), 0);
    }
  });

  it('binds loopback only: a non-loopback local address refuses the connection', async (t) => {
    const external = nonLoopbackAddress();
    if (external === undefined) {
      t.skip('no non-loopback IPv4 address on this machine');
      return;
    }
    const server = await startServer(['--port', '0']);
    try {
      assert.equal((await fetch(`http://127.0.0.1:${server.port}/health`)).status, 200);
      await assert.rejects(fetch(`http://${external}:${server.port}/health`), (err: unknown) => {
        const cause = err instanceof Error ? err.cause : undefined;
        return cause instanceof Error && 'code' in cause && cause.code === 'ECONNREFUSED';
      });
    } finally {
      assert.equal(await stop(server), 0);
    }
  });

  it('prints a random 32-hex token and gates config and entries on it', async () => {
    const server = await startServer(['--port', '0']);
    try {
      assert.match(server.token, /^[0-9a-f]{32}$/);
      const base = `http://127.0.0.1:${server.port}`;
      const denied = await fetch(`${base}/config`);
      assert.equal(denied.status, 401);
      assert.deepEqual(await denied.json(), {
        error: { code: 'unauthorized', message: 'missing or invalid bearer token' },
      });
      assert.equal((await fetch(`${base}/config`, { headers: auth(server) })).status, 200);
      assert.equal((await fetch(`${base}/health`)).status, 200);
    } finally {
      assert.equal(await stop(server), 0);
    }
  });

  it('uses CLOG_API_TOKEN from the environment when set', async () => {
    const server = await startServer(['--port', '0'], { ...env, CLOG_API_TOKEN: 'fixed-token-123' });
    try {
      assert.equal(server.token, 'fixed-token-123');
      const base = `http://127.0.0.1:${server.port}`;
      assert.equal((await fetch(`${base}/config`, { headers: auth(server) })).status, 200);
      assert.equal((await fetch(`${base}/config`, { headers: { Authorization: 'Bearer nope' } })).status, 401);
    } finally {
      assert.equal(await stop(server), 0);
    }
  });

  it('exits 0 on SIGTERM', async () => {
    const server = await startServer(['--port', '0']);
    assert.equal(await stop(server, 'SIGTERM'), 0);
  });

  it('starts without a config, answers /health and reports no_config', async () => {
    const noConfig = { ...env, CLOG_CONFIG: path.join(tmp, 'missing.yaml') };
    const server = await startServer(['--port', '0'], noConfig);
    try {
      const base = `http://127.0.0.1:${server.port}`;
      const health = await fetch(`${base}/health`);
      assert.equal(health.status, 200);
      const config = await fetch(`${base}/config`, { headers: auth(server) });
      assert.equal(config.status, 503);
      const body = (await config.json()) as { error: { code: string } };
      assert.equal(body.error.code, 'no_config');
    } finally {
      assert.equal(await stop(server), 0);
    }
  });

  it('writes and reads an entry through the running server', async () => {
    const server = await startServer(['--port', '0']);
    try {
      const base = `http://127.0.0.1:${server.port}`;
      const created = await fetch(`${base}/entries`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...auth(server) },
        body: JSON.stringify({ type: 'ACTION', summary: 'smoke', repo: 'r', date: '2026-01-03' }),
      });
      assert.equal(created.status, 201);
      const listed = await fetch(`${base}/entries?date=2026-01-03`, { headers: auth(server) });
      const body = (await listed.json()) as { entries: Array<Record<string, unknown>> };
      assert.deepEqual(
        body.entries.map((e) => e['summary']),
        ['smoke'],
      );
    } finally {
      assert.equal(await stop(server), 0);
    }
  });

  it('serves the demo page and the reference page as HTML', async () => {
    const server = await startServer(['--port', '0']);
    try {
      const base = `http://127.0.0.1:${server.port}`;
      const demo = await fetch(`${base}/demo`);
      assert.equal(demo.status, 200);
      assert.match(demo.headers.get('content-type') ?? '', /text\/html/);
      const demoHtml = await demo.text();
      assert.equal(demoHtml, fs.readFileSync(path.join(REPO_ROOT, 'docs', 'api', 'demo.html'), 'utf-8'));
      assert.match(demoHtml, /<title>clog API demo<\/title>/);
      // self-contained: no external script, stylesheet or asset
      assert.doesNotMatch(demoHtml, /<script[^>]*\ssrc=/i);
      assert.doesNotMatch(demoHtml, /<link\b/i);
      assert.doesNotMatch(demoHtml, /(src|href)=["']https?:/i);

      const docs = await fetch(`${base}/docs`);
      assert.equal(docs.status, 200);
      assert.match(docs.headers.get('content-type') ?? '', /text\/html/);
      assert.equal(
        await docs.text(),
        fs.readFileSync(path.join(REPO_ROOT, 'docs', 'api', 'index.html'), 'utf-8'),
      );
    } finally {
      assert.equal(await stop(server), 0);
    }
  });

  it('exits 1 with a message for a non-integer --port', () => {
    const result = spawnSync(CLOG_BIN, ['serve', '--port', 'abc'], { env, encoding: 'utf-8' });
    assert.equal(result.status, 1);
    assert.equal(result.stderr, "clog: invalid --port 'abc'\n");
    assert.equal(result.stdout, '');
  });

  it('exits 1 with a message for an out-of-range --port', () => {
    const result = spawnSync(CLOG_BIN, ['serve', '--port', '70000'], { env, encoding: 'utf-8' });
    assert.equal(result.status, 1);
    assert.equal(result.stderr, "clog: invalid --port '70000'\n");
  });

  it('prints a one-line usage for serve --help and exits 0', () => {
    const result = spawnSync(CLOG_BIN, ['serve', '--help'], { env, encoding: 'utf-8' });
    assert.equal(result.status, 0);
    assert.equal(
      result.stdout,
      'Usage: clog serve [--port N]   (default 127.0.0.1:4848; prints the API token on start)\n',
    );
  });

  it('lists serve in --help', () => {
    const result = spawnSync(CLOG_BIN, ['--help'], { env, encoding: 'utf-8' });
    assert.equal(result.status, 0);
    assert.match(result.stdout, /clog serve \[--port N\]/);
  });
});
