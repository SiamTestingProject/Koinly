# Changelog

## Unreleased

### Added

- Added server-enforced, invite-key-based account registration with one active single-use key, atomic consumption/rotation, expiration, revocation, and an auditable Turso key ledger.
- Added automatic Telegram delivery for each newly rotated registration key, delivery retry tracking, and protected administrator status/reveal/rotate/revoke/retry endpoints.
- Loans are enabled again with a full workflow for given/taken loans, repayment history, repayment reminders, overdue alerts, account-balance updates, and cloud sync.
- Loan records now include Pursenal-style detail fields for institution/provider, loan account number, agreement number, and interest rate.

### Fixed

- Account signup now rejects missing, invalid, expired, revoked, and previously used registration keys with clear user-facing messages.
- Latest release changelog now publishes only the current update notes instead of the full accumulated development history.
- Loan create/edit and repayment dialogs now show clear user-facing messages when required fields are missing instead of silently doing nothing.

### Changed

- The Create account form now requires a Registration Key and always relies on backend validation; Telegram tokens, chat IDs, and administrator credentials remain deployment secrets.
- Loan screens now use friendlier wording, direct empty-state actions, clearer repayment progress, visible repayment action buttons, and a delete confirmation.
- Added a Pursenal-style Load backup workflow in Settings that opens a file picker, loads a `.koinlybackup` file, replaces local data, and triggers the existing cloud-upload path when signed in.
- Android package/application ID changed from `com.siamapps.koinly` to `com.koinly.siam`.
- Transaction amount entry now uses the normal phone/desktop keyboard instead of Koinly's old custom on-screen keypad.
- Release automation now falls back to only the first/current bullet under each Unreleased heading, so accidental older notes do not flood the newest GitHub Release body.
- Restore/sync wording now treats loans as an active feature instead of hidden legacy data.

### Previous development history

