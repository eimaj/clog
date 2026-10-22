/**
 * Maps failures to the HTTP API's single error shape, `{ error: { code, message } }`.
 * `bin/clog` owns the rules; where it rejects an entry its first stderr line is
 * kept verbatim as `message` and only the status and code are derived here.
 */

export type ErrorStatus = 400 | 401 | 403 | 404 | 413 | 415 | 500 | 503;

export type ErrorCode =
  | 'invalid_json'
  | 'invalid_type'
  | 'missing_summary'
  | 'invalid_field'
  | 'invalid_date'
  | 'invalid_tail'
  | 'invalid_tag'
  | 'no_config'
  | 'disabled'
  | 'clog_failed'
  | 'clog_timeout'
  | 'payload_too_large'
  | 'unsupported_media_type'
  | 'forbidden_host'
  | 'unauthorized'
  | 'not_found'
  | 'internal_error';

export interface ErrorBody {
  error: { code: ErrorCode; message: string };
}

export interface ErrorResponse {
  status: ErrorStatus;
  body: ErrorBody;
}

export class HttpError extends Error {
  readonly status: ErrorStatus;
  readonly code: ErrorCode;

  constructor(status: ErrorStatus, code: ErrorCode, message: string) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.code = code;
  }
}

interface StderrRule {
  prefix: string;
  status: ErrorStatus;
  code: ErrorCode;
}

// Must mirror the first stderr line of `bin/clog`; `tests/server.test.ts` pins each prefix.
const STDERR_RULES: readonly StderrRule[] = [
  { prefix: 'clog: unknown type', status: 400, code: 'invalid_type' },
  { prefix: 'clog: invalid --date', status: 400, code: 'invalid_date' },
  { prefix: 'clog: missing summary', status: 400, code: 'missing_summary' },
  { prefix: 'clog: no config at', status: 503, code: 'no_config' },
];

export function firstLine(text: string): string {
  return text.split('\n')[0]?.trim() ?? '';
}

/** Error for a non-zero exit of `bin/clog`, keyed on the first stderr line. */
export function errorFromStderr(exitCode: number, stderr: string): HttpError {
  const line = firstLine(stderr);
  const rule = STDERR_RULES.find((r) => line.startsWith(r.prefix));
  if (rule !== undefined) return new HttpError(rule.status, rule.code, line);
  return new HttpError(500, 'clog_failed', line === '' ? `clog exited with code ${exitCode}` : line);
}

/** Never leaks a stack or an unexpected error's text; the caller logs the cause. */
export function toErrorResponse(err: unknown): ErrorResponse {
  if (err instanceof HttpError) {
    return { status: err.status, body: { error: { code: err.code, message: err.message } } };
  }
  return {
    status: 500,
    body: { error: { code: 'internal_error', message: 'internal server error' } },
  };
}
