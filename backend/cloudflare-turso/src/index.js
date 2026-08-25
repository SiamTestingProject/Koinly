import { createClient } from '@libsql/client/web';

const headers = {
  'content-type': 'application/json; charset=utf-8',
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,POST,OPTIONS',
  'access-control-allow-headers': 'content-type',
};

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { headers });
    const url = new URL(request.url);

    try {
      if (request.method === 'GET' && url.pathname === '/') {
        const configured = Boolean(env.TURSO_DATABASE_URL && env.TURSO_AUTH_TOKEN && env.SYNC_SECRET);
        return json({ ok: configured, service: 'koinly-personal-turso-sync', loginRequired: false }, configured ? 200 : 503);
      }
      if (request.method === 'POST' && url.pathname === '/api/sync/push') return await push(request, env);
      if (request.method === 'POST' && url.pathname === '/api/sync/pull') return await pull(request, env);
      return json({ error: 'Not found.' }, 404);
    } catch (error) {
      return json({ error: error?.message || 'Server error.' }, error?.status || 500);
    }
  },
};

async function push(request, env) {
  const body = await readJson(request);
  const syncId = normalizeSyncId(body.syncId);
  const pin = String(body.pin || '').trim();
  validate(syncId, pin);
  if (!body.payload || typeof body.payload !== 'object' || Array.isArray(body.payload)) {
    throw new HttpError(400, 'Missing sync payload.');
  }

  const payloadJson = JSON.stringify(body.payload);
  const payloadBytes = new TextEncoder().encode(payloadJson).length;
  if (payloadBytes > 4_500_000) throw new HttpError(413, 'Sync payload is too large.');

  const database = await openDatabase(env);
  const pinHash = await hashPin(env, syncId, pin);
  await requireMatchingPin(database, syncId, pinHash);
  const now = new Date().toISOString();
  await database.execute({
    sql: `INSERT INTO sync_snapshots(sync_id, pin_hash, payload_json, payload_bytes, device_id, client_updated_at, created_at, updated_at)
          VALUES(?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(sync_id) DO UPDATE SET
            payload_json = excluded.payload_json,
            payload_bytes = excluded.payload_bytes,
            device_id = excluded.device_id,
            client_updated_at = excluded.client_updated_at,
            updated_at = excluded.updated_at`,
    args: [
      syncId,
      pinHash,
      payloadJson,
      payloadBytes,
      String(body.deviceId || '').slice(0, 120),
      String(body.clientUpdatedAt || '').slice(0, 80),
      now,
      now,
    ],
  });
  return json({ ok: true, syncId, updatedAt: now, payloadBytes });
}

async function pull(request, env) {
  const body = await readJson(request);
  const syncId = normalizeSyncId(body.syncId);
  const pin = String(body.pin || '').trim();
  validate(syncId, pin);

  const database = await openDatabase(env);
  const result = await database.execute({
    sql: 'SELECT pin_hash, payload_json, updated_at, payload_bytes FROM sync_snapshots WHERE sync_id = ?',
    args: [syncId],
  });
  if (!result.rows.length) throw new HttpError(404, 'No cloud data found for this Sync ID.');

  const row = result.rows[0];
  if (row.pin_hash !== await hashPin(env, syncId, pin)) throw new HttpError(401, 'Wrong Sync PIN.');
  return json({
    ok: true,
    syncId,
    updatedAt: row.updated_at,
    payloadBytes: row.payload_bytes,
    payload: JSON.parse(row.payload_json),
  });
}

async function openDatabase(env) {
  if (!env.TURSO_DATABASE_URL || !env.TURSO_AUTH_TOKEN || !env.SYNC_SECRET) {
    throw new HttpError(503, 'Missing TURSO_DATABASE_URL, TURSO_AUTH_TOKEN, or SYNC_SECRET.');
  }
  const database = createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN });
  await database.execute(`
    CREATE TABLE IF NOT EXISTS sync_snapshots (
      sync_id TEXT PRIMARY KEY,
      pin_hash TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      payload_bytes INTEGER NOT NULL DEFAULT 0,
      device_id TEXT NOT NULL DEFAULT '',
      client_updated_at TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
    )
  `);
  return database;
}

async function requireMatchingPin(database, syncId, pinHash) {
  const result = await database.execute({ sql: 'SELECT pin_hash FROM sync_snapshots WHERE sync_id = ?', args: [syncId] });
  if (result.rows.length && result.rows[0].pin_hash !== pinHash) throw new HttpError(401, 'Wrong Sync PIN.');
}

function validate(syncId, pin) {
  if (syncId.length < 3) throw new HttpError(400, 'Sync ID must contain at least 3 letters or numbers.');
  if (pin.length < 4) throw new HttpError(400, 'Sync PIN must be at least 4 characters.');
}

async function hashPin(env, syncId, pin) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${env.SYNC_SECRET}::${syncId}::${pin}`));
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, '0')).join('');
}

function normalizeSyncId(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_.-]/g, '-')
    .replace(/-+/g, '-')
    .slice(0, 80);
}

async function readJson(request) {
  try {
    return await request.json();
  } catch (_) {
    throw new HttpError(400, 'Invalid JSON body.');
  }
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers });
}

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
