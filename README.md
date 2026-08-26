# Koinly

A local-first personal finance tracker built in Flutter with a polished Material 3 mobile and desktop UI. Koinly helps users manage accounts, transactions, categories, budgets, savings, reminders, reports, exports, and local backups from one Android or Windows app.

![Koinly banner](assets/images/koinly-banner.png)

---

## App versioning

- Baseline source version: `1.0.71+72`
- GitHub Actions automatically stamps each release build with a newer version.
- Generated version format: `1.0.<1000 + github.run_number>`
- Android `versionName`, Android `versionCode`, `pubspec.yaml`, Windows installer version, and the in-app About screen version are updated during CI.
- Manual edits to `pubspec.yaml`, `android/app/build.gradle`, and `lib/main.dart` are no longer required for normal release version bumps.
- Windows installer output remains `KoinlySetup.exe`.
- Stable production tags use semantic versions such as `v1.0.1042`.
- In-app update checks read public GitHub Releases from `SiamTestingProject/Koinly`.

---

## Project status

| Area | Current implementation |
| --- | --- |
| App framework | Flutter / Dart |
| Platforms | Android and Windows |
| Android package ID | `com.koinly.siam` |
| UI system | Dark glass finance dashboard inspired by the latest Koinly mockup, with cyan accents, compact cards, centered popups, and adaptive spacing |
| Local database | SQLite via `sqflite` and desktop SQLite FFI |
| State management | `provider` + `ChangeNotifier` |
| Analytics/crash reporting | Firebase Analytics + Crashlytics with optional initialization |
| Online sync | Account-based automatic multi-device sync |
| Sync backend | Cloudflare Worker API |
| Cloud database | Turso, accessed only by the Worker |
| Local sync state | SQLite outbox, cursor, entity versions, and conflict records |
| Backup/restore | Local `.koinlybackup` files plus automatic safety backups before destructive restores |
| CI build | GitHub Actions for Android APKs and Windows installer |
| Android outputs | Universal, ARM32, ARM64, x86_64 release APKs and Android App Bundle |
| Windows output | `KoinlySetup.exe` |
| License | Apache License 2.0 |

---

## Source structure

The project is being gradually split out of the original large single-file Flutter build.

- `lib/main.dart` still contains the app controller, persistence services, and most UI screens.
- `lib/app_config.dart` contains app constants, feature flags, platform helpers, and shared visual constants.
- `lib/branding_widgets.dart` contains reusable Koinly branding widgets, including the shared app icon.
- `lib/collection_utils.dart` contains small collection extensions used by filtering and lookup flows.
- `lib/icon_helpers.dart` contains shared icon lookup, custom-image icon handling, and reusable icon bubble rendering.
- `lib/models.dart` contains finance enums, SQLite mapping models, date/color helpers, and data-health model types.
- `lib/persistence_stores.dart` contains SharedPreferences and secure credential storage wrappers.
- `lib/reminder_service.dart` contains local notification setup and daily reminder scheduling.
- `lib/sync_models.dart` contains shared sync exception/session data types.
- `lib/sync_services.dart` contains legacy Cloudflare sync, account sync API client, and MongoDB snapshot sync helpers.
- `lib/ui_foundation.dart` contains responsive breakpoints, shared motion/shape helpers, page transitions, pressable behavior, and scroll physics.
- `lib/update_service.dart` contains the GitHub Releases updater, semantic versioning, changelog parsing, asset matching, download state, and Android installer helpers.

This staged split keeps behavior stable while making future analyzer, editor, and performance work less painful.

---

## In-app updates

Koinly includes a GitHub Releases-based updater.

- Automatic update check runs after app startup.
- Manual update check is available in **Settings → Updates**.
- Draft GitHub releases are ignored.
- Prereleases are ignored in production builds and can be included in development builds with `KOINLY_INCLUDE_PRERELEASE_UPDATES=true`.
- Version comparison is semantic, so `1.4.10` correctly sorts after `1.4.8`, and `1.10.0` correctly sorts after `1.4.10`.
- Release notes are fetched from the actual GitHub Release body and rendered inside the app.
- Android downloads APKs in-app and opens Android’s installer automatically after download.
- If Android blocks unknown-app installs, Koinly opens the system “Allow from this source” page and resumes installation when the user returns.
- If the installer is cancelled after a successful download, **Settings → Updates** shows an install action for the existing APK instead of forcing another download.
- Windows prefers semantic installer assets such as `Koinly-v1.0.1042-Setup.exe`; if no installer is available, the GitHub release page opens.
- Android CI generates the Universal APK from the AAB with bundletool, avoiding one extra full Flutter Android compile.

Expected release assets:

- `Koinly-v<version>-arm64.apk`
- `Koinly-v<version>-arm32.apk`
- `Koinly-v<version>-x86_64.apk`
- `Koinly-v<version>-universal.apk`
- `Koinly-v<version>.aab`
- `Koinly-v<version>-Setup.exe`

