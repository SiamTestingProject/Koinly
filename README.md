# Koinly

Koinly is a local-first personal finance app built with Flutter for Android and Windows. It tracks accounts, transactions, categories, budgets, savings, loans, reminders, reports, exports, and backups. Online sync is optional: the app works offline with local SQLite and can connect to a Cloudflare Worker backed by Turso for account-based multi-device sync.

![Koinly banner](assets/images/koinly-banner.png)

## Contents

- [Features](#features)
- [How Koinly stores and syncs data](#how-koinly-stores-and-syncs-data)
- [Project structure](#project-structure)
- [Run the app locally](#run-the-app-locally)
- [Fork and deploy your own no-login sync Worker](#fork-and-deploy-your-own-no-login-sync-worker)
- [Shared account sync: complete Turso and Cloudflare setup](#shared-account-sync-complete-turso-and-cloudflare-setup)
- [Manual Worker deployment](#manual-worker-deployment)
- [GitHub Actions builds and releases](#github-actions-builds-and-releases)
- [In-app updates](#in-app-updates)
- [Validation and packaging](#validation-and-packaging)
- [Troubleshooting](#troubleshooting)
- [Security notes](#security-notes)

## Features

- Regular, credit, and savings accounts
- Income, expense, and transfer transactions
- Income and expense categories
- Monthly budgets with account/category filters and alert levels
- Savings transfers and daily savings suggestions
- Given and taken loans, repayments, reminders, and overdue alerts
- Analysis charts, category breakdowns, and period summaries
- Bills, subscriptions, and local notifications
- CSV/PDF exports
- Local `.koinlybackup` backup and restore
- Automatic safety backups before destructive restore operations
- Optional account-based multi-device sync
- Optional personal no-login Turso sync
- GitHub Releases-based Android and Windows updater
- Material 3 adaptive UI for phones and desktop

## How Koinly stores and syncs data

Koinly writes finance data to local SQLite first. The app remains usable when the network or backend is unavailable.

For shared account sync, the data path is:

```text
Android/Windows app
        |
        | HTTPS + Koinly account token
        v
Cloudflare Worker (cloud/worker)
        |
        | libSQL connection + Turso token
        v
Turso database
```

The Flutter app never receives `TURSO_AUTH_TOKEN`, `JWT_SECRET`, Telegram credentials, or the registration administrator secret. Those values exist only in GitHub Actions and the deployed Cloudflare Worker.

Sync behavior:

- Local edits are queued and uploaded in the background.
- Signed-in devices pull cloud changes while the app is open and when it resumes.
- Create account adopts the current local data into the new cloud account.
- Login treats existing cloud data as the source of truth: Koinly downloads the cloud copy, creates a local safety backup, and replaces local finance data.
- Restoring a local backup while signed in marks that restored copy for authoritative cloud upload.
- Sync operations are tenant-scoped and use operation IDs, entity versions, and a server cursor.
- `POST /v1/sync/replace` is reserved for an authoritative full replacement after restore.

Koinly includes two different backends:

| Backend | Folder | Use case |
| --- | --- | --- |
| Shared account sync | `cloud/worker/` | Email/password accounts, multiple users, devices, invite-only registration, incremental sync |
| Personal no-login sync | `backend/cloudflare-turso/` | One person using a Worker URL plus private Sync ID/PIN |

Do not deploy both folders as the same Worker. Use separate Worker names and preferably separate Turso databases.

## Project structure

```text
lib/                              Flutter app
  main.dart                       App controller, database, and most screens
  app_config.dart                 App constants and build-time flags
  models.dart                     Finance and diagnostics models
  sync_services.dart              Account/personal sync clients
  update_service.dart             GitHub Releases updater
android/                          Android platform project
windows/                          Windows platform project/generated files
cloud/worker/                     Shared account Cloudflare Worker
  src/index.ts                    Worker routes, auth, sync, and admin API
  schema.sql                      Shared Turso schema
  scripts/apply-schema.mjs        Idempotent schema installer
  wrangler.toml                   Worker name and non-secret variables
backend/cloudflare-turso/         Optional personal no-login Worker
.github/workflows/
  deploy-personal-sync-worker.yml Personal no-login Worker deployment
  deploy-sync-worker.yml          Shared Worker deployment
  build-android-apks.yml          Android/Windows builds and stable releases
tool/
  validate_project.ps1            Flutter validation helper
  package_project.ps1             Clean ZIP builder
```

## Requirements

App development:

- Flutter stable with Dart 3.5 or newer
- Java 17
- Android SDK 36 and NDK `28.2.13676358` for Android builds
- Visual Studio Build Tools with the Desktop C++ workload for Windows builds

Shared backend deployment:

- A Turso account
- A Cloudflare account with Workers enabled
- Node.js 22 and npm
- A GitHub repository if using the included deployment workflow
- A Telegram bot/chat for delivery of single-use registration keys

Official setup references:

- [Install the Turso CLI](https://docs.turso.tech/cli/installation)
- [Create a Turso database](https://docs.turso.tech/cli/db/create)
- [Get a Turso database URL](https://docs.turso.tech/cli/db/show)
- [Create a Turso database token](https://docs.turso.tech/cli/db/tokens/create)
- [Cloudflare Worker secrets](https://developers.cloudflare.com/workers/configuration/secrets/)
- [Cloudflare API token templates](https://developers.cloudflare.com/fundamentals/api/reference/template/)
- [Find a Cloudflare account ID](https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/)
- [Cloudflare `workers.dev` URLs](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)
- [GitHub Actions secrets](https://docs.github.com/en/actions/reference/security/secrets)

## Run the app locally

Install Flutter packages:

```bash
flutter pub get
```

Run Android without online account sync:

```bash
flutter run
```

Run Windows without online account sync:

```bash
flutter config --enable-windows-desktop
flutter run -d windows
```

Run with the shared account Worker enabled:

```bash
flutter run --dart-define=KOINLY_SYNC_API_BASE_URL=https://koinly-sync-worker.YOUR_SUBDOMAIN.workers.dev
```

The Worker URL is a build-time value. Changing the GitHub secret/variable or Cloudflare Worker URL does not change an already-built APK/EXE; rebuild the app after changing it.

Useful build-time values:

| Value | Purpose | Default |
| --- | --- | --- |
| `KOINLY_SYNC_API_BASE_URL` | Shared account Worker base URL | Empty; account sync disabled |
| `KOINLY_APP_VERSION` | Version shown inside the app | `1.0.70` |
| `KOINLY_ENABLE_LOANS` | Enables the loan feature | `true` |
| `KOINLY_INCLUDE_PRERELEASE_UPDATES` | Allows prerelease update checks for development | `false` |

## Fork and deploy your own no-login sync Worker

Use this option when you want online sync through your own Turso database and Cloudflare account without creating a Koinly cloud account. It uses `backend/cloudflare-turso/`, not the shared account server in `cloud/worker/`.

```text
Your fork → GitHub Action → your Cloudflare Worker → your Turso database
                                          ↑
                               Worker URL + Sync ID/PIN
                                          ↑
                                      Koinly app
```

This personal backend does not use Koinly registration keys, Telegram, JWT sessions, or the app's **Create account** button. The Turso credentials stay in GitHub and Cloudflare; the app receives only the public Worker URL and the private Sync ID/PIN you choose.

### Recommended: deploy from your fork with GitHub Actions

#### 1. Fork the repository

Select **Fork** on GitHub, create the fork under your account, and keep the default branch named `main` or `master`. The deployment is a manual Action, so no source-code editing is required.

#### 2. Create a personal Turso database

Install and authenticate the Turso CLI, then run:

```bash
turso auth login
turso db create koinly-personal-sync
turso db show koinly-personal-sync --url
turso db tokens create koinly-personal-sync
```

Save the `libsql://...` URL as `TURSO_DATABASE_URL` and the generated write token as `TURSO_AUTH_TOKEN`. Do not use a read-only token because the Worker stores snapshots. The `sync_snapshots` table is created automatically on first upload; there is no schema command to run.

#### 3. Create Cloudflare deployment credentials

In Cloudflare, create an API token from the **Edit Cloudflare Workers** template and restrict it to your account. Copy your account ID from **Workers & Pages → Account Details**.

Save these values:

```text
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
```

Cloudflare documents the same two CI credentials in its [GitHub Actions deployment guide](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/).

#### 4. Create the personal sync secret

Generate a long random value, preferably at least 32 characters, and save it as `SYNC_SECRET`. It is used to derive the stored PIN verifier and must never be embedded in the Flutter app.

#### 5. Add five GitHub Actions secrets

In your fork, open **Settings → Secrets and variables → Actions → New repository secret** and create:

| Secret | Value |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | Token from the Edit Cloudflare Workers template |
| `CLOUDFLARE_ACCOUNT_ID` | Account that will own the Worker |
| `TURSO_DATABASE_URL` | `libsql://...` URL from Turso |
| `TURSO_AUTH_TOKEN` | Turso database write token |
| `SYNC_SECRET` | Your long random personal sync secret |

Use repository **secrets**, not plain variables. Paste only each value—do not add quotes or `NAME=` before it.

#### 6. Run the deployment Action

Open:

```text
Actions → Deploy Personal No-Login Sync Worker → Run workflow
```

The included `.github/workflows/deploy-personal-sync-worker.yml` action:

1. Installs the personal Worker's locked npm dependencies.
2. Runs its Worker tests.
3. Checks all five GitHub secrets.
4. Uploads `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN`, and `SYNC_SECRET` as encrypted Cloudflare Worker runtime secrets.
5. Deploys the Worker named `koinly-sync`.

The last deployment log prints a URL shaped like:

```text
https://koinly-sync.YOUR_CLOUDFLARE_SUBDOMAIN.workers.dev
```

The action also redeploys automatically after a push to `main` or `master` changes `backend/cloudflare-turso/**` or its workflow file. Other app or README changes do not redeploy this Worker.

#### 7. Verify the Worker

Open the Worker URL in a browser. A successful configured deployment returns HTTP 200 and:

```json
{
  "ok": true,
  "service": "koinly-personal-turso-sync",
  "loginRequired": false
}
```

If it returns HTTP 503 with `"ok": false`, one or more Cloudflare runtime secrets is missing. Recheck the GitHub secret names and rerun the Action.

#### 8. Connect Koinly without an app account

Open **Koinly → Settings → Account & sync → Use own Turso Worker** and enter:

- Your `https://...workers.dev` URL
- A private Sync ID of your choice
- A private Sync PIN of your choice

On the device containing the correct data, select **Upload Data** first. On another device, enter the same Worker URL, Sync ID, and PIN, then select **Sync**. A pull creates a local safety backup and replaces local finance data with the cloud snapshot.

The personal Worker URL is entered at runtime, so you do not need to rebuild Koinly or set `KOINLY_SYNC_API_BASE_URL`. Never enter `TURSO_AUTH_TOKEN` or `SYNC_SECRET` in the app.

This backend uses last-upload-wins behavior. Sync before editing on another device, and keep the Sync ID/PIN private because anyone with all three connection values can access that snapshot.

### Alternative: Cloudflare's Import a repository screen

You can connect the fork directly through **Cloudflare → Workers & Pages → Create application → Import a repository**. GitHub Actions is recommended because it uploads all runtime secrets during deployment; the direct Cloudflare route requires one extra dashboard step.

For the screen shown above, use:

| Cloudflare field | Value |
| --- | --- |
| Repository | Your Koinly fork |
| Project name | `koinly-sync` |
| Production branch | `main` or `master` |
| Root directory | `backend/cloudflare-turso` |
| Build command | `npm ci && npm test` |
| Deploy command | `npx wrangler deploy` |
| Builds for non-production branches | Off, unless you want preview builds |
| Protect with Cloudflare Access | Off; the Worker has its own Sync ID/PIN protection |

The project name must match `name = "koinly-sync"` in `backend/cloudflare-turso/wrangler.toml`. If the import screen does not show **Root directory**, finish connecting the repository, then set it under **Worker → Settings → Builds → Build configuration** before retrying the build. Cloudflare explains these fields in its [Workers Builds configuration guide](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/).

If you want the first build to work from the exact screen in the screenshot before setting a root directory, use these two commands instead:

```text
Build command:  cd backend/cloudflare-turso && npm ci && npm test
Deploy command: cd backend/cloudflare-turso && npx wrangler deploy
```

Do not use both the `cd backend/cloudflare-turso` commands and a `backend/cloudflare-turso` root directory at the same time.

After the first deployment, open **Worker → Settings → Variables and Secrets → Add**, choose **Secret**, and add these runtime secrets:

```text
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
SYNC_SECRET
```

Select **Deploy**, then verify the Worker URL and connect it in Koinly as described above. Build variables alone are not runtime Worker secrets; use **Settings → Variables and Secrets**. See Cloudflare's [Worker secrets guide](https://developers.cloudflare.com/workers/configuration/secrets/).

## Shared account sync: complete Turso and Cloudflare setup

This is the recommended production setup for Koinly accounts. Follow the steps in order.

### 1. Create the Turso database

Install and authenticate the Turso CLI. On Windows, the Turso Cloud CLI currently runs through WSL.

```bash
turso auth login
```

Create a database:

```bash
turso db create koinly-sync
```

Copy its libSQL URL:

```bash
turso db show koinly-sync --url
```

Example shape:

```text
libsql://koinly-sync-your-organization.turso.io
```

Create a database-scoped write token:

```bash
turso db tokens create koinly-sync
```

Save these two values immediately:

```text
TURSO_DATABASE_URL=libsql://...
TURSO_AUTH_TOKEN=eyJ...
```

The Worker creates tables and writes sync data, so do not create this token with `--read-only`. The token is sensitive and should never be committed to the repository or embedded in the app.

### 2. Prepare Telegram registration-key delivery

The shared Worker uses one active, single-use registration key. After a key is consumed, the Worker generates the next key and sends it to a Telegram chat.

1. Open Telegram and create a bot with `@BotFather`.
2. Save the bot token as `TELEGRAM_BOT_TOKEN`.
3. Send the bot a message, or add it to the target group/channel and give it permission to post.
4. Obtain the target chat ID and save it as `REGISTRATION_KEY_CHAT_ID`.
5. Never commit the bot token or paste it into public logs/issues.

For a private chat, send the bot a message before checking updates; otherwise Telegram has no conversation from which to obtain the chat ID.

### 3. Generate the Koinly cryptographic secrets

Create two independent random values:

```text
JWT_SECRET
REGISTRATION_ADMIN_SECRET
```

Use a password manager or a cryptographic generator. Each value should contain at least 32 random characters; 64 characters is a sensible target.

`JWT_SECRET` is used for access-token signatures, password hashing/peppering, and encryption of the active registration-key delivery copy. Keep it stable. Replacing it on an existing deployment invalidates sessions and can prevent existing password hashes and encrypted registration-key data from being used.

`REGISTRATION_ADMIN_SECRET` protects the registration-key administration API and must contain at least 32 characters.

### 4. Create the Cloudflare deployment token

1. Sign in to the Cloudflare dashboard.
2. Open **My Profile → API Tokens → Create Token**.
3. Use Cloudflare's **Edit Cloudflare Workers** template.
4. Restrict the token to the account that will host Koinly.
5. Copy the token when Cloudflare displays it; it is shown only once.

The template currently includes the permissions used by this workflow, including Worker Scripts write plus the account/user read permissions Wrangler uses. If you create a custom token, the practical minimum for this repository is:

```text
Account > Workers Scripts  > Edit/Write
Account > Account Settings > Read
User    > User Details      > Read
User    > Memberships       > Read
```

Add `Zone > Workers Routes > Edit/Write` only if you attach the Worker to a route or custom domain. It is not needed for the default `workers.dev` URL.

Copy the Cloudflare account ID from **Workers & Pages → Account Details**, or use the dashboard search command **Copy account ID**.

Save:

```text
CLOUDFLARE_API_TOKEN=...
CLOUDFLARE_ACCOUNT_ID=...
```

### 5. Determine the Worker URL

The included `cloud/worker/wrangler.toml` names the Worker:

```toml
name = "koinly-sync-worker"
```

With the default Cloudflare route, its URL is:

```text
https://koinly-sync-worker.YOUR_CLOUDFLARE_SUBDOMAIN.workers.dev
```

Find `YOUR_CLOUDFLARE_SUBDOMAIN` in **Cloudflare → Workers & Pages**. You do not need to create the Worker manually; the first Wrangler deployment creates it.

Save the complete URL without a trailing slash as:

```text
KOINLY_SYNC_API_BASE_URL=https://koinly-sync-worker.YOUR_CLOUDFLARE_SUBDOMAIN.workers.dev
```

The Worker URL is not a credential—it is embedded in every built app and can be discovered by users. Security comes from account authentication and the Worker secrets. It may be stored as either a GitHub Actions repository variable or secret.

### 6. Add GitHub Actions secrets and variables

Open the GitHub repository and go to:

```text
Settings → Secrets and variables → Actions
```

Create these repository secrets:

| Name | Value | Used by |
| --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token | Wrangler deployment |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID | Wrangler deployment |
| `TURSO_DATABASE_URL` | `libsql://...` database URL | Schema installer and Worker |
| `TURSO_AUTH_TOKEN` | Turso database write token | Schema installer and Worker |
| `JWT_SECRET` | Stable random secret | Passwords, tokens, key encryption |
| `TELEGRAM_BOT_TOKEN` | Token from BotFather | Registration-key delivery |
| `REGISTRATION_KEY_CHAT_ID` | Telegram target chat ID | Registration-key delivery |
| `REGISTRATION_ADMIN_SECRET` | Independent random secret, 32+ characters | Protected admin endpoints |

Create `KOINLY_SYNC_API_BASE_URL` as a repository variable or secret. Both included workflows accept either location.

The shared Worker deployment therefore needs eight real secrets plus the Worker URL value. Android signing and optional Windows signing values are separate from backend deployment.

Do not add quotes around secret values in GitHub. Do not paste names such as `TURSO_DATABASE_URL` into the value field; paste the actual corresponding value.

### 7. Deploy the Worker with GitHub Actions

Run:

```text
Actions → Deploy Sync Worker → Run workflow
```

The workflow in `.github/workflows/deploy-sync-worker.yml` performs these steps:

1. Checks out the repository.
2. Installs Node.js 22 dependencies.
3. Runs the TypeScript typecheck.
4. Verifies all required GitHub values exist.
5. Applies `cloud/worker/schema.sql` to Turso.
6. Uploads the six Worker runtime secrets with Wrangler.
7. Deploys `cloud/worker/src/index.ts` as `koinly-sync-worker`.
8. Calls the protected bootstrap endpoint so one active registration key exists.

The deployment workflow also runs automatically when a push to `main` or `master` changes `cloud/worker/**` or the deployment workflow itself. Editing only `README.md` does not trigger a Worker deployment.

### 8. Understand the Turso schema

The shared schema creates:

| Table | Purpose |
| --- | --- |
| `users` | Account identity and password hash |
| `refresh_tokens` | Rotating device refresh sessions |
| `devices` | Signed-in device registry |
| `sync_entities` | Current server copy of each finance entity |
| `sync_changes` | Ordered change log consumed by device cursors |
| `processed_operations` | Idempotency records for repeated client operations |
| `rate_limits` | Server-side request throttling state |
| `registration_keys` | Single-use invite-key ledger and delivery status |

`schema.sql` contains only `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS` statements. It is safe to apply repeatedly and does not delete existing finance data.

The Worker also calls the same idempotent schema bootstrap before protected auth/sync requests. The GitHub schema step is still valuable because deployment fails early if the database URL/token is wrong.

### 9. Verify the deployment

Open the Worker root:

```text
https://koinly-sync-worker.YOUR_CLOUDFLARE_SUBDOMAIN.workers.dev/
```

It should return a service summary with:

```json
{
  "ok": true,
  "service": "koinly-sync",
  "configured": true
}
```

Then open:

```text
https://koinly-sync-worker.YOUR_CLOUDFLARE_SUBDOMAIN.workers.dev/health
```

A healthy deployment returns fields equivalent to:

```json
{
  "ok": true,
  "service": "koinly-sync",
  "configured": true,
  "databaseReachable": true,
  "schemaReady": true,
  "missingTables": []
}
```

`configured: false` means at least one of the six Worker runtime secrets is missing or `REGISTRATION_ADMIN_SECRET` is shorter than 32 characters. `databaseReachable: false` means the Turso URL/token or network connection failed. `schemaReady: false` means one or more required tables are still missing.

### 10. Build Koinly with the Worker URL

The app cannot use the shared Worker until the URL is passed at build time.

For GitHub builds, add `KOINLY_SYNC_API_BASE_URL` and run:

```text
Actions → Build Android APKs and Windows Installer → Run workflow
```

For a local Android release:

```bash
flutter build apk --release --dart-define=KOINLY_SYNC_API_BASE_URL=https://koinly-sync-worker.YOUR_SUBDOMAIN.workers.dev
```

For a local Windows release:

```bash
flutter build windows --release --dart-define=KOINLY_SYNC_API_BASE_URL=https://koinly-sync-worker.YOUR_SUBDOMAIN.workers.dev
```

### 11. Create the first Koinly sync account

After deployment, the workflow calls:

```text
POST /v1/admin/registration-key/bootstrap
```

If no valid active registration key exists, the Worker creates one and sends it to the configured Telegram chat. In Koinly:

1. Open **Settings → Account & sync** (or use the setup login page).
2. Select **Create account**.
3. Enter email, password, and the current registration key.
4. After successful registration, that key becomes permanently used.
5. The Worker creates and delivers the next active key.

Used, revoked, and expired keys remain in the audit ledger and cannot become active again.

### 12. Registration-key administration

Every endpoint below requires:

```text
Authorization: Bearer REGISTRATION_ADMIN_SECRET
```

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `POST` | `/v1/admin/registration-key/bootstrap` | Create a key only if no valid active key exists |
| `GET` | `/v1/admin/registration-key/status` | Show status without revealing plaintext |
| `GET` | `/v1/admin/registration-key/reveal` | Emergency reveal of the encrypted active key |
| `POST` | `/v1/admin/registration-key/rotate` | Revoke/replace the active key and deliver the new one |
| `POST` | `/v1/admin/registration-key/revoke` | Revoke the active key |
| `POST` | `/v1/admin/registration-key/retry-delivery` | Retry Telegram delivery |

Example status request:

```bash
curl "https://YOUR_WORKER/v1/admin/registration-key/status" \
  -H "Authorization: Bearer YOUR_REGISTRATION_ADMIN_SECRET"
```

Example rotation:

```bash
curl -X POST "https://YOUR_WORKER/v1/admin/registration-key/rotate" \
  -H "Authorization: Bearer YOUR_REGISTRATION_ADMIN_SECRET"
```

Do not paste the real administrator secret into shell history on a shared computer. Prefer an environment variable or a secure API client.

## Manual Worker deployment

GitHub Actions is the shortest supported path. Use manual deployment only when debugging or when the source is not hosted on GitHub.

Open the Worker folder and install the locked dependencies:

```bash
cd cloud/worker
npm ci
npm run typecheck
```

Authenticate Wrangler interactively:

```bash
npx wrangler login
```

Apply the schema. `scripts/apply-schema.mjs` reads `TURSO_DATABASE_URL` and `TURSO_AUTH_TOKEN` from the process environment.

PowerShell:

```powershell
$env:TURSO_DATABASE_URL = "libsql://YOUR_DATABASE.turso.io"
$env:TURSO_AUTH_TOKEN = "YOUR_TURSO_TOKEN"
npm run schema:apply
```

Bash:

```bash
export TURSO_DATABASE_URL="libsql://YOUR_DATABASE.turso.io"
export TURSO_AUTH_TOKEN="YOUR_TURSO_TOKEN"
npm run schema:apply
```

Add all six Worker secrets. Wrangler prompts for each value and stores it encrypted in Cloudflare:

```bash
npx wrangler secret put TURSO_DATABASE_URL
npx wrangler secret put TURSO_AUTH_TOKEN
npx wrangler secret put JWT_SECRET
npx wrangler secret put TELEGRAM_BOT_TOKEN
npx wrangler secret put REGISTRATION_KEY_CHAT_ID
npx wrangler secret put REGISTRATION_ADMIN_SECRET
```

Deploy:

```bash
npx wrangler deploy
```

Verify `/health`, then call the bootstrap endpoint manually if needed. For local Worker development, place the same six values in `cloud/worker/.dev.vars`; that file is ignored by Git and is loaded by `wrangler dev`. The schema installer does not read `.dev.vars`, so export the two Turso values before running `npm run schema:apply`.

## Shared Worker API

Public/service endpoints:

```text
GET  /
GET  /health
```

Authentication endpoints:

```text
POST /v1/auth/register
POST /v1/auth/login
POST /v1/auth/refresh
POST /v1/auth/logout
```

Authenticated sync endpoints:

```text
POST /v1/sync/initial
POST /v1/sync/push
POST /v1/sync/replace
GET  /v1/sync/pull?cursor=0&limit=100
GET  /v1/sync/status
```

The request/response implementation and validation rules are in `cloud/worker/src/index.ts`. Do not expose the admin endpoints through an unauthenticated proxy.

## GitHub Actions builds and releases

`.github/workflows/build-android-apks.yml` builds:

```text
Koinly-v<version>-arm32.apk
Koinly-v<version>-arm64.apk
Koinly-v<version>-x86_64.apk
Koinly-v<version>-universal.apk
Koinly-v<version>.aab
Koinly-v<version>-Setup.exe
```

The workflow:

- Runs manually or after app/build files change on `main`/`master`
- Requires `KOINLY_SYNC_API_BASE_URL`
- Uses Java 17, Android SDK 36, NDK 28, and Flutter stable
- Builds split Android APKs and an AAB
- Generates the universal APK from the AAB with bundletool
- Builds a Windows x64 application and Inno Setup installer
- Publishes a normal stable GitHub Release with semantic tag `v1.0.<build>`
- Uses the current `CHANGELOG.md` section for release notes
- Keeps older versioned GitHub Releases

Automatic CI versioning is:

```text
BUILD_NUMBER = 1000 + github.run_number
VERSION_NAME = 1.0.<BUILD_NUMBER>
```

Only changes matching a workflow's `paths` list trigger that workflow. A README-only commit triggers neither the app release workflow nor the Worker deployment workflow; run either workflow manually when documentation is the only changed file.

The repository currently contains a bundled development release keystore so CI-built APKs can update each other. Replace that keystore and the hard-coded development credentials before distributing Koinly as a production application. Keep the replacement signing key permanently—Android updates must use the same signing identity.

Windows signing is optional. The workflow recognizes:

```text
WINDOWS_CODESIGN_PFX_BASE64
WINDOWS_CODESIGN_PASSWORD
WINDOWS_CODESIGN_TIMESTAMP_URL
```

Unsigned Windows builds still install, but Microsoft Defender SmartScreen may show a warning.

## In-app updates

Koinly checks public stable releases from `SiamTestingProject/Koinly`.

- Draft releases are ignored.
- Prereleases are ignored in production.
- Versions are compared semantically.
- The release body becomes the in-app changelog.
- Android selects ARM64, ARM32, x86_64, or Universal APK assets by filename.
- Android downloads inside the app and opens the package installer.
- Windows prefers the versioned `Setup.exe` release asset.

Update settings are available at **Settings → Updates**.

## Validation and packaging

Validate Flutter source:

```powershell
powershell -ExecutionPolicy Bypass -File tool\validate_project.ps1
```

The helper runs:

```text
flutter pub get
flutter analyze --fatal-infos
flutter test
```

Validate the shared Worker:

```bash
cd cloud/worker
npm ci
npm run typecheck
```

Validate the personal Worker:

```bash
cd backend/cloudflare-turso
npm ci
npm test
```

Create a clean project ZIP on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tool\package_project.ps1 -OutputPath C:\path\Koinly-clean.zip
```

The packaging script excludes build outputs, caches, Worker `node_modules`, Wrangler state, `.env`, `.dev.vars`, logs, and existing ZIPs. ZIP entries use `/` paths so GitHub recognizes `.github/workflows/` correctly.

## Troubleshooting

### GitHub Actions says a secret is missing

Check **Settings → Secrets and variables → Actions**. Names must match exactly. The personal no-login Action needs its five listed repository secrets. The shared account Action needs eight repository secrets plus `KOINLY_SYNC_API_BASE_URL`, which may be a repository variable or secret.

### Wrangler cannot authenticate in GitHub Actions

If Cloudflare returns authentication code `10000`, recreate `CLOUDFLARE_API_TOKEN` with the **Edit Cloudflare Workers** template, restrict it to the correct account, update the GitHub secret, and confirm `CLOUDFLARE_ACCOUNT_ID` belongs to the same account.

For local deployment, run `npx wrangler login`. In non-interactive CI, Wrangler requires `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.

### Wrangler cannot find static files

Run Wrangler from `cloud/worker/`, where this project's `wrangler.toml` exists. This is an API Worker and does not require a static asset directory.

### `/health` returns `configured: false`

Check all six deployed Worker secrets:

```text
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
TELEGRAM_BOT_TOKEN
REGISTRATION_KEY_CHAT_ID
REGISTRATION_ADMIN_SECRET
```

Also confirm `REGISTRATION_ADMIN_SECRET` is at least 32 characters.

### `/health` returns `databaseReachable: false`

- Confirm the URL begins with `libsql://`.
- Create a fresh database token and update `TURSO_AUTH_TOKEN`.
- Ensure the token is not read-only.
- Run `npm run schema:apply` with the same two Turso values.
- Do not add whitespace, quotes, or Markdown links to secret values.

### `/health` returns `schemaReady: false`

Run the **Deploy Sync Worker** workflow again or run `npm run schema:apply` locally. Check `missingTables` in the response to see what was not created.

### Worker returns Cloudflare error 1101 or HTTP 500

Open **Cloudflare → Workers & Pages → koinly-sync-worker → Logs** or run:

```bash
cd cloud/worker
npx wrangler tail
```

Common causes are invalid Turso credentials, missing Worker secrets, an old deployed Worker version, or database request limits. Redeploy the current `cloud/worker` source before debugging code that is not live.

### Registration key is not delivered

- Confirm the bot token is correct.
- Ensure the target user has messaged the bot, or the bot can post in the target group/channel.
- Check `/v1/admin/registration-key/status`.
- Call `/v1/admin/registration-key/retry-delivery`.
- Use `/v1/admin/registration-key/reveal` only as an emergency retrieval path.

### The app says the online backend is not configured

The app was built without `KOINLY_SYNC_API_BASE_URL`. Add the GitHub value and rebuild, or pass the URL with `--dart-define` locally.

### The app still calls an old Worker URL

Worker URLs are compiled into the app. Rebuild and reinstall the APK/EXE after changing the URL.

### A second device does not show new data immediately

Confirm both devices use the same Koinly account and current app version. Keep the second app open for its foreground sync interval or reopen it to trigger resume sync. Check **Account & sync** for pending uploads/errors.

### Setup Node cannot cache npm dependencies

Both backend folders include `package-lock.json`. Run `npm ci` from the corresponding folder and ensure the workflow cache path points to that lockfile.

### TypeScript reports an unavailable package version

Use the committed `package-lock.json` with `npm ci`. Do not guess a future `@cloudflare/workers-types` version; update dependencies only to versions available in the npm registry and commit the regenerated lockfile.

### Windows installer is unsigned

Configure the optional Windows signing values. Without a trusted certificate, SmartScreen warnings are expected even when the build succeeds.

## Security notes

- Never commit Turso tokens, Cloudflare tokens, JWT/admin secrets, Telegram tokens, `.dev.vars`, `.env`, or signing certificates/private keys.
- Use a database-scoped Turso token for this Worker, not a broad organization token.
- Restrict the Cloudflare API token to the account that hosts Koinly.
- Keep `JWT_SECRET` stable after users are created.
- Treat registration keys as credentials until they are consumed.
- Do not put Turso credentials in Dart code or `--dart-define` values.
- The public Worker URL is not a secret.
- Rotate a leaked Turso/Cloudflare/Telegram token immediately and redeploy.
- Make a Turso backup before intentional destructive database maintenance.
- Replace the bundled Android development signing key before production distribution.

## License

Apache License 2.0. See [LICENSE](LICENSE).
