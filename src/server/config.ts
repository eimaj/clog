import { execFile } from 'node:child_process';
import * as fs from 'node:fs/promises';
import * as os from 'node:os';
import * as path from 'node:path';
import { HttpError, errorFromStderr, firstLine } from './errors.ts';

/**
 * Config resolution is delegated to `lib/config.sh` (env > config file >
 * default), the same code `bin/clog` runs, so the API never reimplements it.
 */

export interface ClogConfig {
  configPath: string;
  logRoot: string;
  logSubdir: string;
  families: string[];
  kpis: string[];
}

const LOAD_TIMEOUT_MS = 10_000;
const NO_CONFIG_PREFIX = 'clog: no config at';
// "$1" is the lib path, passed as an argument so no path is ever interpolated into the script.
// `env -0` NUL-separates the pairs, so a multi-line value in the parent
// environment cannot forge a `CLOG_*=` line.
const LOAD_SCRIPT = '. "$1" && load_config && env -0';
export const DISABLED_MESSAGE = 'clog: logging is disabled (CLOG_DISABLE=1)';

/** The repo root a `bin/clog` belongs to (its real location, through symlinks). */
export async function repoRootOf(clogBin: string): Promise<string> {
  const real = await fs.realpath(clogBin);
  return path.dirname(path.dirname(real));
}

const splitList = (value: string | undefined): string[] => value?.split(' ').filter(Boolean) ?? [];

function parseEnv(output: string): Map<string, string> {
  const vars = new Map<string, string>();
  for (const pair of output.split('\0')) {
    const eq = pair.indexOf('=');
    if (eq > 0) vars.set(pair.slice(0, eq), pair.slice(eq + 1));
  }
  return vars;
}

function runLoader(libConfig: string): Promise<{ stdout: string; stderr: string; failed: boolean }> {
  return new Promise((resolve, reject) => {
    execFile(
      'bash',
      ['-c', LOAD_SCRIPT, 'clog-config', libConfig],
      { encoding: 'utf-8', timeout: LOAD_TIMEOUT_MS, env: process.env },
      (error, stdout, stderr) => {
        if (error === null) {
          resolve({ stdout, stderr, failed: false });
        } else if (error.killed === true) {
          reject(new HttpError(500, 'clog_timeout', 'clog: config load timed out'));
        } else if (typeof error.code === 'number') {
          resolve({ stdout, stderr, failed: true });
        } else {
          reject(new HttpError(500, 'clog_failed', `clog: cannot run bash: ${error.message}`));
        }
      },
    );
  });
}

/** Resolve the effective config for `clogBin`; 503 when no config file exists. */
export async function loadClogConfig(clogBin: string): Promise<ClogConfig> {
  const root = await repoRootOf(clogBin);
  const result = await runLoader(path.join(root, 'lib', 'config.sh'));
  if (result.failed) {
    const line = firstLine(result.stderr);
    if (line.startsWith(NO_CONFIG_PREFIX)) throw new HttpError(503, 'no_config', line);
    throw errorFromStderr(1, result.stderr);
  }
  const vars = parseEnv(result.stdout);
  const logRoot = vars.get('CLOG_LOG_ROOT');
  const logSubdir = vars.get('CLOG_LOG_SUBDIR');
  // load_config returns early under CLOG_DISABLE=1 without resolving defaults.
  if (logRoot === undefined || logSubdir === undefined) {
    throw new HttpError(503, 'disabled', DISABLED_MESSAGE);
  }
  return {
    configPath: process.env['CLOG_CONFIG'] ?? path.join(os.homedir(), '.config', 'clog', 'config.yaml'),
    logRoot,
    logSubdir,
    families: splitList(vars.get('CLOG_FAMILIES')),
    kpis: splitList(vars.get('CLOG_KPIS')),
  };
}

export function readRootOf(config: ClogConfig): string {
  return path.join(config.logRoot, config.logSubdir);
}