Release notes come from `CHANGELOG.md`. The workflow first looks for the current version section, then falls back to only the first/current bullet under each heading in `## Unreleased` and stops before `### Previous development history`. This keeps the in-app Latest release changelog focused on what was changed, added, removed, or fixed in that exact release only.

---

## Visual design

- Deep navy app background with lightweight cyan accents.
- Glass-style cards and bottom navigation with subtle borders and shadows.
- Home dashboard focuses on balance, accounts, budgets, and category spending without the old Quick actions block.
- Balance, account, transaction, and category surfaces use the same compact rounded-card language across Android and desktop.

---

## Performance notes

- App shell rebuilds are scoped to the values that actually affect the shell, such as theme and selected tab.
- Account, category, and balance lookups are cached after every database reload so long lists do not repeatedly scan the full in-memory dataset.
- Money formatting reuses cached formatters instead of creating a new formatter for every visible amount.
- Home dashboard category totals reuse the already-filtered transaction list.
- Background online sync uses incremental pulls and avoids global busy-state rebuilds; manual sync/sign-in can still fully overwrite local finance data when required.
- Login/cloud overwrite removes untouched starter Cash/Card/Bank Account placeholders after applying the cloud copy, so old seeded accounts do not survive sign-in.
- Full restored-data uploads use a longer request timeout than small incremental syncs, and the Account & sync page now reports an existing background sync instead of making a manual tap look ignored.
- Signed-in devices automatically run a quiet foreground sync every 15 seconds and once on app resume, so changes made on one device are pulled by other open devices without using Restore cloud copy.
- Small icon images use medium filtering to reduce GPU work while scrolling.
- Page transitions now use shorter fade-only motion, and the heavy background glow layers were removed to reduce animation jank on both Windows and Android.
- Advanced settings includes Performance mode. It is enabled by default on desktop and reduces page transitions, press animations, animated card changes, update-wave animation, gradients, and heavy shadows.
- Desktop card lists use static card containers with lighter visual effects so account/category/transaction scrolling has less GPU and layout work.
- Long finance lists disable unnecessary keep-alive and semantic-index bookkeeping and rely on the framework's built-in row repaint isolation instead of adding duplicate repaint boundaries.
- Desktop page headers are slightly more compact than mobile headers so Windows layouts feel less oversized.

---

## Data safety

- Manual backup restore and the Settings Load backup workflow create a local safety backup before importing the selected `.koinlybackup`.
- Restore cloud copy and setup-login cloud overwrite download the cloud copy first, then create a safety backup, then replace local finance data.
- Server reset sync operations also create a safety backup before clearing local finance data.
- Legacy online cloud restore also creates a safety backup before replacing local data.
- The app keeps the newest 3 safety backups in local app storage.
- **Advanced settings → Restore last safety backup** reopens the latest safety backup if a restore/cloud-overwrite needs to be undone.
- Loaded/restored backup data is automatically marked as the local source of truth and uploads to cloud sync when the user is signed in.

---

## Data health diagnostics

Koinly includes **Advanced settings → Data health** for quick local diagnostics.

The health check reports:

- account, category, transaction, and budget counts
- pending cloud-sync upload operations
- unresolved sync conflicts
- transactions pointing to missing accounts
- transactions pointing to missing categories
- budgets with missing account/category selections
- skipped setup starter-account leftovers

The page is mostly read-only. Its only repair action removes untouched Cash/Card/Bank Account starter placeholders when the user already chose to skip account setup.

Data health can also build a privacy-safe diagnostics report. The report can be copied or shared and includes app version, platform, setup state, local data counts, sync status, pending uploads, conflicts, update state, and health findings without including auth tokens or database credentials.

---

## Validation and packaging

Koinly includes local helper scripts for repeatable validation and clean ZIP handoff.

