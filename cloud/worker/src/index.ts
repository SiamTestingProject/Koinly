import { createClient, type Client } from '@libsql/client/web';

type Env = {
  TURSO_DATABASE_URL: string;
  TURSO_AUTH_TOKEN: string;
  JWT_SECRET: string;
  ACCESS_TOKEN_TTL_SECONDS?: string;
  REFRESH_TOKEN_TTL_SECONDS?: string;
  MAX_SYNC_BATCH_SIZE?: string;
};

type AuthContext = {
  userId: string;
  email: string;
  deviceId: string;
};

type SyncOperation = {
  operationId: string;
  entityType: string;
  entityId: string;
  operation: 'upsert' | 'delete';
  payload?: unknown;
  baseVersion?: number;
  clientUpdatedAt?: number;
};

const enc = new TextEncoder();

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const db = createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN });

    try {
      if (request.method === 'OPTIONS') return cors(new Response(null, { status: 204 }));
      if (request.method === 'GET' && url.pathname === '/health') return json({ ok: true, service: 'koinly-sync' });

      if (request.method === 'POST' && url.pathname === '/v1/auth/register') return register(request, env, db);
      if (request.method === 'POST' && url.pathname === '/v1/auth/login') return login(request, env, db);
      if (request.method === 'POST' && url.pathname === '/v1/auth/refresh') return refresh(request, env, db);

      const auth = await requireAuth(request, env);
      if (request.method === 'POST' && url.pathname === '/v1/auth/logout') return logout(request, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/sync/initial') return initialSync(request, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/sync/push') return push(request, env, db, auth);
      if (request.method === 'GET' && url.pathname === '/v1/sync/pull') return pull(url, env, db, auth);
      if (request.method === 'GET' && url.pathname === '/v1/sync/status') return status(db, auth);

      return json({ error: 'Not found.' }, 404);
    } catch (error) {
      const statusCode = error instanceof HttpError ? error.status : 500;
      const message = error instanceof Error ? error.message : 'Internal error.';
      return json({ error: message }, statusCode);
    } finally {
      db.close();
    }
  },
};

async function register(request: Request, env: Env, db: Client): Promise<Response> {
  const body = await readJson(request);
  const email = normalizeEmail(body.email);
  const password = String(body.password ?? '');
  const deviceId = normalizeId(body.deviceId, 'deviceId');
  const deviceName = cleanText(body.deviceName, 80) || 'Koinly device';
  const platform = cleanText(body.platform, 40) || 'unknown';
  validatePassword(password);

  const now = Date.now();
  const userId = crypto.randomUUID();
  const passwordHash = await hashPassword(password);
  try {
    await db.batch([
      {
        sql: 'INSERT INTO users(id, email, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        args: [userId, email, passwordHash, now, now],
      },
      {
        sql: 'INSERT INTO devices(id, user_id, name, platform, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)',
        args: [deviceId, userId, deviceName, platform, now, now],
      },
    ], 'write');
  } catch {
    throw new HttpError(409, 'An account already exists for this email.');
  }
  return issueTokens(env, db, { userId, email, deviceId });
}

async function login(request: Request, env: Env, db: Client): Promise<Response> {
  const body = await readJson(request);
  const email = normalizeEmail(body.email);
  const password = String(body.password ?? '');
  const deviceId = normalizeId(body.deviceId, 'deviceId');
  const deviceName = cleanText(body.deviceName, 80) || 'Koinly device';
  const platform = cleanText(body.platform, 40) || 'unknown';

  const row = (await db.execute({ sql: 'SELECT id, email, password_hash FROM users WHERE email = ?', args: [email] })).rows[0];
  if (!row || !(await verifyPassword(password, String(row.password_hash)))) {
    throw new HttpError(401, 'Invalid email or password.');
  }

  const now = Date.now();
  await db.execute({
    sql: `INSERT INTO devices(id, user_id, name, platform, created_at, last_seen_at)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(user_id, id) DO UPDATE SET name = excluded.name, platform = excluded.platform, last_seen_at = excluded.last_seen_at, revoked_at = NULL`,
    args: [deviceId, String(row.id), deviceName, platform, now, now],
  });
  return issueTokens(env, db, { userId: String(row.id), email: String(row.email), deviceId });
}

