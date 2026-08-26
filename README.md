# Koinly

Local-first personal finance tracking for Android and Windows, built with
Flutter and Material 3.

![Koinly banner](assets/images/koinly-banner.png)

Koinly stores finance data in SQLite on the device and works without an
account or internet connection. Online account sync is optional. Users can use
the app's default sync service or connect the app to their own Cloudflare
Worker and Turso database.

## Highlights

- Accounts and balances
- Income, expense, and transfer transactions
- Custom categories
- Monthly budgets and progress tracking
- Filters, analysis, and charts
- Savings suggestions and planning
- CSV and PDF export
- Encrypted `.koinlybackup` backup and restore
- Daily reminder notifications
- Automatic update checks
- Light, dark, and system themes
- Local-first SQLite storage
- Optional multi-device account sync
- Optional self-hosted Cloudflare Worker and Turso backend

## Supported platforms

| Platform | Status |
| --- | --- |
| Android | Supported |
| Windows | Supported |

The source also contains platform-aware code for other Flutter targets, but
the maintained release workflows build Android and Windows artifacts.

## How data is stored

Normal app changes are written to local SQLite first. The UI does not wait for
the network. When online account sync is enabled, changes are added to a local
outbox and synchronized in the background.

```text
Koinly app -> local SQLite -> Cloudflare Worker -> Turso
```

The app never receives or stores the Turso database token. It communicates
only with the selected Worker endpoint.

## Getting started

### Requirements

- Flutter SDK compatible with Dart `>=3.5.0 <4.0.0`
- Android Studio and Java 17 for Android builds
- Visual Studio with Desktop development with C++ for Windows builds
- Node.js 22 for Worker development

### Run the app

```bash
flutter pub get
flutter run
```

Choose a target explicitly when more than one device is available:

```bash
flutter run -d android
flutter run -d windows
```

### Run checks

```bash
flutter analyze
flutter test
```

Worker checks:

```bash
cd cloud/worker
npm ci
npm run typecheck
```

## Build configuration

The default cloud sync endpoint is compiled into the app with a Dart define:

```bash
--dart-define=KOINLY_SYNC_API_BASE_URL=https://your-default-worker.example.workers.dev
```

The app version can also be supplied at build time:

```bash
--dart-define=KOINLY_APP_VERSION=1.0.71
```

A missing default endpoint does not prevent local-only use or the runtime
self-hosted option. It only makes the **Default** sync choice unavailable.

### Android

```bash
flutter build apk --release \
  --dart-define=KOINLY_SYNC_API_BASE_URL=https://your-worker.example.workers.dev
```

Android release signing uses environment variables or GitHub Actions secrets:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

Never commit a keystore or its passwords.

### Windows

```bash
flutter build windows --release \
  --dart-define=KOINLY_SYNC_API_BASE_URL=https://your-worker.example.workers.dev
```

Windows signing is optional. The release workflow recognizes:

```text
WINDOWS_CODESIGN_PFX_BASE64
WINDOWS_CODESIGN_PASSWORD
WINDOWS_CODESIGN_TIMESTAMP_URL
```

## GitHub release workflow

`.github/workflows/build-android-apks.yml` builds Android APKs/AAB and a
Windows installer. It can run manually or on pushes to `main` and `master`.

The workflow expects `KOINLY_SYNC_API_BASE_URL` as a repository secret or
variable and requires the Android signing secrets listed above. Successful
builds publish versioned release artifacts.

## Online account sync

Open **Settings > Account & sync** to choose a service and sign in.

### Default cloud sync

Select **Default** to use the endpoint compiled into the app with
`KOINLY_SYNC_API_BASE_URL`. Existing users who do not configure self-hosting
continue using this service normally.

### Self-hosted cloud sync

Select **Self-hosted**, paste a Worker URL, and press **Validate and use
Worker**. The app accepts the endpoint only when:

- the URL is an HTTPS origin without a path, query, or fragment;
- `/health` identifies the service as `koinly-sync`;
- all required Worker secrets are configured;
- the Turso database is reachable; and
- the Turso schema is ready.

After validation, authentication, refresh, logout, upload, download, manual
sync, and automatic foreground sync all use the custom endpoint.

Changing services signs out the current backend session because the default
and self-hosted services have independent users and tokens. Switching does not
delete local finance data. Signing in can replace local finance data with the
selected account's cloud copy, so read the confirmation shown by the app.

## Self-hosted deployment

The supported deployment path is:

```text
Fork repository
  -> add GitHub Actions secrets
  -> deploy Cloudflare Worker
  -> connect Worker to Turso
  -> copy workers.dev URL
  -> validate URL in Koinly
```

### 1. Fork the repository

Fork this repository into your GitHub account. Open the fork's **Actions** tab
and enable workflows if GitHub displays that prompt.

### 2. Create a Turso database

