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
4. Add Worker runtime secrets from your local terminal:

```bash
wrangler secret put TURSO_DATABASE_URL
wrangler secret put TURSO_AUTH_TOKEN
wrangler secret put JWT_SECRET
```

5. For GitHub Actions deployment, add repository secrets in GitHub:

```text
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
```

Create them in repo Settings > Secrets and variables > Actions. The API token
must be scoped to the target Cloudflare account and have the Cloudflare
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

6. Deploy:

```bash
npm install
npm run deploy
```

7. Open the deployed Worker URL in a browser. `/` should return a JSON service
summary. `/health` should return `ok: true` after `TURSO_DATABASE_URL`,
`TURSO_AUTH_TOKEN`, and `JWT_SECRET` are configured.

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