async function refresh(request: Request, env: Env, db: Client): Promise<Response> {
  const body = await readJson(request);
  const refreshToken = String(body.refreshToken ?? '');
  const deviceId = normalizeId(body.deviceId, 'deviceId');
  if (!refreshToken) throw new HttpError(401, 'Missing refresh token.');

  const tokenHash = await sha256(refreshToken);
  const row = (await db.execute({
    sql: `SELECT rt.id, rt.user_id, u.email
          FROM refresh_tokens rt
          JOIN users u ON u.id = rt.user_id
          WHERE rt.token_hash = ? AND rt.device_id = ? AND rt.revoked_at IS NULL AND rt.expires_at > ?`,
    args: [tokenHash, deviceId, Date.now()],
  })).rows[0];
  if (!row) throw new HttpError(401, 'Refresh token is invalid or expired.');

  await db.execute({ sql: 'UPDATE refresh_tokens SET revoked_at = ?, rotated_at = ? WHERE id = ?', args: [Date.now(), Date.now(), String(row.id)] });
  return issueTokens(env, db, { userId: String(row.user_id), email: String(row.email), deviceId });
}

async function logout(request: Request, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const refreshToken = String(body.refreshToken ?? '');
  if (refreshToken) {
    await db.execute({
      sql: 'UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND token_hash = ?',
      args: [Date.now(), auth.userId, await sha256(refreshToken)],
    });
  }
  return json({ ok: true });
}

async function initialSync(request: Request, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const adoptLocal = Boolean(body.adoptLocal);
  if (adoptLocal && Array.isArray(body.operations)) {
    return pushWithOperations(db, auth, body.operations, 1000);
  }
  return pull(new URL('https://koinly.local/v1/sync/pull?cursor=0&limit=250'), { MAX_SYNC_BATCH_SIZE: '250' } as Env, db, auth);
}

async function push(request: Request, env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  return pushWithOperations(db, auth, body.operations, numberEnv(env.MAX_SYNC_BATCH_SIZE, 100));
}

