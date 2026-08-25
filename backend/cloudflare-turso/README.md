# Personal Cloudflare + Turso Sync

This Worker lets one Koinly user sync through their own Turso database without creating a Koinly account. The Flutter app sends full snapshots to the Worker; Turso credentials never enter the app.

## Deploy

1. Create a Turso database and token:

   ```bash
   turso db create koinly-sync
   turso db show koinly-sync --url
   turso db tokens create koinly-sync
   ```

2. Deploy `backend/cloudflare-turso` as a Cloudflare Worker:

   ```bash
   npm install
   npx wrangler secret put TURSO_DATABASE_URL
   npx wrangler secret put TURSO_AUTH_TOKEN
   npx wrangler secret put SYNC_SECRET
   npm run deploy
   ```

   Use a long random value for `SYNC_SECRET`. The Worker creates its table automatically on first use.

3. Open the Worker URL. A configured deployment returns:

   ```json
   {"ok":true,"service":"koinly-personal-turso-sync","loginRequired":false}
   ```

4. In Koinly, open **Settings > Account & sync > Use own Turso Worker**. Enter the Worker URL and a private Sync ID/PIN, then select **Upload Data** on the first device. Use the same values and **Sync** on another device.

## Behavior

- The Sync ID and PIN protect each snapshot; an existing Sync ID cannot be overwritten with a different PIN.
- Local edits upload automatically after the first successful upload.
- Manual **Sync** replaces local finance data with the latest cloud snapshot after a safety backup.
- Conflict handling is last-upload-wins. Download before editing from a second device.
- Never put `TURSO_AUTH_TOKEN` or `SYNC_SECRET` in the Flutter app.
