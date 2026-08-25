import worker from './src/index.js';
import assert from 'node:assert/strict';

const env = { TURSO_DATABASE_URL: 'libsql://example.turso.io', TURSO_AUTH_TOKEN: 'test', SYNC_SECRET: 'test-secret' };
const root = await worker.fetch(new Request('https://worker.example/'), env);
assert.equal(root.status, 200);
assert.equal((await root.json()).loginRequired, false);

const invalid = await worker.fetch(new Request('https://worker.example/api/sync/push', {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ syncId: 'x', pin: '12' }),
}), env);
assert.equal(invalid.status, 400);

console.log('personal Turso Worker checks passed');
