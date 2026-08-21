# Koinly Sync Worker

Cloudflare Worker backend for Koinly multi-device sync.

The Flutter app talks only to this Worker. Turso credentials stay in Worker
secrets and are never shipped in the app.

## API

- `POST /v1/auth/register`
- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `POST /v1/auth/logout`
- `POST /v1/sync/initial`
- `POST /v1/sync/push`
- `GET /v1/sync/pull?cursor=0&limit=100`
- `GET /v1/sync/status`

## Setup

1. Create a Turso database.
2. Apply `schema.sql`.
3. Review `wrangler.toml` and adjust the Worker name if needed.
4. Add secrets:

```bash
wrangler secret put TURSO_DATABASE_URL
wrangler secret put TURSO_AUTH_TOKEN
wrangler secret put JWT_SECRET
```

5. Deploy:

```bash
npm install
npm run deploy
```

## Sync Model

Clients write local SQLite first, enqueue entity operations in `sync_outbox`,
then push batches. The server deduplicates by `operationId`, stores current
entity state, and appends `sync_changes`. Clients pull by monotonic sequence.

Financial correctness is protected by:

- idempotent operations;
- tenant-scoped server queries;
- explicit stale-version conflicts;
- bounded batches;
- local transactional apply on the Flutter side.