- `analysis_options.yaml` excludes generated Worker dependency/cache folders and package-output folders from Dart analysis.
- `.gitignore` keeps Flutter/Android/Windows build outputs, Worker `node_modules`, Wrangler cache, environment files, ZIPs, logs, and local output folders out of source packages.
- Run `tool\validate_project.ps1` to execute `flutter pub get`, `flutter analyze --fatal-infos`, and `flutter test`.
- The validation helper supports `-PubGetTimeoutSeconds`, `-AnalyzeTimeoutSeconds`, and `-TestTimeoutSeconds`, plus `-SkipPubGet`, `-SkipAnalyze`, and `-SkipTests` for targeted checks.
- Run `tool\package_project.ps1 -OutputPath C:\path\Koinly-clean.zip` to create a clean project ZIP.
- Clean packages intentionally exclude `cloud\worker\node_modules`, build folders, caches, temporary outputs, and generated logs so the ZIP stays small and uploadable.
- Clean packages force ZIP entry paths to use `/` so GitHub receives real folders such as `.github/workflows` instead of Windows-style backslash filenames.
- If analyzer timeouts continue, the next structural fix is to split the current large `lib\main.dart` into smaller feature files so Dart analysis can resolve the app incrementally.
- Phase 8 started that split by moving shared app config/constants and finance models out of `lib\main.dart`.
- Phase 9 continued the split by moving reusable UI foundation primitives out of `lib\main.dart`.
- Phase 10 continued the split by moving preference/credential stores and sync data types out of `lib\main.dart`.
- Phase 11 continued the split by moving reminder scheduling and sync network/database helper services out of `lib\main.dart`.
- Phase 12 continued the split by moving reusable branding and collection utility code out of `lib\main.dart`.
- Phase 13 continued the split by moving reusable icon lookup/rendering helpers out of `lib\main.dart`.
- Phase 14 fixed clean ZIP path separators so GitHub Actions workflow files upload as real `.github/workflows` files.
- Phase 15 fixed Flutter SDK name collisions by hiding framework `Category`/`Summary` annotations from `lib\main.dart` imports.
- Phase 17 hardened `/v1/sync/replace` so duplicate snapshot upserts and repeated operation IDs no longer cause Worker 500 responses.
- Phase 18 reduced `/v1/sync/replace` Turso calls by batching snapshot writes, avoiding Cloudflare's per-invocation subrequest limit.
- Phase 19 simplified the Account & sync page by hiding backend-build explanation text and the restore/upload help paragraph.

---

## README sync note

This README was rebuilt by comparing the current Koinly version with the uploaded `Koinly-main.zip`.

Kept from the uploaded version where still accurate:
- clean project status section
- feature grouping
- backend setup references
- build instructions
- troubleshooting structure
- API/backend documentation style

Added for the current app:
- Windows installer workflow and `KoinlySetup.exe`
- automatic GitHub Actions version stamping
- Windows title/executable branding as `Koinly`
- Material 3 Expressive UI behavior
- automatic safety backups before destructive restore/cloud-overwrite operations
- Advanced settings Data health diagnostics
- privacy-safe copy/share diagnostics report
- validation/package scripts and clean source ZIP generation
- validation timeout controls for slow local analyzer/pub/test runs
- Phase 8 source split with `lib/app_config.dart` and `lib/models.dart`
- Phase 9 source split with `lib/ui_foundation.dart`
- Phase 10 source split with `lib/persistence_stores.dart` and `lib/sync_models.dart`
- Phase 11 source split with `lib/reminder_service.dart` and `lib/sync_services.dart`
- Phase 12 source split with `lib/branding_widgets.dart` and `lib/collection_utils.dart`
- Phase 13 source split with `lib/icon_helpers.dart`
- Phase 14 GitHub/ForgePort ZIP path separator fix for automated Actions workflow detection
- Phase 15 Flutter 3.47 `Category`/`Summary` import collision fix for Android release builds
- Phase 17 Cloudflare Worker `/v1/sync/replace` duplicate-upsert/idempotency fix
- Phase 18 Cloudflare Worker `/v1/sync/replace` subrequest-limit fix with chunked Turso batches
- Phase 19 Account & sync page cleanup hiding backend/debug explanation text
- onboarding login/create-account actions
- onboarding skip-accounts flow that removes untouched starter accounts
- Hidden Settings naming
- single-toggle category filters
- account-based automatic multi-device sync
- server-authoritative sync download behavior
- Financial Health Summary popup behavior
- daily 10 Savings Account suggestion bubbles
- budget alert summary behavior


## Core data rules

Koinly is strict about money classification.

- Income counts only as income.
- Expense counts only as expense.
- Regular transfers are internal.
- Savings transfers are internal and never count as income or expense.
- Bills and subscriptions are tracked separately for reminders and summaries.
- Budget usage comes from real expense category spending.
- Exports follow active filters.

---

## Features

### Accounts

Koinly supports regular accounts, credit accounts, and Savings accounts. Users can create, edit, delete, reorder, color, and icon-tag accounts. Account balances appear across Home and account pages. Savings balances are kept separate from normal operating balances.

### Transactions

Koinly supports income, expense, and transfer transactions with date/time, amount, account, category, and notes. Amount entry uses the normal Android soft keyboard or desktop keyboard instead of a custom in-app keypad. Filters support date range, account, category, and transaction type. Transfer records avoid category double counting. Savings movements stay out of income/expense totals.

### Categories

Income and expense categories are managed from one page. Expense/Income uses one toggle button. Category cards use icons and colors. Category detail pages show real category transactions only. Transfer and Savings transfer rows are excluded from category spending pages.

### Budgets

Budgets support monthly limits, category scope, account scope, progress tracking, remaining budget, and alert levels. Status can be safe, warning, near limit, limit reached, or overspent. Budget data is included in Financial Health Summary.

### Savings

