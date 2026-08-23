# Changelog

## Unreleased

- Fixed setup-page account create/login so it returns to setup instead of completing onboarding early and bouncing back later.
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
