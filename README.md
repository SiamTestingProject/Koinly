# Koinly Flutter

A local-first personal finance tracker built in Flutter with a polished Material 3 mobile and desktop UI. Koinly helps users manage accounts, transactions, categories, budgets, loans, savings, reminders, reports, exports, and local backups from one Android or Windows app.

![Koinly banner](assets/images/koinly-banner.png)

---

## Current app version

- App version: `1.0.70+71`
- Android `versionName`: `1.0.70`
- Android `versionCode`: `71`
- Windows installer output: `KoinlySetup.exe`
- Every project update must bump `pubspec.yaml`, `android/app/build.gradle`, and `lib/main.dart`.

---

## Project status

| Area | Current implementation |
| --- | --- |
| App framework | Flutter / Dart |
| Platforms | Android and Windows |
| UI system | Material 3 Expressive-style cards, motion, centered popups, adaptive spacing |
| Local database | SQLite via `sqflite` and desktop SQLite FFI |
| State management | `provider` + `ChangeNotifier` |
| Analytics/crash reporting | Firebase Analytics + Crashlytics with optional initialization |
| Online sync | Account-based automatic multi-device sync |
| Sync backend | Cloudflare Worker API |
| Cloud database | Turso, accessed only by the Worker |
| Local sync state | SQLite outbox, cursor, entity versions, and conflict records |
| Backup/restore | Local `.koinlybackup` files |
| CI build | GitHub Actions for Android APKs and Windows installer |
| Android outputs | Universal, ARM32, ARM64 release APKs |
| Windows output | `KoinlySetup.exe` |
| License | Apache License 2.0 |

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
- Material 3 Expressive UI behavior
- Hidden Settings naming
- single-toggle category and loan filters
- account-based automatic multi-device sync
- Financial Health Summary popup behavior
- daily 10 Savings Account suggestion bubbles
- loan repayment reminders and budget alert summary behavior


## Core data rules

Koinly is strict about money classification.

- Income counts only as income.
- Expense counts only as expense.
- Regular transfers are internal.
- Savings transfers are internal and never count as income or expense.
- Given Loans reduce the selected paying account.
- Taken Loans increase the selected receiving account.
- Loan principal movement does not inflate income/expense.
- Loan repayments update loan balance and account balance.
- Bills and subscriptions are tracked separately for reminders and summaries.
- Budget usage comes from real expense category spending.
- Exports follow active filters.

---

## Features

### Accounts

Koinly supports regular accounts, credit accounts, and Savings accounts. Users can create, edit, delete, reorder, color, and icon-tag accounts. Account balances appear across Home and account pages. Savings balances are kept separate from normal operating balances.

### Transactions

Koinly supports income, expense, and transfer transactions with date/time, amount, account, category, and notes. Filters support date range, account, category, and transaction type. Transfer records avoid category double counting. Savings movements stay out of income/expense totals.

### Categories

Income and expense categories are managed from one page. Expense/Income uses one toggle button. Category cards use icons and colors. Category detail pages show real category transactions only. Transfer and Savings transfer rows are excluded from category spending pages.

### Budgets

Budgets support monthly limits, category scope, account scope, progress tracking, remaining budget, and alert levels. Status can be safe, warning, near limit, limit reached, or overspent. Budget data is included in Financial Health Summary.

### Loans

Loans support Given Loans and Taken Loans. Given/Taken uses one toggle button. Open/Completed uses one toggle button. Given Loan means money goes out; Taken Loan means money comes in. Partial repayments, repayment history, overdue highlighting, and loan repayment reminders are supported. Loan activity is included in Financial Health Summary but excluded from normal income/expense totals.

### Savings

Savings has a dedicated Savings Accounts page. Transfers into and out of Savings are internal transfers. Savings activity appears separately in summaries. Savings suggestion profile is available in Settings. The Savings page shows 10 daily mystery `?` suggestion bubbles. Tapping a bubble opens the full suggestion. Checked suggestions are saved for the day. After all 10 are checked, no more appear until the next day.

### Financial Health Summary

Financial Health Summary is not a fixed Analysis page section. It appears automatically after a month or year ends. Users can go through summary pages or skip all. Skipped and reviewed summaries are remembered.

The summary includes income, expenses, net flow, savings transfers, savings balance movement, current savings balance, loans given/taken, repayments paid/received, recurring bills/subscriptions, paid/unpaid/upcoming/overdue bills, loan repayment reminder status, partial repayments, overdue alerts, budget usage, remaining budget, overspent categories, and a health result.

Possible status results include Saved Money, Overspent, Increased Debt, Reduced Debt, Stable Month, Stable Year, and Strong Savings Growth.

Yearly view includes month-by-month income, expense, savings, loans, repayments, bills, budget usage, best month, worst month, highest income month, highest expense month, highest savings month, and most overspent month.

### Reminders

Reminder-related data supports bills, subscriptions, tuition, rent, internet bills, mobile recharge, electricity bills, EMI payments, scheduled payments, loan repayments, partial repayments, and overdue alerts. Reminder status is included in Financial Health Summary.