Savings has a dedicated Savings Accounts page. Transfers into and out of Savings are internal transfers. Savings activity appears separately in summaries. Savings suggestion profile is available in Settings. The Savings page shows 10 daily mystery `?` suggestion bubbles. Tapping a bubble opens the full suggestion. Checked suggestions are saved for the day. After all 10 are checked, no more appear until the next day.

### Financial Health Summary

Financial Health Summary is not a fixed Analysis page section. It appears automatically after a month or year ends. Users can go through summary pages or skip all. Skipped and reviewed summaries are remembered.

The summary includes income, expenses, net flow, savings transfers, savings balance movement, current savings balance, recurring bills/subscriptions, paid/unpaid/upcoming/overdue bills, budget usage, remaining budget, overspent categories, and a health result.

Possible status results include Saved Money, Overspent, Stable Month, Stable Year, and Strong Savings Growth.

Yearly view includes month-by-month income, expense, savings, bills, budget usage, best month, worst month, highest income month, highest expense month, highest savings month, and most overspent month.

### Reminders

Reminder-related data supports bills, subscriptions, tuition, rent, internet bills, mobile recharge, electricity bills, EMI payments, scheduled payments, and overdue alerts. Reminder status is included in Financial Health Summary.

### Analysis and reports

The Analysis page remains focused on charts and analytics: income/expense charting, cash flow trend, category breakdown, budget usage context, filter-aware summaries, responsive chart cards, and Material 3 Expressive-style spacing. Financial Health Summary appears as a period-end popup, not as a permanent Analysis card.

### Exports

Koinly supports CSV export, PDF export, filter-aware export data, shared export files, and summaries based on active filters.

### Settings

Settings includes theme, currency, currency symbol/code, prefix/suffix placement, number separators, daily reminder time, default account, default expense category, default income category, default date filter, Savings suggestion profile, export, Load backup, Account & sync, Updates, About, privacy policy, terms, and licenses.

### Hidden Settings

Hidden Settings keeps secondary controls away from the main workflow. Examples include defaults, reorder tools, and backup tools.

---

## Online data sync

Koinly now uses account-based, local-first online sync.

The active user flow is:

1. Open Settings.
2. Open Account & sync.
3. Create an account or sign in.
4. Continue using Koinly normally.

Login always signs in, downloads the cloud copy as the source of truth, creates
a safety backup, and fully overwrites local finance data on that device. During
first setup, login also completes setup and opens the app. Create account still
returns to the setup pages after authentication so a new user can finish local
setup before adopting the device data into the new cloud account.

The Accounts setup page can also be skipped for fully empty local use. Skipping
accounts removes the untouched Cash, Card, and Bank Account placeholders, saves
that choice locally, and cleans those placeholders again if an older install,
seed step, or sync pass tries to bring back the exact untouched starter set.

The build-time `KOINLY_SYNC_API_BASE_URL` remains the default service. In
**Account & sync**, users can instead select **Self-hosted**, validate their
own Worker URL, and use it for all account and synchronization requests.

Normal app operations save to local SQLite first, update the UI immediately, and add an operation to the local `sync_outbox`. The background coordinator batches pending operations, pushes them to the Worker, pulls remote changes by server cursor, and applies them locally.

Account & sync separates destructive and non-destructive actions:

- **Restore cloud copy** downloads the account cloud data and fully overwrites
  local finance data on this device after confirmation.
- **Upload local changes** pushes pending local edits and then checks cloud
  changes.
- When a local backup restore is waiting to become the cloud source of truth,
  this button changes to **Upload restored data** and retries the full cloud
  replacement upload.

Sync status uses explicit stages such as checking local changes, downloading
cloud copy, overwriting local data, applying cloud changes, synced, pending,
and error states. The last successful sync timestamp is shown with the sync
card/status.

Backup restore is intentionally stronger than a normal incremental edit. After
restore, Koinly uploads the restored local data as an authoritative cloud
replacement when the user is signed in. Other devices on the same account
receive a reset marker, clear their local finance data, and then apply the
cloud copy so the restored backup fully overwrites local data.

No Turso database token is stored in Flutter. The app talks to:

```text
Koinly Flutter -> Cloudflare Worker -> Turso
```

The older manual snapshot-style sync code and `backend/cloudflare-turso/` reference backend are retained as legacy reference material, but Account & sync is the normal multi-device path.

---

## Self-Hosted Cloud Sync

Self-hosting is optional. Existing users can leave **Default** selected and
continue using the Worker compiled into the app. A self-hosted setup keeps
Turso credentials in the Worker and sends the Flutter app only the public
Worker URL.

### 1. Fork and enable the deployment workflow

1. Fork this repository on GitHub.
2. Open the fork's **Actions** tab and enable workflows if GitHub asks.
3. Open **Settings > Secrets and variables > Actions** in the fork.
4. Add the repository secrets listed below.
5. Run **Actions > Deploy Sync Worker > Run workflow**. Later pushes that
   change `cloud/worker/**` or the deployment workflow redeploy automatically.

Do not put tokens in `wrangler.toml`, source files, workflow YAML, issues, or
build logs.

