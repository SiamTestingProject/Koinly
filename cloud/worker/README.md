# Koinly Sync Worker

Cloudflare Worker backend for Koinly multi-device sync.

The Flutter app talks only to this Worker. Turso credentials stay in Worker
secrets and are never shipped in the app.

## API

- `GET /`
- `GET /health`
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
4. Add deployment secrets in GitHub repo Settings > Secrets and variables >
   Actions:

```text
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
```

The workflow uploads `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN`, and
`JWT_SECRET` to Cloudflare as Worker secrets during deploy, so you do not need
to add them twice when deploying through GitHub Actions.

If you deploy from your local terminal instead of GitHub Actions, add Worker
runtime secrets manually:

```bash
wrangler secret put TURSO_DATABASE_URL
wrangler secret put TURSO_AUTH_TOKEN
wrangler secret put JWT_SECRET
```

The Cloudflare API token must be scoped to the target Cloudflare account and have the Cloudflare
`Edit Cloudflare Workers` token template permissions. If you create it
manually, include at minimum:

```text
Account  > Workers Scripts   > Edit/Write
Account  > Account Settings  > Read
User     > User Details      > Read
User     > Memberships       > Read
```

If you attach the Worker to routes or a custom domain, also include:

```text
Zone     > Workers Routes    > Edit/Write
```

After changing the token in Cloudflare, replace the existing GitHub
`CLOUDFLARE_API_TOKEN` secret with the new token value.

5. Deploy:

```bash
npm install
npm run schema:apply
npm run deploy
```

The GitHub Actions workflow also runs `npm run schema:apply` before deploying.
The schema file is idempotent, so it is safe to run on every deploy and will not
erase existing sync data.

6. Open the deployed Worker URL in a browser. `/` should return a JSON service
summary. `/health` should return `ok: true`, `databaseReachable: true`, and
`schemaReady: true` after `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN`, and
`JWT_SECRET` are configured.

The Worker also runs the idempotent schema bootstrap before auth/sync requests,
so missing tables are created automatically if the GitHub Actions schema step
was skipped.

If Cloudflare shows error `1101`, check Worker logs. Most setup-time crashes
are caused by missing Worker secrets, invalid Turso credentials, or not applying
`schema.sql` to the Turso database.

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