### Analysis and reports

The Analysis page remains focused on charts and analytics: income/expense charting, cash flow trend, category breakdown, budget usage context, filter-aware summaries, responsive chart cards, and Material 3 Expressive-style spacing. Financial Health Summary appears as a period-end popup, not as a permanent Analysis card.

### Exports

Koinly supports CSV export, PDF export, filter-aware export data, shared export files, and summaries based on active filters.

### Settings

Settings includes theme, currency, currency symbol/code, prefix/suffix placement, number separators, daily reminder time, default account, default expense category, default income category, default date filter, Savings suggestion profile, backup/restore, app lock/security, About, privacy policy, terms, and licenses.

### Hidden Settings

Hidden Settings keeps secondary controls away from the main workflow. Examples include defaults, reorder tools, backup tools, and lock/security options.

---

## Online data sync

Koinly now uses account-based, local-first online sync.

The active user flow is:

1. Open Settings.
2. Open Account & sync.
3. Create an account or sign in.
4. Continue using Koinly normally.

The Cloudflare Worker URL is embedded at build time through the GitHub
Actions/Flutter define `KOINLY_SYNC_API_BASE_URL`; it is not shown as an app
setting.

Normal app operations save to local SQLite first, update the UI immediately, and add an operation to the local `sync_outbox`. The background coordinator batches pending operations, pushes them to the Worker, pulls remote changes by server cursor, and applies them locally.

No Turso database token is stored in Flutter. The app talks to:

```text
Koinly Flutter -> Cloudflare Worker -> Turso
```

The older manual snapshot-style sync code and `backend/cloudflare-turso/` reference backend are retained as legacy reference material, but Account & sync is the normal multi-device path.

---

## Backup and restore

Backup files use `.koinlybackup`. Backup includes local app data and preferences. Restore replaces local data with backup contents. Local-only use does not require a sync account.

---

## Screenshots

| Home | Transactions |
| --- | --- |
| ![Home](assets/images/readme/home.png) | ![Transactions](assets/images/readme/transactions.png) |

| Categories | Loans |
| --- | --- |
| ![Categories](assets/images/readme/categories.png) | ![Loans](assets/images/readme/loans.png) |

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
| Biometrics/device auth | `local_auth` |
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

The app stores local data for accounts, categories, transactions, budgets, loans, repayments, loan repayment reminders, savings suggestion profile, daily savings suggestion seen status, settings/preferences, backup metadata, and sync metadata.

Important classification fields include transaction type, account IDs, category ID, loan metadata, transfer target, created date/time, reminder status, and budget scope.

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
artifacts/koinly-universal-release.apk
artifacts/koinly-armeabi-v7a-release.apk
artifacts/koinly-arm64-v8a-release.apk
artifacts/KoinlySetup.exe
```

Workflow behavior:
- supports manual dispatch
- supports push to `main` or `master`
- requires `KOINLY_SYNC_API_BASE_URL` as a GitHub repository secret or variable
- preserves Android signing support
- preserves Windows signing support
- generates Windows installer
- patches Windows CMake compatibility where needed

App build config:

```text
KOINLY_SYNC_API_BASE_URL=https://koinly-sync-worker.koinlytest.workers.dev
```

The installer filename must stay:

```text
KoinlySetup.exe
```

---

## Release signing

Android release signing support is preserved.

Typical Android secret names:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

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
```

GitHub Actions deployment expects all deployment values to be stored as
repository secrets:

```text
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
```

The deploy workflow passes `TURSO_DATABASE_URL`, `TURSO_AUTH_TOKEN`, and
`JWT_SECRET` to Cloudflare as Worker secrets with `wrangler deploy
--secrets-file`, so you can manage all deploy-time values from GitHub repo
Settings > Secrets and variables > Actions.

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
npm install
npm run schema:apply
npx wrangler deploy
```

After deploy, open the Worker URL in a browser. `/` should return a JSON
service summary and `/health` should report `ok: true` once Worker secrets are
configured. Apply `cloud/worker/schema.sql` to Turso before using the Worker.
The Flutter app needs only the deployed Worker URL in Settings > Account & sync.

---

## Legacy sync backend

The old `backend/cloudflare-turso/` snapshot/admin-approval backend is retained as reference material. It is not the normal multi-device sync path.

---

## Online sync user flow

1. User opens Account & sync.
2. The app uses the Worker URL embedded at build time through `KOINLY_SYNC_API_BASE_URL`.
3. User creates an account or signs in.
4. Existing local data is adopted into the account through the outbox.
5. Local changes are saved immediately and synced automatically in the background.
6. Other signed-in devices pull changes by cursor and update their local SQLite database.
7. A manual Sync now action remains available for troubleshooting.

---

## API endpoints

Backend endpoint definitions are in:

```text
cloud/worker/src/index.ts
```

Endpoint groups include auth registration/login/refresh/logout, initial sync, push, pull, and status.

---

## Troubleshooting

### Account & sync cannot connect

Check the Worker URL, Turso secrets, `JWT_SECRET`, and whether `cloud/worker/schema.sql` has been applied.

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