### 2. Create the Turso database

Install and sign in to the [Turso CLI](https://docs.turso.tech/cli/introduction),
then run:

```bash
turso db create koinly-sync
turso db show koinly-sync --url
turso db tokens create koinly-sync
```

Save the URL as `TURSO_DATABASE_URL` and the full-access database token as
`TURSO_AUTH_TOKEN`. The Worker needs write access. The deployment workflow
applies `cloud/worker/schema.sql` automatically; the schema is idempotent and
does not erase existing sync data when redeployed.

### 3. Create Cloudflare credentials and choose the Worker name

Create a Cloudflare API token using the **Edit Cloudflare Workers** template,
scope it to the account that will own the Worker, and copy that account's ID.
Cloudflare's [GitHub Actions guide](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/)
explains both values.

Choose a unique `CLOUDFLARE_NAME`, for example:

```ini
CLOUDFLARE_NAME=my-koinly-sync
```

The name must contain 1-63 lowercase letters, numbers, or dashes and cannot
start or end with a dash. GitHub Actions passes it to `wrangler deploy --name`,
so the committed fallback name is never the deployment identity for a fork.
Cloudflare URLs include the account subdomain:

```text
https://my-koinly-sync.<your-account-subdomain>.workers.dev
```

See Cloudflare's [workers.dev naming and URL rules](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/).

### 4. Add the required GitHub Actions secrets

Add every value under **Repository secrets**:

| Secret | Value |
| --- | --- |
| `CLOUDFLARE_NAME` | Worker name, such as `my-koinly-sync` |
| `CLOUDFLARE_API_TOKEN` | Account-scoped Cloudflare deployment token |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID |
| `TURSO_DATABASE_URL` | URL returned by `turso db show ... --url` |
| `TURSO_AUTH_TOKEN` | Full-access token returned by `turso db tokens create` |
| `JWT_SECRET` | Unique random secret of at least 32 characters |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token used to deliver registration keys |
| `REGISTRATION_KEY_CHAT_ID` | Private Telegram user, group, or channel chat ID |
| `REGISTRATION_ADMIN_SECRET` | Different random administrator secret of at least 32 characters |

`CLOUDFLARE_NAME` is not sensitive, so the workflow also accepts it as a
repository variable. Keeping it with the deployment secrets makes the fork
setup a single checklist. Never reuse `JWT_SECRET` as
`REGISTRATION_ADMIN_SECRET`; changing `JWT_SECRET` later invalidates sessions
and makes previously encrypted registration keys unreadable.

### 5. Deploy and find the Worker URL

The **Deploy Sync Worker** workflow:

1. checks for missing values and validates the Worker/secret lengths;
2. typechecks the Worker;
3. applies the Turso schema;
4. uploads runtime credentials as Cloudflare Worker secrets;
5. deploys using `CLOUDFLARE_NAME`;
6. derives the account's exact `workers.dev` URL;
7. checks `/health`; and
8. creates and delivers an active registration key.

On success, the exact URL appears in the workflow log and job summary as
**Worker URL**. Opening `<Worker URL>/health` should return JSON containing:

```json
{
  "service": "koinly-sync",
  "ok": true,
  "databaseReachable": true,
  "schemaReady": true
}
```

### 6. Connect the app

1. Open **Settings > Account & sync**.
2. Under **Cloud sync service**, select **Self-hosted**.
3. Paste the URL reported by GitHub Actions. Paste only the HTTPS origin, with
   no `/health`, path, query, or fragment.
4. Press **Validate and use Worker**.
5. Create an account with the registration key delivered to Telegram, or sign
   in to an account already stored in that Turso database.

The app enables the custom endpoint only after `/health` identifies a Koinly
Worker whose secrets, database connection, and schema are ready. Auth,
refresh, logout, upload, download, automatic foreground sync, and manual sync
then all use that URL.

To return to the built-in service, select **Default** and press **Use default
service**. Changing either direction signs out the current backend session,
because default and self-hosted accounts and tokens are independent. Local
finance data is not deleted by switching; the normal login warning still
applies before downloading and replacing local data.

### Updating or redeploying

- Push Worker changes to `main` or `master` to redeploy automatically.
- Use **Actions > Deploy Sync Worker > Run workflow** to redeploy without a
  source change or after rotating a GitHub secret.
- Keep the same `CLOUDFLARE_NAME` and Turso database to update in place.
- Changing the Worker name creates a different URL; validate and save the new
  URL in every app installation.
- Changing the Turso database points the Worker at a different sync account
  store. Apply the workflow before signing in from the app.

### Self-hosted troubleshooting

- **Missing secret:** add the exact name shown by the workflow under
  **Settings > Secrets and variables > Actions**, then rerun it.
- **Cloudflare authentication error / code 10000:** recreate the token with
  the Edit Cloudflare Workers template, scope it to the correct account, and
  confirm `CLOUDFLARE_ACCOUNT_ID` belongs to that account.
- **Invalid Worker name:** use only lowercase letters, numbers, and internal
  dashes; keep it at 63 characters or fewer.
- **Turso schema or connection failure:** regenerate a full-access Turso token,
  verify the database URL, and rerun the workflow so `schema.sql` is applied.
- **Worker health check fails:** open `/health`; `configured: false` means a
  Worker secret is missing, `databaseReachable: false` points to Turso
  credentials/network access, and `schemaReady: false` means schema setup did
  not complete.
- **Registration key delivery fails:** confirm the bot token and chat ID, add
  the bot to the target group/channel if applicable, then rerun the workflow or
  use the protected registration-key retry endpoint documented below.
- **The app rejects the URL:** use `https://`, remove `/health` and trailing
  paths, confirm `/health` returns the four values above, and check device
  network or TLS filtering.
- **Login fails after switching services:** create or use an account on the
  selected backend; accounts from the default service are not copied to a
  self-hosted Turso database.

---

## Backup and restore

Backup files use `.koinlybackup`. Backup includes local app data and preferences. Restore replaces local data with backup contents. Local-only use does not require a sync account. If a sync account is signed in, restore automatically uploads the restored copy to cloud sync; if not signed in, the upload remains pending until sync is configured.

When Koinly starts with no accounts, Home shows quick recovery actions for
adding an account, restoring a backup, or signing in to restore the cloud copy.

---

## Screenshots

| Home | Transactions |
| --- | --- |
| ![Home](assets/images/readme/home.png) | ![Transactions](assets/images/readme/transactions.png) |

| Categories |
| --- |
| ![Categories](assets/images/readme/categories.png) |

| Analysis |
| --- |
| ![Analysis](assets/images/readme/analysis.png) |

---

## Tech stack

| Layer | Technology |
| --- | --- |
| UI | Flutter |
| Language | Dart |
| State | Provider |
| Local database | SQLite |
| Android database | `sqflite` |
| Desktop database | `sqflite_common_ffi` |
| Charts | `fl_chart` |
| PDF export | `pdf` + `printing` |
| File picker | `file_picker` |
| Sharing | `share_plus` |
| Secure storage | `flutter_secure_storage` |
| Notifications | `flutter_local_notifications` |
| Time zones | `timezone` |
| Firebase | Analytics + Crashlytics |
| HTTP | `http` for Worker API sync |
| MongoDB | `mongo_dart` retained for legacy sync code |
| IDs | `uuid` |

---

## Project structure

```text
.
├── .github/
│   └── workflows/
│       └── build-android-apks.yml
├── android/
│   └── app/
├── assets/
│   ├── icons/
│   └── images/
├── backend/
│   └── cloudflare-turso/
├── lib/
│   └── main.dart
├── tools/
│   └── windows/
├── pubspec.yaml
├── analysis_options.yaml
├── README.md
└── LICENSE
```

The app is currently implemented mainly in `lib/main.dart`. GitHub Actions can regenerate platform files where needed. The Windows workflow generates Windows platform files before packaging. The installer artifact remains `KoinlySetup.exe`.

---

## Data model overview

The app stores local data for accounts, categories, transactions, budgets, savings suggestion profile, daily savings suggestion seen status, settings/preferences, backup metadata, and sync metadata.

Important classification fields include transaction type, account IDs, category ID, transfer target, created date/time, reminder status, and budget scope.

---

## Requirements

Android:
- Flutter stable
- Java 17
- Android SDK/build tools
- NDK configured by workflow
- Gradle wrapper restored/configured by workflow

Windows:
- Flutter stable
- Windows desktop support
- Visual Studio Build Tools with Desktop C++ workload
- Inno Setup in CI
- optional code signing certificate

---

## Local setup

Install dependencies:

```bash
flutter pub get
```

Run Android:

```bash
flutter run
```

Run Windows:

```bash
flutter config --enable-windows-desktop
flutter run -d windows
```

Build universal APK:

```bash
flutter build apk --release
```

Build ARM32/ARM64 APKs:

```bash
flutter build apk --release --split-per-abi
```

Build Windows release:

```bash
flutter build windows --release
```

---

## GitHub Actions build

Workflow:

```text
.github/workflows/build-android-apks.yml
```

The workflow builds:

```text
artifacts/Koinly-v<version>-universal.apk
artifacts/Koinly-v<version>-arm32.apk
artifacts/Koinly-v<version>-arm64.apk
artifacts/Koinly-v<version>-x86_64.apk
artifacts/Koinly-v<version>.aab
artifacts/Koinly-v<version>-Setup.exe
```

Workflow behavior:
- supports manual dispatch
- supports push to `main` or `master`
- cancels older in-progress release builds on the same branch when a newer push starts
- requires `KOINLY_SYNC_API_BASE_URL` as a GitHub repository secret or variable
- automatically stamps each build version from `github.run_number`
- passes the generated version into Flutter through `KOINLY_APP_VERSION`
- updates Android `versionName` and `versionCode` before APK builds
- updates `pubspec.yaml` before Windows installer packaging
- uses Flutter/Gradle caching where available
- uses `--no-pub` after dependency restore so release builds do not resolve packages repeatedly
- generates the Universal APK from the AAB with bundletool instead of running a separate universal APK compile
- uploads already-compressed APK/EXE artifacts with artifact compression disabled for faster transfer
- requires Android release signing secrets and never stores the release keystore in the repository
- preserves Windows signing support
- generates Windows installer
- publishes APKs, AAB, and the Windows setup installer to a new versioned stable GitHub Release for every build
- patches Windows CMake compatibility where needed
- patches the generated Windows runner title to show `Koinly`

Automatic versioning:

```text
BUILD_NUMBER = 1000 + github.run_number
VERSION_NAME = 1.0.<BUILD_NUMBER>
pubspec.yaml = VERSION_NAME+BUILD_NUMBER
Android versionName = VERSION_NAME
Android versionCode = BUILD_NUMBER
About screen = VERSION_NAME
Windows installer version = VERSION_NAME
```

App build config:

```text
KOINLY_SYNC_API_BASE_URL=https://koinly-sync-worker.koinlytest.workers.dev
```

The installer filename must stay:

```text
KoinlySetup.exe
```

Stable release publishing:

```text
Tag: v1.0.<BUILD_NUMBER>
Release title: Koinly Stable 1.0.<BUILD_NUMBER>
Assets:
- Koinly-v<version>-universal.apk
- Koinly-v<version>-arm32.apk
- Koinly-v<version>-arm64.apk
- Koinly-v<version>-x86_64.apk
- Koinly-v<version>.aab
- Koinly-v<version>-Setup.exe
```

Each successful build creates or updates only its own versioned release. Older
release builds remain available in GitHub Releases instead of being deleted by
the next update.

---

## Release signing

Android release signing is secret-driven. The release `.jks`/keystore and its passwords are **not stored in the repository**. GitHub Actions decodes the keystore into the runner's temporary directory for the build, and Gradle refuses to produce a release build when signing configuration is missing.

Required Android repository secrets:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

For a local release build, set `ANDROID_KEYSTORE_FILE` to the local keystore path and provide `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` in the environment. Do not commit the keystore or `android/key.properties`.

Windows code signing is optional.

Typical Windows secret names:

```text
WINDOWS_CODESIGN_PFX_BASE64
WINDOWS_CODESIGN_PASSWORD
WINDOWS_CODESIGN_TIMESTAMP_URL
```

If Windows signing is not configured, the installer still builds, but Windows may show SmartScreen warnings.

---

## Cloudflare + Turso backend

Active sync Worker folder:

```text
cloud/worker/
```

It contains the Cloudflare Worker API, Turso schema, package configuration, and deployment reference files.

Backend files:

```text
cloud/worker/src/index.ts
cloud/worker/schema.sql
cloud/worker/package.json
cloud/worker/wrangler.toml
cloud/worker/wrangler.toml.example
```

Worker runtime secrets:

```text
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
TELEGRAM_BOT_TOKEN
REGISTRATION_KEY_CHAT_ID
REGISTRATION_ADMIN_SECRET
```

GitHub Actions deployment expects all deployment values to be stored as
repository secrets:

```text
CLOUDFLARE_NAME
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
TELEGRAM_BOT_TOKEN
REGISTRATION_KEY_CHAT_ID
REGISTRATION_ADMIN_SECRET
```

The deploy workflow uses `CLOUDFLARE_NAME` as the Wrangler deployment name and
passes the database, authentication, registration-key, and Telegram values to
Cloudflare as Worker secrets with `wrangler deploy --secrets-file`, so you can
manage all deploy-time values from GitHub repo Settings > Secrets and variables
> Actions.

The same workflow also applies `cloud/worker/schema.sql` to Turso before
deploying the Worker. The schema is idempotent, so rerunning the workflow keeps
existing data and only creates missing tables/indexes.

The Cloudflare API token should use the `Edit Cloudflare Workers` template
for the target account. If you create a custom token manually, include:

```text
Account  > Workers Scripts   > Edit/Write
Account  > Account Settings  > Read
User     > User Details      > Read
User     > Memberships       > Read
```

Add `Zone > Workers Routes > Edit/Write` too if you use Worker routes or a
custom domain. If deploy fails with Cloudflare authentication code `10000`,
replace the GitHub `CLOUDFLARE_API_TOKEN` secret with a token that has these
permissions.

Deploy from terminal:

```bash
cd cloud/worker
npm ci
npm run schema:apply
npx wrangler deploy --name "$CLOUDFLARE_NAME"
```

After deploy, open the Worker URL in a browser. `/` should return a JSON
service summary and `/health` should report `ok: true`, `databaseReachable:
true`, and `schemaReady: true`. The Worker also runs the idempotent schema
bootstrap before auth/sync requests, so missing tables are created
automatically if the GitHub Actions schema step was skipped.

### Invite-only registration

Creating a sync account requires the one active, single-use registration key.
The Worker validates and consumes that key inside the same database transaction
that creates the user. A successful registration marks the previous key
`USED`, creates the next cryptographically random key, stores its SHA-256 hash
plus an AES-GCM encrypted delivery copy, and sends the new plaintext key to the
configured Telegram chat. Used, revoked, and expired keys remain in the audit
ledger and can never become active again.

Add these three repository secrets before deploying:

```text
TELEGRAM_BOT_TOKEN          # BotFather token
REGISTRATION_KEY_CHAT_ID    # target Telegram user/group/channel chat ID
REGISTRATION_ADMIN_SECRET   # independent random value, at least 32 characters
```

The normal key lifetime is controlled by the non-secret Worker variable
`REGISTRATION_KEY_TTL_SECONDS`; the included configuration uses 30 days.

The deployment workflow calls the protected `bootstrap` endpoint after each
deploy. It creates and delivers an initial key only when no valid active key
exists, so ordinary Worker deployments do not rotate a still-valid key.

To rotate the active key manually, use the command below. It does not return
the plaintext key; Telegram receives it:

```bash
curl -X POST "https://YOUR-WORKER.workers.dev/v1/admin/registration-key/rotate" \
  -H "Authorization: Bearer $REGISTRATION_ADMIN_SECRET"
```

Protected administrator endpoints:

```text
GET  /v1/admin/registration-key/status
GET  /v1/admin/registration-key/reveal
POST /v1/admin/registration-key/rotate
POST /v1/admin/registration-key/revoke
POST /v1/admin/registration-key/retry-delivery
POST /v1/admin/registration-key/bootstrap
```

Send `Authorization: Bearer REGISTRATION_ADMIN_SECRET` to each endpoint.
`status` never returns the key. `reveal` is the emergency retrieval path for
the current encrypted active key and returns `Cache-Control: no-store`.
`retry-delivery` safely retries Telegram delivery. The Worker also attempts
Telegram delivery up to three times and records delivery status without
rolling back an already-created account.

---

## Legacy sync backend

The old `backend/cloudflare-turso/` snapshot/admin-approval backend is retained as reference material. It is not the normal multi-device sync path.

---

## Online sync user flow

1. User opens Account & sync.
2. The app uses either the default build-time Worker or the validated self-hosted Worker selected in Account & sync.
3. User creates an account with the current single-use registration key, or signs in.
4. Create account adopts existing local data into the new account through the outbox.
5. Login clears local finance data and replaces it with the cloud account data.
6. Local changes are saved immediately and synced automatically in the background.
7. Other signed-in devices quietly sync every 15 seconds while open and once when the app resumes, pulling changes by cursor into local SQLite.
8. A manual Sync now action remains available for troubleshooting.

---

## API endpoints

Backend endpoint definitions are in:

```text
cloud/worker/src/index.ts
```

Endpoint groups include auth registration/login/refresh/logout, initial sync,
push, pull, status, and protected registration-key administration.

---

## Troubleshooting

### Account & sync cannot connect

Check the Worker URL, Turso secrets, `JWT_SECRET`, Telegram registration
secrets, and whether `cloud/worker/schema.sql` has been applied.

### Registration key was not delivered

Check the active key's protected `status` endpoint. Confirm the bot has access
to `REGISTRATION_KEY_CHAT_ID`, then call `retry-delivery`. If Telegram remains
unavailable, use the protected `reveal` endpoint or rotate the active key. Do
not paste keys, bot tokens, or administrator secrets into public logs.

### Sync conflict appears

Koinly records stale-version conflicts locally instead of silently overwriting financial data. Use the newest synced device data as the source of truth before retrying a conflicting local edit.

### Admin panel says unauthorized

Check `ADMIN_KEY`.

### SQLite table errors in backend

Check schema, database credentials, Worker bindings, and deployment target.

### Android build fails after Flutter upgrade

Check Gradle wrapper, Android Gradle Plugin, Kotlin Gradle Plugin warnings, plugin compatibility, Java 17, SDK, and NDK setup.

### Kotlin Gradle Plugin warning

Flutter may warn that the Android app or plugins apply KGP. The current build can still succeed unless Flutter changes enforcement.

### Windows CMake warning

Firebase's bundled Windows C++ SDK may show old CMake policy warnings. The workflow patches Windows CMake files during CI.

### `KoinlySetup.exe` is missing

Check Windows platform generation, Flutter Windows build, Inno Setup, installer script output, and artifact path.

Expected path:

```text
artifacts/KoinlySetup.exe
```

### Firebase build errors

Check:

```text
android/app/google-services.json
```

### Release APK signing problem

Check Android signing secrets and Gradle signing configuration.

---

## License

Apache License 2.0.

See:

```text
LICENSE
```