- Long scrolling lists now avoid duplicate row repaint boundaries, unnecessary keep-alive bookkeeping, and semantic index calculations that made Windows scrolling feel choppier.
- Desktop card surfaces now avoid animated container work, heavy shadows, and per-card gradients during normal rendering for smoother Windows scrolling.
- Desktop list preloading was reduced so fast scrolling builds fewer off-screen finance cards at once.
- Login/cloud restore now removes untouched starter Cash/Card/Bank Account placeholders from the restored local copy, even when real cloud data also exists.
- Other signed-in devices now automatically pull cloud changes while the app is open and whenever the app resumes, so new transactions appear across devices without manual restore.
- Android no longer reopens the package installer for a downloaded update after that same version is already installed.
- Made Account & sync uploads more reliable by giving full restore uploads a longer request timeout and replacing raw timeout exceptions with clean user-facing messages.
- Prevented Upload restored/local changes from appearing to do nothing while a background sync retry is already running.
- Login from setup or Account & sync now always treats cloud data as the source of truth and fully replaces local finance data on the device.
- Release notes are grouped by current changes, additions, removals, and fixes so the in-app updater shows only the useful “what changed in this update” text.
- Renamed the Account & sync upload button to “Upload restored data” whenever a restored local backup still needs to become the cloud source of truth.
- Hid the Account & sync backend-configuration explanation card and the restore/upload help paragraph to keep the sync page cleaner.
- Reduced Cloudflare Worker subrequests during `/v1/sync/replace` by batching snapshot entity/change writes instead of calling Turso several times per entity.
- Removed per-operation sequence lookups from authoritative cloud replace uploads; the app only needs accepted entity versions plus the final server cursor for this flow.
- Hardened the Cloudflare Worker `/v1/sync/replace` endpoint so duplicate snapshot upserts are coalesced by entity before writing to Turso.
- Made replace-sync processed operation writes idempotent, preventing repeated operation IDs from turning cloud overwrite attempts into 500 responses.
- Added sanitized Worker-side logging for unexpected internal errors so future Cloudflare logs show the useful failure reason.
- Fixed Android release builds on newer Flutter SDKs by hiding Flutter's `Category` and `Summary` annotation exports where they collided with Koinly finance models.
- Fixed clean ZIP packaging on Windows so entries use GitHub-compatible `/` paths instead of literal backslash filenames.
- Ensured workflow files package as `.github/workflows/*.yml`, allowing GitHub Actions to detect them after upload.
- Continued Phase 13 source-structure cleanup by extracting shared icon lookup/rendering helpers into `lib/icon_helpers.dart`.
- Reduced `lib/main.dart` further by moving reusable icon glyph and icon bubble UI helpers out of the main app file.
- Continued Phase 12 source-structure cleanup by extracting reusable Koinly branding widgets into `lib/branding_widgets.dart`.
- Moved the shared `firstOrNull` collection extension into `lib/collection_utils.dart`.
- Continued Phase 11 source-structure cleanup by extracting `ReminderService` into `lib/reminder_service.dart`.
- Moved legacy Cloudflare sync, account sync API, and MongoDB snapshot sync helpers into `lib/sync_services.dart`.
- Removed notification/timezone/MongoDB implementation details from `lib/main.dart`, leaving the app controller/UI to consume service APIs.
- Continued Phase 10 source-structure cleanup by extracting preference/secure credential stores into `lib/persistence_stores.dart`.
- Moved shared sync error/session data types into `lib/sync_models.dart` so future sync-service extraction can happen without touching UI code.
- Continued Phase 9 source-structure cleanup by extracting shared UI foundation primitives into `lib/ui_foundation.dart`.
- Moved responsive breakpoints, motion constants, shape helpers, page transitions, pressable wrapper behavior, and optimized scroll behavior out of `lib/main.dart`.
- Started Phase 8 source-structure cleanup by extracting app configuration/constants into `lib/app_config.dart` and finance data models/helpers into `lib/models.dart`.
- Reduced the size of `lib/main.dart` and began separating the app into clearer layers so future analyzer/editor performance work can continue safely.
- Added Phase 7 validation reliability: the local validation helper now supports explicit timeouts for `flutter pub get`, `flutter analyze --fatal-infos`, and `flutter test`, plus skip flags for each stage.
- Validation now reports likely analyzer timeout causes clearly instead of hanging silently when the current large single-file Flutter app overwhelms analysis.
- Added Phase 6 validation and packaging cleanup so generated packages no longer include worker `node_modules`, Flutter build folders, local output folders, or transient logs.
- Added reusable `tool/package_project.ps1` and `tool/validate_project.ps1` helpers for clean ZIP creation and repeatable local validation.
- Added repository ignore/exclude rules for Worker dependency/cache folders and generated packaging outputs to keep analysis and release archives focused on source files.
- Added Phase 5 privacy-safe diagnostics reports that can be copied or shared from Data health.
- Diagnostics now summarize app version, platform, setup state, local data counts, sync status, pending uploads, conflicts, update state, and health findings without exposing tokens or backend secrets.
- Added Phase 4 diagnostics with Advanced settings → Data health for local data, sync backlog, sync conflicts, and skipped setup leftovers.
- Added a safe Data health cleanup action for untouched starter accounts that remain after the user skipped account setup.
- Added Phase 3 data safety: automatic local safety backups are created before manual restores, legacy cloud restores, full cloud-overwrite syncs, and server reset sync operations.
- Koinly now keeps the newest 3 safety backups and exposes Restore last safety backup in Advanced settings.
- Login/cloud-restore no longer clears local data before a successful cloud download; the app downloads first, saves a safety backup, then overwrites local finance data.
- Started Phase 2 polish with a desktop-default Performance mode that reduces transitions, card animations, update-wave animation, gradients, and heavy shadows.
- Made desktop page headers more compact for a less oversized Windows layout.
- Started Phase 1 polish with clearer sync stages, explicit Restore cloud copy vs Upload local changes actions, and a Home empty-state recovery card for no-account/offline setups.
- Setup Login now signs in, cloud-overwrites local setup/default data, completes setup, and opens the app immediately.
- Persisted the Accounts setup Skip choice and added a safe cleanup for old installs where the untouched Cash/Card/Bank Account starter placeholders remained visible after skipping.
- Fixed setup-page Create account so it returns to setup instead of completing onboarding early and bouncing back later.
- Restore now automatically schedules an authoritative cloud upload when signed in, so restored data becomes the cloud source of truth.
- Added account-sync replace support so other devices fully clear local finance data before applying a restored cloud copy.
- Removed the Home Quick actions block for a cleaner dashboard.
- Fixed the onboarding account setup Skip action so untouched starter accounts are removed instead of staying in the app.
- Reduced route/tab motion and expensive background glow layers for smoother Android and Windows performance.
- Temporarily hid the user-facing Loans feature while preserving legacy storage compatibility for a future re-add.
- Optimized Android release CI by generating the Universal APK from the AAB instead of running a duplicate universal APK build.
- Added a GitHub Releases-based in-app updater.
- Added Settings → Updates with installed version, latest release, update status, release date, and GitHub release changelog.
- Added Android APK architecture selection for ARM64, ARM32, x86_64, and Universal builds.
- Added in-app Android APK downloading with live progress, speed, downloaded size, and animated wave progress.
- Added Android installer handoff with FileProvider content URI support and install-from-this-source permission handling.
- Added Windows update handling that prefers installer assets before falling back to the GitHub release page.
- Updated release automation to publish semantic-version assets and use changelog text for release notes.