async function pushWithOperations(db: Client, auth: AuthContext, rawOperations: unknown, maxBatch: number): Promise<Response> {
  if (!Array.isArray(rawOperations)) throw new HttpError(400, 'operations must be an array.');
  if (rawOperations.length > maxBatch) throw new HttpError(413, `Batch limit is ${maxBatch} operations.`);

  const accepted: Array<{ operationId: string; sequence: number; version: number }> = [];
  const conflicts: Array<{ operationId: string; entityType: string; entityId: string; serverVersion: number }> = [];

  for (const raw of rawOperations) {
    const op = validateOperation(raw);
    const processed = (await db.execute({
      sql: 'SELECT sequence FROM processed_operations WHERE user_id = ? AND operation_id = ?',
      args: [auth.userId, op.operationId],
    })).rows[0];
    if (processed) {
      accepted.push({ operationId: op.operationId, sequence: Number(processed.sequence), version: op.baseVersion ?? 0 });
      continue;
    }

    const existing = (await db.execute({
      sql: 'SELECT version FROM sync_entities WHERE user_id = ? AND entity_type = ? AND entity_id = ?',
      args: [auth.userId, op.entityType, op.entityId],
    })).rows[0];
    const serverVersion = existing ? Number(existing.version) : 0;
    const baseVersion = op.baseVersion ?? 0;
    if (serverVersion > baseVersion) {
      conflicts.push({ operationId: op.operationId, entityType: op.entityType, entityId: op.entityId, serverVersion });
      continue;
    }

    const version = serverVersion + 1;
    const now = Date.now();
    const payloadJson = op.operation === 'delete' ? null : JSON.stringify(op.payload ?? {});
    await db.batch([
      {
        sql: `INSERT INTO sync_entities(user_id, entity_type, entity_id, version, payload_json, deleted_at, updated_at, last_operation_id)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(user_id, entity_type, entity_id) DO UPDATE SET
                version = excluded.version,
                payload_json = excluded.payload_json,
                deleted_at = excluded.deleted_at,
                updated_at = excluded.updated_at,
                last_operation_id = excluded.last_operation_id`,
        args: [auth.userId, op.entityType, op.entityId, version, payloadJson ?? '{}', op.operation === 'delete' ? now : null, now, op.operationId],
      },
      {
        sql: `INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, version, payload_json, device_id, operation_id, changed_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        args: [auth.userId, op.entityType, op.entityId, op.operation, version, payloadJson, auth.deviceId, op.operationId, now],
      },
    ], 'write');

    const sequenceRow = (await db.execute({
      sql: 'SELECT sequence FROM sync_changes WHERE user_id = ? AND operation_id = ?',
      args: [auth.userId, op.operationId],
    })).rows[0];
    const sequence = Number(sequenceRow?.sequence ?? 0);
    await db.execute({
      sql: 'INSERT INTO processed_operations(user_id, operation_id, sequence, created_at) VALUES (?, ?, ?, ?)',
      args: [auth.userId, op.operationId, sequence, now],
    });
    accepted.push({ operationId: op.operationId, sequence, version });
  }

  return json({ ok: true, accepted, conflicts });
}

async function pull(url: URL, env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const cursor = Math.max(0, Number(url.searchParams.get('cursor') ?? '0') || 0);
  const limit = Math.min(Math.max(1, Number(url.searchParams.get('limit') ?? '100') || 100), numberEnv(env.MAX_SYNC_BATCH_SIZE, 100));
  const rows = (await db.execute({
    sql: `SELECT sequence, entity_type, entity_id, operation, version, payload_json, device_id, operation_id, changed_at
          FROM sync_changes
          WHERE user_id = ? AND sequence > ?
          ORDER BY sequence
          LIMIT ?`,
    args: [auth.userId, cursor, limit + 1],
  })).rows;
  const page = rows.slice(0, limit);
  const nextCursor = page.length ? Number(page[page.length - 1].sequence) : cursor;
  return json({
    cursor: nextCursor,
    hasMore: rows.length > limit,
    changes: page.map(row => ({
      sequence: Number(row.sequence),
      entityType: String(row.entity_type),
      entityId: String(row.entity_id),
      operation: String(row.operation),
      version: Number(row.version),
      payload: row.payload_json ? JSON.parse(String(row.payload_json)) : null,
      deviceId: String(row.device_id),
      operationId: String(row.operation_id),
      changedAt: Number(row.changed_at),
    })),
  });
}

async function status(db: Client, auth: AuthContext): Promise<Response> {
  await db.execute({ sql: 'UPDATE devices SET last_seen_at = ? WHERE user_id = ? AND id = ?', args: [Date.now(), auth.userId, auth.deviceId] });
  const row = (await db.execute({ sql: 'SELECT COALESCE(MAX(sequence), 0) AS sequence FROM sync_changes WHERE user_id = ?', args: [auth.userId] })).rows[0];
  return json({ ok: true, serverCursor: Number(row?.sequence ?? 0), userId: auth.userId, deviceId: auth.deviceId });
}

async function issueTokens(env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const now = Date.now();
  const accessExpiresAt = now + numberEnv(env.ACCESS_TOKEN_TTL_SECONDS, 900) * 1000;
  const refreshExpiresAt = now + numberEnv(env.REFRESH_TOKEN_TTL_SECONDS, 2592000) * 1000;
  const accessToken = await signToken(env.JWT_SECRET, { sub: auth.userId, email: auth.email, deviceId: auth.deviceId, exp: Math.floor(accessExpiresAt / 1000) });
  const refreshToken = crypto.randomUUID() + '.' + crypto.randomUUID();
  await db.execute({
    sql: 'INSERT INTO refresh_tokens(id, user_id, token_hash, device_id, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    args: [crypto.randomUUID(), auth.userId, await sha256(refreshToken), auth.deviceId, refreshExpiresAt, now],
  });
  return json({ accessToken, refreshToken, accessExpiresAt, refreshExpiresAt, user: { id: auth.userId, email: auth.email }, deviceId: auth.deviceId });
}

async function requireAuth(request: Request, env: Env): Promise<AuthContext> {
  const header = request.headers.get('authorization') ?? '';
  const token = header.toLowerCase().startsWith('bearer ') ? header.slice(7) : '';
  if (!token) throw new HttpError(401, 'Missing access token.');
  const payload = await verifyToken(env.JWT_SECRET, token);
  return { userId: String(payload.sub), email: String(payload.email), deviceId: String(payload.deviceId) };
}

async function signToken(secret: string, payload: Record<string, unknown>): Promise<string> {
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify(payload));
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(`${header}.${body}`));
  return `${header}.${body}.${b64urlBytes(sig)}`;
}

async function verifyToken(secret: string, token: string): Promise<Record<string, unknown>> {
  const parts = token.split('.');
  if (parts.length !== 3) throw new HttpError(401, 'Invalid access token.');
  const expected = await signDetached(secret, `${parts[0]}.${parts[1]}`);
  if (expected !== parts[2]) throw new HttpError(401, 'Invalid access token signature.');
  const payload = JSON.parse(atobUrl(parts[1])) as Record<string, unknown>;
  if (Number(payload.exp ?? 0) < Math.floor(Date.now() / 1000)) throw new HttpError(401, 'Access token expired.');
  return payload;
}

async function signDetached(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return b64urlBytes(await crypto.subtle.sign('HMAC', key, enc.encode(value)));
}

async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: 210000 }, key, 256);
  return `pbkdf2$210000$${b64urlBytes(salt)}$${b64urlBytes(bits)}`;
}

async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [scheme, iterationsRaw, saltRaw, hashRaw] = stored.split('$');
  if (scheme !== 'pbkdf2') return false;
  const salt = bytesFromB64Url(saltRaw);
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: Number(iterationsRaw) }, key, 256);
  return b64urlBytes(bits) === hashRaw;
}

async function sha256(value: string): Promise<string> {
  return b64urlBytes(await crypto.subtle.digest('SHA-256', enc.encode(value)));
}

function validateOperation(raw: unknown): SyncOperation {
  const value = raw as Record<string, unknown>;
  const operation = String(value.operation ?? '');
  if (operation !== 'upsert' && operation !== 'delete') throw new HttpError(400, 'Invalid operation.');
  return {
    operationId: normalizeId(value.operationId, 'operationId'),
    entityType: normalizeEntityType(value.entityType),
    entityId: normalizeId(value.entityId, 'entityId'),
    operation,
    payload: value.payload,
    baseVersion: Number(value.baseVersion ?? 0),
    clientUpdatedAt: Number(value.clientUpdatedAt ?? Date.now()),
  };
}

function normalizeEmail(value: unknown): string {
  const email = String(value ?? '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new HttpError(400, 'Enter a valid email address.');
  return email;
}

function validatePassword(password: string): void {
  if (password.length < 8) throw new HttpError(400, 'Password must be at least 8 characters.');
}

function normalizeEntityType(value: unknown): string {
  const entityType = String(value ?? '').trim();
  if (!/^[a-z_]{2,64}$/.test(entityType)) throw new HttpError(400, 'Invalid entity type.');
  return entityType;
}

function normalizeId(value: unknown, label: string): string {
  const id = String(value ?? '').trim();
  if (!/^[A-Za-z0-9._:-]{3,120}$/.test(id)) throw new HttpError(400, `Invalid ${label}.`);
  return id;
}

function cleanText(value: unknown, max: number): string {
  return String(value ?? '').trim().slice(0, max);
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    return await request.json() as Record<string, unknown>;
  } catch {
    throw new HttpError(400, 'Invalid JSON body.');
  }
}

function numberEnv(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function b64url(value: string): string {
  return b64urlBytes(enc.encode(value));
}

function b64urlBytes(value: ArrayBuffer | Uint8Array): string {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  let raw = '';
  for (const byte of bytes) raw += String.fromCharCode(byte);
  return btoa(raw).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function bytesFromB64Url(value: string): Uint8Array<ArrayBuffer> {
  const raw = atobUrl(value);
  const bytes = new Uint8Array(new ArrayBuffer(raw.length));
  for (let i = 0; i < raw.length; i += 1) {
    bytes[i] = raw.charCodeAt(i);
  }
  return bytes;
}

function atobUrl(value: string): string {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=');
  return atob(padded);
}

function json(value: unknown, status = 200): Response {
  return cors(new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  }));
}

function cors(response: Response): Response {
  response.headers.set('access-control-allow-origin', '*');
  response.headers.set('access-control-allow-methods', 'GET,POST,OPTIONS');
  response.headers.set('access-control-allow-headers', 'authorization,content-type');
  return response;
}

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}
