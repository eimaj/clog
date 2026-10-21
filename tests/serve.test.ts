import assert from 'node:assert/strict';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import type { ChildProcess } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { after, before, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

// Child-process smoke: builds dist/, then runs the real `bin/clog serve`.

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const CLOG_BIN = path.join(REPO_ROOT, 'bin', 'clog');
const LISTENING = /^clog API listening on http:\/\/127\.0\.0\.1:(\d+)\n$/;
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
  exited: Promise<number | null>;
}

function startServer(args: string[]): Promise<Running> {
  return new Promise((resolve, reject) => {
    const child = spawn(CLOG_BIN, ['serve', ...args], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    const exited = new Promise<number | null>((done) => child.once('exit', (code) => done(code)));
    let stdout = '';
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error(`no listening line within ${STARTUP_TIMEOUT_MS}ms: ${JSON.stringify(stdout)}`));
    }, STARTUP_TIMEOUT_MS);
    child.stdout?.on('data', (chunk: Buffer) => {
      stdout += chunk.toString('utf-8');
      const match = LISTENING.exec(stdout);
      if (match?.[1] !== undefined) {
        clearTimeout(timer);
        resolve({ child, port: Number.parseInt(match[1], 10), exited });
      }
    });
    child.once('error', reject);
  });
}

async function stop(server: Running): Promise<number | null> {
  server.child.kill('SIGINT');
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

  it('writes and reads an entry through the running server', async () => {
    const server = await startServer(['--port', '0']);
    try {
      const base = `http://127.0.0.1:${server.port}`;
      const created = await fetch(`${base}/entries`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'ACTION', summary: 'smoke', repo: 'r', date: '2026-01-03' }),
      });
      assert.equal(created.status, 201);
      const listed = await fetch(`${base}/entries?date=2026-01-03`);
      const body = (await listed.json()) as { entries: Array<Record<string, unknown>> };
      assert.deepEqual(
        body.entries.map((e) => e['summary']),
        ['smoke'],
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

  it('lists serve in --help', () => {
    const result = spawnSync(CLOG_BIN, ['--help'], { env, encoding: 'utf-8' });
    assert.equal(result.status, 0);
    assert.match(result.stdout, /clog serve \[--port N\]/);
  });
});