Install and authenticate the [Turso CLI](https://docs.turso.tech/cli/introduction),
then create a database:

```bash
turso db create koinly-sync
```

Get its URL:

```bash
turso db show koinly-sync --url
```

Create a full-access database token:

```bash
turso db tokens create koinly-sync
```

Save the two returned values. They become `TURSO_DATABASE_URL` and
`TURSO_AUTH_TOKEN`. The Worker needs write access, so a read-only token will
not work.

The deployment workflow automatically applies `cloud/worker/schema.sql`. The
schema is idempotent: redeploying creates missing tables and indexes without
deleting existing sync data.

### 3. Create Cloudflare credentials

Follow Cloudflare's [GitHub Actions deployment guide](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/)
to obtain:

- a Cloudflare account ID; and
- an account-scoped API token created from the **Edit Cloudflare Workers**
  template.

Keep the token limited to the account that will host the Worker. Custom
domains or Worker routes may require additional route permissions, but they
are not needed for the standard `workers.dev` deployment.

### 4. Choose the Worker name

Choose a unique name:

```ini
CLOUDFLARE_NAME=my-koinly-sync
```

For `workers.dev`, the name must:

- contain 1-63 lowercase letters, numbers, or dashes;
- not start with a dash; and
- not end with a dash.

The workflow passes this value to `wrangler deploy --name`; it is not tied to
the fallback name in `wrangler.toml`.

Cloudflare Worker URLs include the account subdomain:

```text
https://my-koinly-sync.<account-subdomain>.workers.dev
```

See Cloudflare's [workers.dev documentation](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)
for naming and routing details.

### 5. Add GitHub Actions secrets

In the fork, open:

**Settings > Secrets and variables > Actions > New repository secret**

Add all of the following:

| Secret | Purpose |
| --- | --- |
| `CLOUDFLARE_NAME` | Name assigned to the deployed Worker |
| `CLOUDFLARE_API_TOKEN` | Deploys and inspects the Worker |
| `CLOUDFLARE_ACCOUNT_ID` | Selects the Cloudflare account |
| `TURSO_DATABASE_URL` | Connects the Worker to Turso |
| `TURSO_AUTH_TOKEN` | Authorizes Turso reads and writes |
| `JWT_SECRET` | Signs sessions and protects password material |

`JWT_SECRET` must contain at least 32 characters. Generate a random value with
a password manager or, where OpenSSL is available:

```bash
openssl rand -hex 32
```

Self-hosted deployment does **not** use `REGISTRATION_ADMIN_SECRET`,
`REGISTRATION_KEY_CHAT_ID`, or `TELEGRAM_BOT_TOKEN`. Those values belong to
the managed default service's invite-key system and should not be added to a
user deployment.

`CLOUDFLARE_NAME` is not sensitive. The workflow accepts it from a repository
variable as well, but storing it with the deployment secrets keeps setup to one
checklist.

Do not store any real credential in source files, workflow YAML, `.env.example`,
issues, or logs.

### 6. Deploy

Open:

**Actions > Deploy Sync Worker > Run workflow**

The workflow:

1. checks that required configuration exists;
2. validates the Worker name and JWT secret length;
3. installs locked Node dependencies;
4. tests and typechecks the Worker;
5. applies the Turso schema;
6. uploads runtime credentials as Cloudflare Worker secrets;
7. deploys using `CLOUDFLARE_NAME`;
8. derives the exact `workers.dev` URL from Cloudflare;
9. validates `/health`.

The job fails with a specific message when configuration, Cloudflare
authentication, Turso access, schema setup, or Worker health fails.

### 7. Find and verify the Worker URL

After a successful run, the exact endpoint appears in the workflow log and job
summary under **Worker URL**.

Open the health endpoint:

```text
https://<worker-name>.<account-subdomain>.workers.dev/health
```

A ready backend returns fields equivalent to:

```json
{
  "service": "koinly-sync",
  "configured": true,
  "registrationMode": "first-user",
  "databaseReachable": true,
  "schemaReady": true,
  "ok": true
}
```

### 8. Connect the app

1. Open **Settings**.
2. Open **Account & sync**.
3. Select **Self-hosted**.
4. Paste the Worker URL without `/health` or another path.
5. Press **Validate and use Worker**.
6. On the first device, choose **Create account** and enter an email and
   password. No registration key is required.
7. On every additional device, choose **Login** and use that same account.

For safety, a self-hosted Worker accepts only its first account registration.
After the owner account exists, registration closes and other devices must
sign in. This prevents an unknown person from creating an account on a public
`workers.dev` endpoint.

## Updating or redeploying the Worker

The deployment workflow runs automatically when changes are pushed to:

```text
cloud/worker/**
.github/workflows/deploy-sync-worker.yml
```

It can also be run manually at any time.

- Keep the same `CLOUDFLARE_NAME` to update the existing Worker.
- Keep the same Turso database to retain existing cloud accounts and data.
- Rotate a secret in GitHub, then rerun the workflow to upload it to
  Cloudflare.
- If the Worker name changes, copy and validate the new URL on every device.
- If the Turso database changes, users must use accounts that exist in the new
  database.

Changing `JWT_SECRET` invalidates active sessions. Rotate it only when that
impact is intended, then sign in again on each device.

## Local Worker development

The active backend is in `cloud/worker/`.

Install dependencies and typecheck:

```bash
cd cloud/worker
npm ci
npm run typecheck
```

Create local runtime values from `.env.example` without committing the real
file. Apply the schema:

```bash
npm run schema:apply
```

Run locally:

```bash
npm run dev
```

Deploy manually after configuring Wrangler authentication and Worker secrets:

```bash
npx wrangler deploy --name my-koinly-sync
```

GitHub Actions remains the recommended path because it applies the schema,
uploads secrets, validates health, and reports the final URL in one run.

## Sync behavior

- Local edits are committed before network synchronization.
- Pending operations are retained in the local outbox until accepted.
- Operations use stable IDs for server-side deduplication.
- Entity versions detect stale updates and record conflicts.
- Clients pull remote changes with a monotonic cursor.
- Signed-in devices perform quiet foreground synchronization and sync again
  when the app resumes.
- **Upload local changes** pushes the current outbox and checks remote changes.
- **Restore cloud copy** creates a safety backup, then replaces local finance
  data with the selected cloud account.
- Restoring a local backup can upload that restored copy as the authoritative
  cloud state after confirmation.

## Backup and restore

Koinly backup files use the `.koinlybackup` extension. A backup contains local
finance data and preferences. Loading a backup replaces the current local
dataset.

When a sync account is signed in, restored data can be uploaded as the new
cloud source of truth. If no account is signed in, the data stays local until
sync is configured.

Keep independent copies of important backups. Cloud synchronization is not a
substitute for a user-controlled backup.

## Troubleshooting

### The app rejects a custom Worker URL

- Use `https://`.
- Paste only the origin; remove `/health`, paths, queries, and fragments.
- Open `<Worker URL>/health` in a browser.
- Confirm `service`, `configured`, `databaseReachable`, `schemaReady`, and `ok`
  match the ready response above.
- Check device DNS, TLS inspection, firewall, and internet access.

### A GitHub secret is reported missing

Add the exact secret name shown in the workflow error under **Settings >
Secrets and variables > Actions**, then rerun **Deploy Sync Worker**.

### Cloudflare authentication fails or returns code 10000

- Recreate the token from the **Edit Cloudflare Workers** template.
- Scope it to the correct Cloudflare account.
- Confirm `CLOUDFLARE_ACCOUNT_ID` belongs to that account.
- Replace the GitHub secret and rerun the workflow.

### The Worker name is rejected

Use 1-63 lowercase letters, numbers, or internal dashes. Do not begin or end
the name with a dash.

### Turso schema or connection checks fail

- Confirm `TURSO_DATABASE_URL` belongs to the intended database.
- Generate a new full-access Turso token.
- Replace `TURSO_AUTH_TOKEN` in GitHub.
- Rerun the workflow so the schema step executes again.

### Account creation says registration is closed

The self-hosted backend already has its owner account. Choose **Login** and use
that account on the new device. To create a different owner, deploy against a
new empty Turso database; do not delete an existing database unless its sync
data is no longer needed.

Never paste database tokens or JWT secrets into public logs or issues.

### Login fails after switching services

Accounts are not copied between the default backend and a self-hosted Turso
database. Create an account or use credentials that exist on the currently
selected service.

### Sync reports a conflict

Koinly records stale-version conflicts rather than silently overwriting finance
data. Confirm which device has the intended data, synchronize it, then retry
the conflicting edit.

### Android or Windows builds fail

- Run `flutter doctor -v`.
- Confirm Java 17 and the Android SDK for Android builds.
- Confirm the Visual Studio C++ desktop workload for Windows builds.
- Run `flutter clean`, `flutter pub get`, and rebuild.
- For release builds, confirm the required signing secrets are available.

## Project structure

```text
.
├── .github/workflows/
│   ├── build-android-apks.yml
│   └── deploy-sync-worker.yml
├── android/
├── assets/
├── backend/cloudflare-turso/   # legacy reference backend
├── cloud/worker/               # active Cloudflare Worker + Turso backend
├── lib/
│   ├── main.dart
│   ├── models.dart
│   ├── persistence_stores.dart
│   ├── sync_models.dart
│   ├── sync_services.dart
│   └── update_service.dart
├── test/
├── tool/
├── pubspec.yaml
└── README.md
```

`backend/cloudflare-turso/` is retained as legacy reference material. New
account sync and self-hosted deployments use `cloud/worker/`.

## Security notes

- Turso credentials belong only in GitHub Actions secrets and Cloudflare
  Worker secrets.
- Cloudflare API credentials belong only in GitHub Actions secrets.
- App access and refresh tokens are stored with platform secure storage.
- Sync credentials are excluded from app backups.
- Worker health responses do not expose secret values.
- Use a unique high-entropy value for `JWT_SECRET`.
- Scope Cloudflare and Turso credentials to the minimum practical access.
- Rotate exposed credentials immediately and redeploy.

## Packaging

Create a clean source archive with the existing packaging script:

```powershell
.\tool\package_project.ps1
```

The package excludes dependency directories, build output, caches, logs, local
environment files, and other generated artifacts.

## License

See [LICENSE](LICENSE).
