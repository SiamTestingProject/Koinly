# Koinly — Loan System: Full Implementation Plan

**Status:** Ready to implement · **Target:** Flutter app in this repo (Android + Windows) · **Branch:** `arena/01a047ad-koinly`

> How to use this document: it is written as a **standalone implementation brief**. You can paste the
> whole file into ChatGPT / Claude / Cursor as the task prompt — it contains the verified repo facts,
> the exact edit sites, the data model, the business rules, the UI spec, and the phased checklist.
> A condensed copy‑paste prompt is also included in **§16**.

---

## 1. Verified project context (read this before changing anything)

These facts were confirmed by reading the actual source at commit `229a6a5` on branch `arena/01a047ad-koinly`.
Do not re-derive them; trust them, but re-verify the line numbers with `grep -n` before editing
(line numbers drift as code changes).

### 1.1 Stack

| Item | Value |
| --- | --- |
| Framework | Flutter, Dart `>=3.5.0 <4.0.0` (Material 3, adaptive) |
| State | `provider` ^6.1.2 — single `AppController extends ChangeNotifier` |
| Storage | `sqflite` + `sqflite_common_ffi` (desktop) + `sqlite3`; file `koinly_flutter.db` |
| Sync | Outbox in SQLite → HTTPS → Cloudflare Worker (`cloud/worker/src/index.ts`) → Turso/D1 |
| Platforms | Android (APK/AAB), Windows x64. Web is **not** supported |
| Other deps | `intl`, `uuid`, `fl_chart`, `pdf`, `printing`, `share_plus`, `file_picker`, `flutter_local_notifications`, `flutter_secure_storage`, `http`, `mongo_dart`, `timezone`, `firebase_core/analytics/crashlytics` |
| Version | `pubspec.yaml` `1.0.1038+82`; `app_config.dart` `appVersion = '1.0.1038'` |

### 1.2 File map

```
lib/
  main.dart              13,908 lines — MONOLITH: DB, all models usage, controller, every screen
  models.dart                 591 — Account, Category, MoneyTransaction, Budget, DataHealth*, Summary
  app_config.dart              34 — colors (kSleek*), tab index constants, platform flags
  ui_foundation.dart          146 — AppBreakpoints, AppMotion, AppShapes, MotionPressable
  icon_helpers.dart           178 — iconFor(name), iconGlyph(), iconBubble(ctx, name, hex, size)
  persistence_stores.dart      65 — PrefsStore (SharedPreferences), SecureCredentialStore
  sync_services.dart          476 — CloudSyncService, MongoDbSyncService, KoinlySyncApi
  sync_models.dart             29 — SyncAuthSession, CloudSyncException
  update_service.dart         516 — GitHub release update flow (not relevant to loans)
  reminder_service.dart        57 — ReminderService (Android-only daily notification, id 501)
  collection_utils.dart         3
test/
  multi_device_sync_screen_test.dart
  sync_services_test.dart
  update_service_test.dart
cloud/worker/src/index.ts   — sync API; entity-type agnostic
cloud/worker/schema.sql     — users, refresh_tokens, devices, sync_entities, sync_changes, processed_operations
docs/                        — (new) this folder
```

### 1.3 Exact edit anchors in `lib/main.dart`

| What | Line | Current code |
| --- | --- | --- |
| DB version | 91 | `version: 6,` inside `sql.openDatabase` |
| Schema creation | 106 | `Future<void> _createSchema(sql.Database database)` — idempotent `CREATE TABLE IF NOT EXISTS`; called from `onCreate`, `onUpgrade`, **and** `onOpen` |
| Export tables (backup/cloud payload) | 443 | `final tables = ['accounts','categories','transactions','budgets','budget_accounts','budget_categories'];` |
| Import tables (restore) | 453 | `final tables = ['budget_categories','budget_accounts','budgets','transactions','categories','accounts'];` — delete in this order, insert in `.reversed` |
| Local-activity probe | 468 | `for (final table in ['transactions','budgets'])` |
| Wipe-before-remote-login | 479 | `final tables = ['budget_categories','budget_accounts','budgets','transactions','categories','accounts'];` |
| **Sync whitelist** | 490 | `static const syncTables = ['accounts','categories','transactions','budgets','budget_accounts','budget_categories'];` |
| Backup payload version | 867, 880 | `'version': 4,` (in `createBackup` and `createSafetyBackup`) |
| `AppController` fields | 1093-1096 | `List<Account> accounts; List<Category> categories; List<MoneyTransaction> transactions; List<Budget> budgets;` |
| `reload()` | 2594 | loads the 4 lists, `_rebuildLookupCaches()`, `notifyListeners()`, `queueCloudSync()` |
| `_rebuildLookupCaches()` | 2610 | builds `_accountsById`, `_savingAccounts`, balances, `_categoryIdsByType` |
| CRUD pattern | 2919-2996 | `saveAccount` / `deleteAccount` / `saveBudget` / `addTransaction` … write → `enqueueTableRow` → `reload(queueSync: true)` |
| `checkDataHealth()` | 1346 | builds `DataHealthItem`s; `DataHealthReport` built at ~1433 |
| Tab pages | 3653-3656 | `const HomeDashboardScreen(), const AnalysisScreen(), const TransactionListScreen(), const CategoriesScreen(),` |
| Dock destinations | 3855 | `_FloatingDockNavigation.destinations` — also consumed by `_SideRailNavigation` (line 3827) |
| Home sections | 5334 / 5355 / 5365 / 5387 | `accountsSection`, `budgetSection`, `categorySection`, `startEmptySection` |
| Settings tiles | 10578 | `SettingsScreen` list of `SettingsTile` |
| Helpers | 4746 / 4948 | `showSnack(ctx,msg)`, `showKoinlyPopup<T>(ctx, maxWidth:, maxHeight:, child:)` |

### 1.4 Conventions an implementation must follow

1. **Model shape** (see `lib/models.dart`): `final` fields, required positional constructor,
   `copyWith({...})`, `Map<String,Object?> toMap()`, `static X fromMap(Map<String,Object?>)`,
   enums serialized with `enumName()` / `enumByName(values, raw, fallback)`,
   dates with `dateToDb()` / `dateFromDb()` (epoch millis, `INTEGER`).
2. **Money** is `double` in the DB (`REAL`). Never compare with `==`; use an epsilon (`< 0.005`).
3. **All displayed money** must go through `AppController.format(double)` (line 2674) — it honours
   `amountsHidden`, `currencySymbol`, `currencyPosition`, `useSeparators`. Default currency is **BDT/৳**.
4. **Mutation pattern**: `db write` → `database.enqueueTableRow(table, id)` (or `enqueueDelete`) →
   `reload(queueSync: true)`. Never call `notifyListeners()` manually after a data write.
5. **Sync entity types** are the SQLite table names, and the Worker validates them against
   `/^[a-z_]{2,64}$/` (`cloud/worker/src/index.ts:1036`). Lowercase snake_case only.
6. **Outbox drain order** is `created_at ASC` (`pendingSyncOperations`, line 618) — so when you enqueue
   a parent and its children, **enqueue the parent first**.
7. `_whereForEntity` / `_whereArgsForEntity` / `_entityIdForRow` (lines 718-748) default to `id = ?`.
   Any new table with a single-column `id` primary key works with **no change** to those three methods.
8. Entity versions are per `(entity_type, entity_id)`. There is no cross-entity transaction on the
   server, so a loan and its payments sync independently (see §11 risk R5).
9. Tests use `package:flutter_test` + `testWidgets` / `test`. `test/multi_device_sync_screen_test.dart`
   does **not** assert on tab count, so adding a nav tab will not break it.

### 1.5 Reusable UI kit (do not invent new design primitives)

| Need | Use |
| --- | --- |
| Screen frame | `PageScaffold(title:, subtitle:, actions:, child:)` |
| Content width | `ResponsiveContent(child:)` / `ResponsiveListContent` |
| Cards | `ExpressiveCard(child:, padding:)` |
| Section titles | `SectionHeader('Title', trailing:)` |
| Empty states | `EmptyCard(icon:, title:, body:, action:, actionLabel:)` |
| Segmented control | `SleekPillSelector<T>(options:, value:, onChanged:)` with `SleekPillOption<T>(value:, label:, icon:)` |
| Pickers / dropdowns | `AppleSelectionField` + `SelectionOption<T>(...)` |
| Bottom-sheet forms | `showKoinlyPopup<T>(context, maxWidth: 560, maxHeight: 700, child:)` |
| Toast | `showSnack(context, message)` |
| Icon tile | `iconBubble(context, iconName, hexColor, size: 50)` |
| Motion / radii | `AppMotion.fast|medium|slow`, `AppShapes.small|medium|large|dialog` |
| Colors | `kSleekIncome` `#27D17F` (to collect), `kSleekExpense` `#FF5353` (to pay), `kSleekWarning` `#F59E0B` (overdue), `kSleekAccent` `#00D7E8`, `kSleekMuted` `#90A4AD` |

Available icon keys include: `wallet, cash, savings, bank, money, exchange, gift, handshake-free
substitutes (use business / work / favorite), receipt, calculator, person-free (use favorite /
child_care / group-free)`. For loans, prefer existing keys: `'exchange'`, `'money'`, `'cash'`,
`'receipt'`, `'calculator'`, `'gift'`. If a genuinely new key is needed, add one `case` to
`iconFor()` in `lib/icon_helpers.dart` (178 lines, trivial to extend).

---

## 2. Product spec

### 2.1 Goal

Track money you **lend to** people and money you **borrow from** people, with the same care the app
already gives accounts: balances, history, and a clean, friendly UI. Two directions, one ledger.

### 2.2 Vocabulary (use consistently in UI copy and code)

| Term | Meaning |
| --- | --- |
| **Lent** (`direction = lent`) | You gave money out. The other person owes you. Positive for you. |
| **Borrowed** (`direction = borrowed`) | You received money. You owe the other person. Negative for you. |
| **Outstanding** | `principal + accrued interest − payments received`. Never shown negative; overpayment shown separately. |
| **Settled / Closed** | Outstanding is zero, or the user marked it closed. |
| **Overdue** | Active loan with `due_date` in the past and outstanding > 0. |

### 2.3 Feature set

**Core (Phase 1-3, must ship)**
- F1 Contacts: name (+ optional phone/note), auto-colour avatar, reused across many loans.
- F2 Create a loan: direction, contact, amount, date, optional note.
- F3 Optional interest: none / simple / compound with rate + period (daily, monthly, yearly, flat).
- F4 Optional installment plan: N payments → auto-computed EMI shown to the user.
- F5 Optional due date → overdue badge + reminder.
- F6 Record payments: any amount, any time; auto-split into interest/principal (user can override).
- F7 Loan detail: progress bar, principal/interest/paid/outstanding, payment history, edit, delete, settle.
- F8 Portfolio home: **To collect**, **To pay**, **Net**, overdue count.
- F9 Optional link to real money movement: pick an account and auto-create the matching
  income/expense transaction so account balances stay truthful.
- F10 Sync + backup + restore + data-health coverage, exactly like accounts/transactions.

**Nice-to-have (Phase 5)**
- F11 Per-contact screen: all loans with that person, net balance, "settle all".
- F12 Share a plain-text statement ("Rahim, you still owe ৳2,300 as of 28 Aug 2026").
- F13 Loan CSV/PDF export reusing `ExportService` / `showExportSheet`.
- F14 Search + filter (by contact, by status, by date).
- F15 Due-date notifications.
- F16 Settle-up suggestion: "You owe Rahim ৳500 but he owes you ৳1,200 — net ৳700 to you."

### 2.4 User flows (the "very user friendly" bar)

**A. First-time, 3 taps to a recorded loan**
```
Home → "Loans" tile  →  (+) New loan  →  [Lent ▾] Rahim ▾  ৳5,000  Save
```
Defaults that make this fast: direction defaults to whatever tab you are on; date defaults to today;
interest defaults to **none**; "record in account" defaults to the global toggle; contact picker
allows typing a brand-new name inline ("Rahim (new)").

**B. Collecting money back, 2 taps**
```
Loans → tap the loan  →  Record payment  →  [ ৳5,000 ] Full · Half · Custom  → Save
```
Quick-fill chips: **Full remaining**, **Half**, **EMI amount** (when an installment plan exists),
**Round up to ৳100**. After saving: "Payment recorded. ৳0 outstanding. Loan marked as settled."
(offer Undo for 5 s via `showSnack`).

**C. Understanding where you stand, 0 taps**
Home tile shows `Net +৳12,400` with subtitle `3 people owe you · 1 you owe · 1 overdue`.

**D. Copy that reads like a human, not a ledger**
- "Rahim will pay you ৳2,300" / "You will pay Rahim ৳2,300"
- "Due in 6 days" / "4 days overdue"
- Empty state: "No loans yet. Tap **New loan** the first time you lend or borrow money."
- Never show raw interest jargon; show "Interest ৳120 (10% per year, 44 days)".

### 2.5 Three decisions — pick before coding

| # | Decision | **Recommended** | Alternative |
| --- | --- | --- | --- |
| D1 | Do loan movements touch account balances? | **Yes, opt-in per action**, default ON (pref `loanRecordTransactionsByDefault = true`). Creates a real `MoneyTransaction` + adjusts the account. | Off by default (loans live in a parallel universe) — simpler, but balances lie. |
| D2 | Where does Loans live? | **Home section tile + pushed route** (no new dock tab). | 5th dock tab (see §9.6 for the exact 3-line change). |
| D3 | Interest accrual basis | **Simple → on original principal. Compound → on remaining balance after payments.** Accrual runs to "now" (or due date, whichever the user set) and stops when settled. | Freeze interest at due date (adds a flag; defer). |

---

## 3. Architecture & new files

`lib/main.dart` is already 13.9k lines. **Do not** add ~1,500 more lines to it. Put the feature in a
new folder and leave only thin wiring in `main.dart` (~40 lines total).

```
lib/loans/
  loan_models.dart        ~260 lines  LoanContact, Loan, LoanPayment + enums + toMap/fromMap
  loan_computation.dart   ~220 lines  PURE math. Imports only dart:convert/intl-free. No Flutter.
  loan_repository.dart    ~200 lines  SQL for the 3 tables + cross-entity writes (loan ↔ account ↔ tx)
  loan_controller.dart    ~180 lines  ChangeNotifier-free mixin-ish helper OR plain extension on AppController
  loan_widgets.dart       ~260 lines  LoanSummaryHero, LoanTile, LoanProgress, LoanMetricRow, LoanFilterPills
  loan_screens.dart       ~900 lines  LoansScreen, LoanDetailScreen, PersonLoansScreen
  loan_sheets.dart        ~500 lines  LoanEditorSheet, LoanPaymentSheet, ContactPickerSheet
  loan_reminders.dart     ~120 lines  due-date scheduling on top of ReminderService
test/loans/
  loan_computation_test.dart
  loan_repository_test.dart
  loan_sync_wiring_test.dart
```

**Wiring surface inside `main.dart` (the only edits to that file):**

1. `import 'loans/loan_models.dart'; import 'loans/loan_repository.dart'; import 'loans/loan_screens.dart';`
2. `AppController`: field `late final LoanRepository loanRepo;` (init in `initialize()`),
   3 list fields, 3 lines in `reload()`, ~4 lines in `_rebuildLookupCaches()`, ~8 public methods.
3. `_createSchema`: 3 `CREATE TABLE` + 4 `CREATE INDEX` blocks (paste from §4.1).
4. Four table-list constants (§7).
5. Home section tile (§9.2), route push, optional settings tile, optional dock tab.
6. `checkDataHealth`: 4 new checks (§10).

### 3.1 Repository injection (required for testability)

```dart
class LoanRepository {
  LoanRepository(this._db);              // Future<sql.Database> Function()
  final Future<sql.Database> Function() _db;
  // every method: final db = await _db();
}
// production:  LoanRepository(() => koinlyDatabase.db)
// test:        LoanRepository(() async => inMemoryDb)   // databaseFactoryFfi, path ':memory:'
```
Do **not** read `getDatabasesPath()` inside the repository — that would make it untestable.

---

## 4. Data model

### 4.1 SQLite (add to `_createSchema`, bump `version: 6` → `version: 7`)

```sql
CREATE TABLE IF NOT EXISTS loan_contacts(
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  phone       TEXT NOT NULL DEFAULT '',
  note        TEXT NOT NULL DEFAULT '',
  icon_name   TEXT NOT NULL DEFAULT 'exchange',
  icon_color  TEXT NOT NULL DEFAULT '#FBC879',
  archived    INTEGER NOT NULL DEFAULT 0,
  created_on  INTEGER NOT NULL,
  updated_on  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS loans(
  id                        TEXT PRIMARY KEY,
  contact_id                TEXT NOT NULL,
  direction                 TEXT NOT NULL,              -- 'lent' | 'borrowed'
  principal                 REAL NOT NULL,
  interest_type             TEXT NOT NULL DEFAULT 'none',   -- 'none' | 'simple' | 'compound'
  interest_rate             REAL NOT NULL DEFAULT 0,        -- percent, per interest_period
  interest_period           TEXT NOT NULL DEFAULT 'monthly',-- 'daily' | 'monthly' | 'yearly' | 'flat'
  start_date                INTEGER NOT NULL,
  due_date                  INTEGER,                        -- nullable
  installment_count         INTEGER,                        -- nullable; NULL = open-ended
  interest_accrual_stop     TEXT NOT NULL DEFAULT 'settled',-- 'settled' | 'due_date'
  note                      TEXT NOT NULL DEFAULT '',
  status                    TEXT NOT NULL DEFAULT 'active', -- 'active' | 'closed' | 'written_off'
  closed_on                 INTEGER,
  disbursal_transaction_id  TEXT,                           -- link to auto-created MoneyTransaction
  created_on                INTEGER NOT NULL,
  updated_on                INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS loan_payments(
  id                  TEXT PRIMARY KEY,
  loan_id             TEXT NOT NULL,
  amount              REAL NOT NULL,          -- == interest_component + principal_component
  interest_component  REAL NOT NULL DEFAULT 0,
  principal_component REAL NOT NULL DEFAULT 0,
  paid_on             INTEGER NOT NULL,
  note                TEXT NOT NULL DEFAULT '',
  transaction_id      TEXT,                   -- link to auto-created MoneyTransaction
  created_on          INTEGER NOT NULL,
  updated_on          INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_loans_contact      ON loans(contact_id);
CREATE INDEX IF NOT EXISTS idx_loans_status_due   ON loans(status, due_date);
CREATE INDEX IF NOT EXISTS idx_loan_payments_loan ON loan_payments(loan_id, paid_on);
CREATE INDEX IF NOT EXISTS idx_loan_contacts_name ON loan_contacts(name COLLATE NOCASE);
```

Migration notes:
- `onUpgrade` and `onOpen` both call `_createSchema`, and every statement is `CREATE TABLE IF NOT EXISTS`,
  so this is **idempotent and safe**. No `ALTER TABLE` is needed because all three tables are new.
- Bump `version:` to `7` anyway, so the intent is recorded and future `ALTER`s have a home.
- All three entity types (`loan_contacts`, `loans`, `loan_payments`) satisfy the Worker's
  `^[a-z_]{2,64}$` entity-type rule. **No Worker change and no deploy is required.**

### 4.2 Dart models (`lib/loans/loan_models.dart`)

Mirror `lib/models.dart` exactly.

```dart
enum LoanDirection { lent, borrowed }          // enumName → 'lent' / 'borrowed'
enum LoanInterestType { none, simple, compound }
enum LoanInterestPeriod { daily, monthly, yearly, flat }
enum LoanStatus { active, closed, writtenOff } // enumName(writtenOff) == 'writtenOff'  ⚠
enum LoanAccrualStop { settled, dueDate }      // ⚠ see note below
```

> ⚠ `enumName()` in `lib/models.dart` returns `value.toString().split('.').last`, so
> `LoanStatus.writtenOff` serializes to `'writtenOff'` (camelCase) and `LoanAccrualStop.dueDate` → `'dueDate'`.
> Either (a) accept camelCase and keep the DB values `'writtenOff'` / `'dueDate'`, or (b) add tiny
> explicit mappers `loanStatusToDb` / `loanStatusFromDb` that emit `'written_off'` / `'due_date'`.
> **Recommended: (b)** — keeps the database snake_case like every other column value in this app.

```dart
class LoanContact {
  final String id, name, phone, note, iconName, iconColor;
  final bool archived;
  final DateTime createdOn, updatedOn;
  // copyWith, toMap, fromMap  (bool → 1/0, like Budget)
  String get initials;                 // 1–2 chars for the avatar fallback
}

class Loan {
  final String id, contactId, note;
  final LoanDirection direction;
  final double principal, interestRate;
  final LoanInterestType interestType;
  final LoanInterestPeriod interestPeriod;
  final DateTime startDate;
  final DateTime? dueDate;
  final int? installmentCount;
  final LoanAccrualStop interestAccrualStop;
  final LoanStatus status;
  final DateTime? closedOn;
  final String? disbursalTransactionId;
  final DateTime createdOn, updatedOn;

  bool get isLent     => direction == LoanDirection.lent;
  bool get isActive   => status == LoanStatus.active;
  bool get hasInterest => interestType != LoanInterestType.none && interestRate > 0;
}

class LoanPayment {
  final String id, loanId, note;
  final double amount, interestComponent, principalComponent;
  final DateTime paidOn;
  final String? transactionId;
  final DateTime createdOn, updatedOn;
}
```

Derived (never stored — always computed, so it can never drift):

```dart
class LoanComputation {
  final double principal;         // original
  final double interestAccrued;   // interest owed as of `at`
  final double totalDue;          // principal + interestAccrued
  final double totalPaid;         // sum(payment.amount)
  final double interestPaid;      // sum(payment.interestComponent)
  final double principalPaid;     // sum(payment.principalComponent)
  final double outstanding;       // totalDue - totalPaid  (may be negative → overpaid)
  final double overpaid;          // max(0, -outstanding)
  final double progress;          // totalPaid / totalDue clamped 0..1
  final bool   settled;           // outstanding <= 0.005
  final int    daysOverdue;       // 0 when not overdue
  final bool   overdue;
  final double? emiAmount;        // null when installmentCount == null
  final int    paymentsCount;
  final int    installmentsPaid;  // when installmentCount != null
  final DateTime computedAt;
}

class LoanPortfolioSummary {
  final double toCollect, toPay, net, overdueAmount;
  final int activeCount, settledCount, overdueCount, contactCount;
}
```

---

## 5. Business rules (the part that must be exactly right)

### 5.1 Rounding

```dart
double round2(double v) => (v * 100).roundToDouble() / 100;
bool nearZero(double v) => v.abs() < 0.005;
```
- Round **once**, at the point a value is persisted or displayed.
- Compute internally at full `double` precision.
- **Invariant:** `payment.amount == payment.interestComponent + payment.principalComponent` (each
  rounded to 2dp, with the remainder pushed into `principal` so the identity always holds).
  Store both components so the sum is guaranteed; never re-derive components on read.

### 5.2 Interest

Let `P` = principal, `r` = `interestRate / 100`, `at` = evaluation instant
(default `DateTime.now()`, clamped to `>= start_date`).

| `interest_type` | `interest_period` | Accrued interest |
| --- | --- | --- |
| `none` | any | `0` |
| `simple` | `flat` | `P * r` (fixed, whole term; period ignored) |
| `simple` | `daily` | `P * r * (days / 365)` |
| `simple` | `monthly` | `P * r * (days / 30.4375)` |
| `simple` | `yearly` | `P * r * (days / 365)` |
| `compound` | `daily` | `P * ((1 + r/365) ^ days − 1)` |
| `compound` | `monthly` | `P * ((1 + r/12) ^ months − 1)` |
| `compound` | `yearly` | `P * ((1 + r) ^ years − 1)` |
| `compound` | `flat` | `P * r` (compound + flat is meaningless; treat as flat) |

`days = at.difference(startDate).inDays` (whole days, `max(0, …)`).
`months = days / 30.4375`, `years = days / 365`.

**Simple accrues on the original `P`. Compound accrues on the remaining balance after payments.**
Because of this, implement a single **period-by-period simulation** rather than closed forms —
one code path, correct for both, and trivially unit-testable:

```
compute(loan, paymentsSortedAsc, at):
  if type == none:
      interestAccrued = 0
      allocate every payment 100% to principal
      return
  effAt   = (accrualStop == dueDate && dueDate != null) ? min(at, dueDate) : at
  balance = P            # compound accrues on this
  accrued = 0            # interest owed so far
  paidInterest = 0
  step = period-length (daily: 1d, monthly: 1 calendar month, yearly: 1 calendar year, flat: whole term)
  for boundary in boundaries(startDate, effAt, step) + [effAt]:
      # 1) apply every payment with paid_on <= boundary, interest-first
      for p in payments where p.paidOn <= boundary and not yet applied:
          interestOwedNow = accrued - paidInterest
          interestPart    = min(p.amount, max(0, interestOwedNow))
          principalPart   = p.amount - interestPart
          paidInterest   += interestPart
          if compound: balance -= principalPart
      # 2) accrue interest for the elapsed slice
      sliceDays = boundary.difference(previousBoundary).inDays
      rateForSlice = (type == compound)
          ? r * (period == daily ? sliceDays/365 : period == monthly ? sliceDays/365*12/12 : sliceDays/365)
          : r * (period == flat ? 1 : period == daily ? sliceDays/365
                                : period == monthly ? sliceDays/30.4375 : sliceDays/365)
      accrued += (type == compound ? balance : P) * rateForSlice
  # 3) apply any remaining payments (paidOn <= at) interest-first, same as above
  outstanding = P + accrued - totalPaid
```

Keep the slice-rate derivation in one tiny helper `double _rateForSlice(period, sliceDays, r)` and
unit-test it directly. Edge cases to pin with tests: `at < startDate`, `dueDate < startDate`,
zero payments, payments dated before `startDate` (clamp to `startDate`), payments dated after `at`
(must be **excluded**), `installmentCount == 0` (treat as null).

### 5.3 Payment allocation

Default **interest-first** (standard lending practice):
```
interestPart  = min(amount, max(0, accruedInterest − interestPaidSoFar))
principalPart = amount − interestPart
```
The sheet shows the split live ("৳120 interest · ৳880 principal") and lets the user switch to
**principal-only** or enter a custom split. Whatever the user sees is what gets stored.

### 5.4 EMI

Only computed when `installmentCount != null && > 0`. Uses `interestPeriod` to get a monthly rate `i`:
- `monthly` → `i = r / 12` … wait: **rate is already "per period"**, so `i = r` when period is monthly,
  `i = r / 12` when yearly, `i = r * 30.4375` when daily, and flat uses the flat formula.
- Reducing balance: `EMI = P * i * (1+i)^n / ((1+i)^n − 1)`; if `i == 0` → `EMI = P / n`.
- Flat: `EMI = (P + P * r * n_months/12) / n` → simplify to `(P + P*r*termFactor) / n` where
  `termFactor = n` when period is monthly, `n/12` when yearly, `n/30.4375` when daily, `1` when flat.
- EMI is **advisory**: displayed, offered as a quick-fill chip, never enforced.

### 5.5 Status & lifecycle

| Transition | Rule |
| --- | --- |
| → `closed` | automatic when `outstanding <= 0.005` after a payment **or** manual "Mark as settled". Sets `closedOn = now`. |
| `closed` → `active` | manual "Reopen" (or automatically if a payment is deleted and outstanding becomes positive). |
| → `writtenOff` | manual only, from the detail menu. Keeps history, excludes the loan from portfolio totals by default (show behind a "Show written off" toggle). |
| `active` + `dueDate < now` + `outstanding > 0` | `overdue = true`, `daysOverdue = now.difference(dueDate).inDays`. |

Deleting a loan: delete its `loan_payments` rows too, **enqueue each child delete** before the parent
(see §7 note about drain order — actually enqueue parent-first is only required for *creation*; for
deletes, enqueue children first so a partially-drained outbox never leaves orphan payments behind).

### 5.6 Money movement (decision D1)

| Action | `lent` | `borrowed` |
| --- | --- | --- |
| Disbursal (create loan) | `MoneyTransaction(type: expense, from: account, amount: P)` | `MoneyTransaction(type: income, from: account, amount: P)` |
| Repayment (add payment) | `MoneyTransaction(type: income, from: account, amount: payment)` | `MoneyTransaction(type: expense, from: account, amount: payment)` |

- Categories are created on demand with `KoinlyDatabase.ensureCategory(name, type, color, icon)`
  (line 393) — never hardcode an id:
  - expense `Loan given` · icon `exchange` · `#FF9E9E`
  - income `Loan taken` · icon `exchange` · `#9BE7B4`
  - income `Loan repayment received` · icon `receipt` · `#A6E3A1`
  - expense `Loan repayment paid` · icon `receipt` · `#FFB5A0`
- Store the created id on `loans.disbursal_transaction_id` / `loan_payments.transaction_id`.
- Deleting a loan/payment **must not** silently delete the transaction by default. Offer
  "Also delete the linked transaction" in the confirm dialog (default off), then call
  `database.deleteTransaction(id)` so the account balance is corrected.
- Everything runs inside one `database.transaction((txn) { … })`, followed by
  `enqueueRowsForTable('accounts')` and `enqueueTableRow('transactions', tx.id)` — copy the exact
  pattern from `AppController.addTransaction` (line 2947).

---

## 6. Repository API (`lib/loans/loan_repository.dart`)

```dart
class LoanRepository {
  LoanRepository(this._db);
  final Future<sql.Database> Function() _db;

  // reads
  Future<List<LoanContact>> contacts({bool includeArchived = false});
  Future<List<Loan>>        loans({String? contactId, LoanStatus? status});
  Future<List<LoanPayment>> payments({String? loanId});

  // contact
  Future<void> upsertContact(LoanContact c);
  Future<void> deleteContact(String id);                 // caller must cascade (see below)

  // loan
  Future<void> upsertLoan(Loan l);
  Future<void> deleteLoan(String id);                    // also deletes its payments (same txn)
  Future<void> setLoanStatus(String id, LoanStatus status, DateTime? closedOn);

  // payment
  Future<void> insertPayment(LoanPayment p);
  Future<void> deletePayment(String id);

  // cross-entity (single sqlite transaction)
  Future<String?> createLoanWithDisbursal(
      Loan loan, {required String accountId, required String categoryId});
  Future<String?> addPaymentWithTransaction(
      LoanPayment p, {required String accountId, required String categoryId});
  Future<void> deleteLoanCascade(String id, {bool deleteLinkedTransactions = false});
}
```
Every write must also be enqueued by the **caller** (`AppController`), matching the existing
convention — the repository only touches SQL and returns the ids it created.

---

## 7. Sync, backup and lifecycle wiring (checklist — miss one and data is lost)

- [ ] **`syncTables` (main.dart:490)** → append `'loan_contacts', 'loans', 'loan_payments'`
      (parents before children). **Without this, loans silently never sync.**
- [ ] **`exportAll` (main.dart:443)** → append the same three names (any order; this feeds both
      backup files and the cloud payload via `exportCloudPayload`).
- [ ] **`importAll` (main.dart:453)** → child-first delete order:
      `['loan_payments','loans','loan_contacts','budget_categories','budget_accounts','budgets','transactions','categories','accounts']`
      (the existing code inserts `tables.reversed`, so parents are inserted before children).
- [ ] **`clearFinanceDataForRemoteLogin` (main.dart:479)** → same child-first list, otherwise stale
      loans survive a "replace this device with cloud data" wipe and re-upload themselves.
- [ ] **`hasLocalUserActivity` (main.dart:468)** → add `'loans'` to the loop, so a loans-only device
      is still treated as "has data" during the adopt/replace decision.
- [ ] **Backup version (main.dart:867 and 880)** → `'version': 4` becomes `'version': 5`
      (both `createBackup` and `createSafetyBackup`).
- [ ] **Backward-compatible restore.** `importAll` deletes every listed table even when the payload
      lacks that key, so restoring an old v4 backup would wipe loans. Fix: change the signature to
      `importAll(Map<String,dynamic> data, {Set<String> skipTables = const {}})` and in
      `BackupService.restoreBackupFile` (line 916) pass
      `skipTables: ((payload['version'] as num? ?? 0).toInt() < 5) ? {'loan_contacts','loans','loan_payments'} : {}`.
      Also surface it in the confirm copy: "This backup was made before loans existed; your current
      loans will be kept."
- [ ] **Enqueue ordering**: creation → parent first (`loans` then `loan_payments`); deletion →
      children first (`loan_payments` then `loans`), because the outbox drains `created_at ASC`.
- [ ] **Contact delete** must enqueue a `delete` for every child loan and every grandchild payment —
      the server has no cascade.
- [ ] Verify no other place enumerates tables: `grep -n "'accounts'" lib/*.dart` and
      `grep -n "budget_categories" lib/*.dart` to catch any list missed above.

---

## 8. Controller wiring (`AppController`)

```dart
// fields, next to the other lists (main.dart:1093)
late final LoanRepository loanRepo;
List<LoanContact> loanContacts = [];
List<Loan> loans = [];
List<LoanPayment> loanPayments = [];

// private caches, beside _accountsById
Map<String, Loan> _loansById = {};
Map<String, LoanContact> _loanContactsById = {};
Map<String, List<LoanPayment>> _paymentsByLoan = {};

// initialize()
loanRepo = LoanRepository(() => database.db);
```

`reload()` — insert after `budgets = await database.budgets();`:
```dart
loanContacts = await loanRepo.contacts(includeArchived: true);
loans        = await loanRepo.loans();
loanPayments = await loanRepo.payments();
```

`_rebuildLookupCaches()` — append:
```dart
_loansById        = {for (final l in loans) l.id: l};
_loanContactsById = {for (final c in loanContacts) c.id: c};
_paymentsByLoan   = {for (final l in loans) l.id: <LoanPayment>[]};
for (final p in loanPayments) {
  _paymentsByLoan.putIfAbsent(p.loanId, () => <LoanPayment>[]).add(p);
}
for (final list in _paymentsByLoan.values) {
  list.sort((a, b) => a.paidOn.compareTo(b.paidOn));
}
```

Public API (each: write → enqueue → `reload(queueSync: true)`):
```dart
Future<void> saveLoanContact(LoanContact c);
Future<void> deleteLoanContact(String id);                    // blocks if it still has loans
Future<void> saveLoan(Loan loan, {bool recordDisbursal = false, String? accountId});
Future<void> updateLoan(Loan loan);
Future<void> deleteLoan(String id, {bool deleteLinkedTransactions = false});
Future<void> setLoanStatus(String id, LoanStatus status);
Future<void> addLoanPayment(LoanPayment p, {bool recordInAccount = false, String? accountId});
Future<void> deleteLoanPayment(String id, {bool deleteLinkedTransaction = false});

// derived, cheap, recomputed on demand (not cached — depends on "now")
LoanComputation       computationFor(String loanId, {DateTime? at});
LoanPortfolioSummary  get loanSummary;
double                netWithContact(String contactId);
List<Loan>            loansForContact(String contactId);
LoanContact?          contactOf(String? id);
Loan?                 loanOf(String id);
```
`loanSummary` iterates `loans` once, skipping `writtenOff`, summing `computationFor(...).outstanding`
into `toCollect` (lent) or `toPay` (borrowed). Guard: if `loans.isEmpty`, return an all-zero summary
so the Home tile never throws during `loading`.

Preferences (via `prefs` = `PrefsStore`):
- `loanRecordTransactionsByDefault` (bool, default `true`)
- `loanRemindersEnabled` (bool, default `true`)
- `loanShowWrittenOff` (bool, default `false`)
Add the first two to `exportPreferences()` (line 1534) so they follow the user across devices;
they are not in `deviceLocalKeys`, so `importPreferences` will sync them automatically.

---

## 9. UI implementation

### 9.1 Design language

Match the existing screens: `PageScaffold` + `ResponsiveContent`, `ExpressiveCard` sections,
`SectionHeader` dividers, `kSleekIncome` green for money coming to you, `kSleekExpense` red for
money leaving, `kSleekWarning` amber for overdue. Large rounded corners (`AppShapes.medium` = 20),
`fontWeight: FontWeight.w900` titles, `kSleekMuted` subtitles at `bodySmall` + `w700`.
Respect `state.reducedMotion` for animations (default true on desktop).

### 9.2 Home entry point (D2, recommended)

In `HomeDashboardScreen`, after `accountsSection` (main.dart:5334), add:
```dart
final loansSection = <Widget>[
  const SectionHeader('Loans'),
  HomeNavigationTile(
    iconName: 'exchange',
    iconColor: '#FBC879',
    title: 'Loans',
    subtitle: _loanSubtitle(state),     // "3 people owe you · 1 you owe · 1 overdue"
    amount: signedNet(state),           // "+৳12,400" / "−৳2,000"
    onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LoansScreen())),
  ),
];
```
and add `...loansSection,` after `...accountsSection,` in **both** layout branches (lines 5456 and 5473).

`HomeNavigationTile` already exists (line 5498) — no new widget needed. Note its `amount` is a
preformatted `String`, so pass `state.format(...)` with a manual `+`/`−` prefix.

### 9.3 `LoansScreen` (`lib/loans/loan_screens.dart`)

```
PageScaffold(title: 'Loans', subtitle: 'Money you lent and borrowed', actions: [search, help])
 └ ResponsiveContent
    ├ LoanSummaryHero                       // 3-up: To collect / To pay / Net  + overdue chip
    ├ SleekPillSelector<LoanFilter>         // To collect | To pay | Settled | All
    ├ SectionHeader('People', trailing: 'Add person')
    └ for each contact with visible loans:
         LoanTile(loan, computation, onTap: → LoanDetailScreen)
      or EmptyCard(icon: Icons.handshake_rounded,
                   title: 'No loans yet',
                   body: 'Tap New loan the first time you lend or borrow money.',
                   action: () => showLoanEditor(context), actionLabel: 'New loan')
 + FloatingActionButton.extended(icon: add, label: 'New loan')
```
- Grouping: sort contacts by `abs(netWithContact)` descending; within a contact, sort loans by
  `dueDate` (nulls last) then `startDate` descending.
- Desktop (≥900px): two columns — hero+filter on the left (`flex 5`), list on the right (`flex 4`),
  mirroring `HomeDashboardScreen`'s `LayoutBuilder` branch at line 5460.
- Collapse settled loans behind the "Settled" pill so the default list stays short.

### 9.4 `LoanTile`

```
ExpressiveCard → ListTile
  leading : iconBubble(ctx, 'exchange', isLent ? '#27D17F' : '#FF5353', size: 50)
  title   : contact.name                       w900
  subtitle: "৳5,000 · 10% yearly · 2 of 6 paid"  (or "Due in 6 days" / "4 days overdue" in amber)
  trailing: Column( outstanding (w900, green if lent / red if borrowed),
                    LinearProgressIndicator(value: progress) )
```
Long-press → menu: Edit · Record payment · Mark settled · Delete.

### 9.5 `LoanDetailScreen`

```
PageScaffold(title: contact.name, subtitle: 'Lent on 12 Mar 2026', actions: [edit, more])
 ├ LoanHeroCard        // outstanding, "of ৳5,000", big progress arc, overdue pill
 ├ LoanMetricGrid      // Principal · Interest · Paid · Remaining · EMI · Due date  (2-col wrap)
 ├ SectionHeader('Payments', trailing: 'Add payment')
 └ payment rows: date · amount · "৳120 interest + ৳880 principal" · note · swipe-to-delete
 bottom: two buttons  [ Record payment (filled, flex 2) ] [ Edit (outlined) ]
```
Interactions:
- **Record payment** → `showLoanPaymentSheet` → quick-fill chips **Full ৳2,300**, **Half ৳1,150**,
  **EMI ৳880**, **Round ৳2,500**; live split preview; date (default today, not before `startDate`);
  note; "Also record in account" switch prefilled from the global default.
- After save: `showSnack('Payment recorded · ৳0 left — loan settled')` when it closes the loan.
- **Mark settled** when outstanding is already ~0, otherwise "Settle with a final payment of ৳X".
- **Delete** → confirm dialog with "Also delete the linked transaction(s)" checkbox (default off).

### 9.6 Optional 5th dock tab (D2 alternative) — exact 3 edits

1. `lib/app_config.dart`: `const int kLoansTabIndex = 4;`
2. `lib/main.dart:3656` — after `const CategoriesScreen(),` add `const LoansScreen(),`
3. `lib/main.dart:3859` — after the Categories destination add
   `const _DockDestination(label: 'Loans', icon: Icons.handshake_outlined, activeIcon: Icons.handshake_rounded),`
   (this one list feeds **both** `_FloatingDockNavigation` and `_SideRailNavigation`.)
4. Verify the floating dock still fits at 360px width (`AppBreakpoints.compact`).
If it crowds, keep the Home-tile approach instead.

### 9.7 Sheets (`lib/loans/loan_sheets.dart`)

Both use `showKoinlyPopup<void>(context, maxWidth: 560, maxHeight: 700, child: …)` like
`FilterSheet` (line 8119) so they adapt between phone sheet and desktop dialog.

**`LoanEditorSheet`**
1. Direction: `SleekPillSelector<LoanDirection>` — "I gave (they owe me)" / "I took (I owe them)"
   with a one-line explainer under it.
2. Person: `AppleSelectionField` populated from `state.loanContacts`, last option
   `+ Add new person` (inline name field, created on save).
3. Amount: numeric field, currency prefix from `state.currencySymbol`, large 28px text.
4. Date: `AppleSelectionField` date row, default today, max = today + 1 year.
5. "Add interest" expandable section (collapsed by default):
   `SleekPillSelector<LoanInterestType>` (None/Simple/Compound) → rate field ("% per") →
   `SleekCyclePillSelector<LoanInterestPeriod>` (Yearly/Monthly/Daily/Fixed total).
   Live preview: "≈ ৳137 interest after 100 days".
6. "Add a plan" expandable: installments count → live EMI preview "6 × ৳880.42".
7. Due date (optional) — only shown once a plan or interest exists (keeps the simple path simple).
8. Account row + "Record this in my account" switch (D1).
9. Note (optional).
10. Footer: `OutlinedButton('Cancel')` + `FilledButton('Save loan')`.

**`LoanPaymentSheet`** — amount (big), quick-fill chips, date, note, account switch, live
"Interest ৳120 · Principal ৳880" strip + "Remaining after this: ৳1,420".

Validation rules (surface inline, never with a raw exception):
- amount > 0 and finite; name non-empty; rate 0–1000; installmentCount 1–600;
- dueDate ≥ startDate; payment date ≥ startDate;
- warning (not blocking) when a payment exceeds the remaining balance → "This overpays by ৳X".

### 9.8 Accessibility & polish

- Every tappable ≥48×48; `Semantics` label on tiles: "Rahim, lent ৳5,000, ৳2,300 outstanding, 4 days overdue".
- All amounts go through `state.format` so `amountsHidden` (••••) is honoured everywhere.
- `state.reducedMotion ? Duration.zero : AppMotion.medium` for the sheets' entry animation.
- Windows: verify at 900px (rail), 1180px (extended rail) and 600px; Android: 360px phone and landscape.

---

## 10. Data Health, reminders, analytics

**`checkDataHealth()` (main.dart:1346)** — add four checks and two counters:
| Severity | Condition | Body |
| --- | --- | --- |
| error | loan references a missing contact | "N loan(s) point to a person that no longer exists." |
| error | payment references a missing loan | "N loan payment(s) point to a missing loan." |
| warning | `interest + principal != amount` (drift) | "N payment(s) have inconsistent splits. Open and re-save them." |
| warning | active loan overdue > 30 days | "N loan(s) are more than a month overdue." |
Add `loanCount` and `loanPaymentCount` to `DataHealthReport` (`lib/models.dart`) and show them in
the counts row of `DataHealthScreen`.

**Reminders (`lib/loans/loan_reminders.dart`)** — Android only (`kSupportsLocalNotifications`):
- New channel: id `loan_due_reminder`, name "Loan due reminders".
- Notification ids `900 + (loan.id.hashCode & 0x7FFFFFFF) % 1000` — stable per loan.
- Schedule at 10:00 local, on the earlier of (due date, due date − 1). Cap at 25 scheduled.
- Re-schedule on: app resume (`_MainShellState.didChangeAppLifecycleState`, line 3630), any loan
  mutation, and when the daily reminder is re-scheduled (`setReminder`, line 2899).
- `tzdata.initializeTimeZones()` already runs in `ReminderService.ensureInitialized()`.
- Gate on `loanRemindersEnabled`.

**Analytics** — optional: `FirebaseAnalytics.instance.logEvent(name: 'loan_created', …)`. Firebase is
wrapped in try/catch in `main()` and is optional; guard every call with a try/catch.

---

## 11. Risks & anti-patterns (read before generating code)

| # | Risk | Mitigation |
| --- | --- | --- |
| R1 | **Adding a new `AccountType.loan`** to reuse the account UI. | Do **not**. `_rebuildLookupCaches` splits accounts into `type != savings` vs `savings`; a third type silently distorts `operatingAccountBalance`, the Home hero card, budgets and filters. Loans are their own entity. |
| R2 | Forgetting `syncTables` | Loans appear to work locally and vanish on the second device. Covered by §7 + a unit test asserting the three names are whitelisted. |
| R3 | Restoring an old backup wipes loans | `importAll` deletes tables missing from the payload. Fixed by the `skipTables` parameter in §7. |
| R4 | Rounding drift between `amount` and its components | Store both components; derive nothing on read; assert `amount == interest + principal` in the repository insert. |
| R5 | Partial sync (loan arrives without its payments) | Server versions per-entity; the outbox is drained in batches. Enqueue parents before children, and make the UI tolerate a loan with zero payments (it already does — it just shows full principal outstanding). |
| R6 | `double` equality | Use `nearZero(x)` (`x.abs() < 0.005`) everywhere instead of `== 0`. |
| R7 | Timezone / DST bugs in day counts | Compare `DateTime` in local time consistently; never mix UTC and local. Store epoch millis, as the app already does. |
| R8 | Deleting a contact with loans | Block with an explainer, or cascade **and** enqueue deletes for loans and payments. Never leave orphans. |
| R9 | Bloating `main.dart` further | Keep the new code in `lib/loans/`; only wiring edits land in `main.dart`. |
| R10 | Interest displayed before it is earned | Always show "as of today" and the basis ("10% per year, 44 days"), so the number is never mysterious. |
| R11 | `installmentCount` of 0 or 1 | Treat `<= 0` as null (open-ended); `1` means a single bullet payment — still valid. |
| R12 | Payments dated in the future | Allowed for scheduled/expected entries? **No — v1 blocks future dates.** Keeps "outstanding" meaningful. |

---

## 12. Tests

**`test/loans/loan_computation_test.dart`** (pure, no Flutter binding — keep
`loan_computation.dart` free of Flutter/material imports):
1. no interest, two partial payments → outstanding = P − sum(payments).
2. no interest, single full payment → `settled == true`, `outstanding == 0`.
3. simple yearly 10%, P=36500, 365 days → interest ≈ 3650 (day-count /365).
4. simple monthly 10%, P=1000, 30.4375 days → interest ≈ 100.
5. simple interest is **not** reduced by payments (accrues on original P).
6. compound yearly 10%, P=1000, 365 days → 100; 730 days → 210.
7. compound **is** reduced by an early principal payment (balance-based accrual).
8. interest-first allocation: payment of 150 when 120 interest is owed → 120/30 split.
9. overpayment: paying more than total due → `overpaid > 0`, `outstanding < 0`, `settled == true`.
10. payments dated after `at` are excluded from the computation.
11. `at < startDate` → zero interest, zero days, no crash.
12. EMI: reducing-balance 12%/yr, P=12000, n=12 → ≈ 1066.19.
13. EMI with 0% → exactly P/n.
14. flat interest EMI → `(P + P*r) / n`.
15. `dueDate` in the past + outstanding > 0 → `overdue == true`, `daysOverdue` correct.
16. `interestAccrualStop == dueDate` freezes interest at the due date.
17. rounding: components always sum to `amount` for a randomized set of 200 cases.

**`test/loans/loan_repository_test.dart`** — needs `sqflite_common_ffi`:
```dart
setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
final repo = LoanRepository(() async => db);
```
1. insert contact → loan → 2 payments; read back; fields round-trip exactly (incl. `null` dueDate).
2. `deleteLoan` removes its payments inside the same transaction.
3. `createLoanWithDisbursal` decrements/increments the linked account by exactly `principal`.
4. `addPaymentWithTransaction` moves the money the correct **direction** for lent vs borrowed.
5. `deleteLoanCascade(deleteLinkedTransactions: true)` restores the account balance.
6. enum round-trip: `written_off` and `due_date` survive `toMap`/`fromMap` (guards the §4.2 ⚠ note).

**`test/loans/loan_sync_wiring_test.dart`**
1. `KoinlyDatabase.syncTables` contains `loan_contacts`, `loans`, `loan_payments`.
2. Every name in `syncTables` matches `RegExp(r'^[a-z_]{2,64}$')` (the Worker's rule).
3. `exportAll()` output contains the three tables.
4. `_entityIdForRow` / `_whereForEntity` resolve rows for the new tables via the `id` default branch.
5. Backup payload `version == 5`.

**Widget smoke test** — pump `LoansScreen` with an `AppController` whose lists are empty (like
`test/multi_device_sync_screen_test.dart` does) and assert the empty state renders, so a regression
in the Home tile or the screen constructor is caught without a database.

Run with `flutter test`. Add `flutter analyze` (repo has `analysis_options.yaml` with
`flutter_lints` ^4.0.0) to the definition of done.

---

## 13. Phased delivery

### Phase 0 — Spike (½ day)
- [ ] Read `lib/models.dart` and `AppController` CRUD (main.dart:2919-2996) end to end.
- [ ] Decide D1/D2/D3 with the repo owner.
- [ ] `flutter test` and `flutter analyze` are green **before** starting.

### Phase 1 — Data layer (1 day)
- [ ] `lib/loans/loan_models.dart` (models + enums + explicit snake_case mappers).
- [ ] `_createSchema`: 3 tables + 4 indexes; `version: 6` → `7`.
- [ ] `lib/loans/loan_repository.dart` with injectable db getter.
- [ ] The 5 table-list edits + backup version 4 → 5 + `importAll(skipTables:)`.
- **Acceptance:** fresh install creates the tables; `PRAGMA table_info` shows all columns;
  `flutter test` green; existing data untouched (open an old DB, accounts/transactions intact).

### Phase 2 — Computation engine + tests (1 day)
- [ ] `lib/loans/loan_computation.dart` (pure Dart, no Flutter import).
- [ ] All 17 unit tests from §12 pass.
- [ ] A `debugCompute()` helper that prints a full amortization table for manual eyeballing.
- **Acceptance:** the 17 tests pass; a 12-month, 12%-EMI schedule sums to the exact expected total.

### Phase 3 — Controller + UI (2-3 days)
- [ ] `AppController` wiring (§8): lists, caches, methods, preferences.
- [ ] `loan_widgets.dart`, `loan_screens.dart`, `loan_sheets.dart`.
- [ ] Home tile (or dock tab), `LoansScreen` → `LoanDetailScreen` navigation.
- [ ] Money-movement integration (§5.6) behind the D1 toggle.
- **Acceptance:** create / pay / edit / settle / delete round-trips; account balances move correctly;
  `amountsHidden` hides every loan amount; works at 360px, 900px and 1180px.

### Phase 4 — Sync, health, reminders (1 day)
- [ ] Two-device sync test: create a loan on A, pull on B, pay on B, pull on A.
- [ ] Backup → wipe → restore keeps loans (and the v4 path keeps existing loans).
- [ ] `checkDataHealth` checks + report counters.
- [ ] `loan_reminders.dart`.
- **Acceptance:** a loan created offline syncs as soon as the device is online; the sync screen shows
  no pending ops afterwards; `DataHealthScreen` reports the new counts.

### Phase 5 — Polish (1-2 days)
- [ ] Per-contact screen, search/filter, share statement, CSV/PDF export, written-off toggle.
- [ ] Empty/loading/error states, Undo snackbars, haptics.
- [ ] README feature list + `CHANGELOG.md` entry (`## [1.0.1039]` → `### Added` → Loans, matching the
      existing Keep-a-Changelog style with dates) + bump `pubspec.yaml` version and
      `app_config.dart`'s `appVersion` default.
- **Acceptance:** `flutter analyze` clean, `flutter test` green, manual pass on Android + Windows.

---

## 14. Definition of done

- [ ] `flutter analyze` → no new issues.
- [ ] `flutter test` → all green, including 17 computation + 6 repository + 5 wiring tests.
- [ ] Loans sync across two devices in both directions and survive backup/restore.
- [ ] Every displayed amount uses `state.format()` and honours `amountsHidden`.
- [ ] No new `AccountType`; no transaction/loan double-counting.
- [ ] `main.dart` grew by **< 80 lines** (everything else lives in `lib/loans/`).
- [ ] Manual QA on Android (phone + landscape) and Windows (900px + 1180px).
- [ ] `CHANGELOG.md` entry + version bump.

---

## 15. Reference: minimal code sketches

**Model skeleton (follow `lib/models.dart` exactly)**
```dart
class Loan {
  const Loan({required this.id, /* …all fields… */});

  final String id;
  // …

  Loan copyWith({String? id, /* … nullable copies of every field … */}) => Loan(/* … */);

  Map<String, Object?> toMap() => {
    'id': id,
    'contact_id': contactId,
    'direction': loanDirectionToDb(direction),
    'principal': principal,
    'interest_type': enumName(interestType),
    'interest_rate': interestRate,
    'interest_period': enumName(interestPeriod),
    'start_date': dateToDb(startDate),
    'due_date': dueDate == null ? null : dateToDb(dueDate!),
    'installment_count': installmentCount,
    'interest_accrual_stop': loanAccrualStopToDb(interestAccrualStop),
    'note': note,
    'status': loanStatusToDb(status),
    'closed_on': closedOn == null ? null : dateToDb(closedOn!),
    'disbursal_transaction_id': disbursalTransactionId,
    'created_on': dateToDb(createdOn),
    'updated_on': dateToDb(updatedOn),
  };

  static Loan fromMap(Map<String, Object?> m) => Loan(/* dateFromDb(...) etc. */);
}
```

**Controller method (copy the `saveAccount` shape verbatim)**
```dart
Future<void> saveLoan(Loan loan, {bool recordDisbursal = false, String? accountId}) async {
  if (recordDisbursal && accountId != null && accountId.isNotEmpty) {
    final category = loan.isLent
        ? await database.ensureCategory('Loan given', CategoryType.expense, '#FF9E9E', 'exchange')
        : await database.ensureCategory('Loan taken', CategoryType.income, '#9BE7B4', 'exchange');
    final txId = await loanRepo.createLoanWithDisbursal(
      loan, accountId: accountId, categoryId: category.id);
    await database.enqueueTableRow('transactions', txId!);
    await database.enqueueRowsForTable('accounts');
    // persist txId onto the loan row as disbursal_transaction_id
  } else {
    await loanRepo.upsertLoan(loan);
  }
  await database.enqueueTableRow('loans', loan.id);
  await reload(queueSync: true);
}
```

**Home tile helper**
```dart
String loanSubtitle(AppController s) {
  final sum = s.loanSummary;
  final parts = <String>[
    if (sum.toCollect > 0) '${sum.collectors} owe you',
    if (sum.toPay > 0) 'you owe ${sum.debtors}',
    if (sum.overdueCount > 0) '${sum.overdueCount} overdue',
  ];
  return parts.isEmpty ? 'No active loans' : parts.join(' · ');
}
```

---

## 16. Copy-paste prompt (condensed)

> Paste everything below the line into ChatGPT 5.x / Cursor / Claude after giving it this repo.

```
You are working in the Flutter repo at /home/user/Koinly (a personal finance app called Koinly,
Android + Windows, provider + sqflite + Cloudflare Worker sync). Branch: arena/01a047ad-koinly.

Implement a complete, friendly LOAN SYSTEM: track money I lend to friends and money I borrow from
friends, with optional interest, optional installment plans, optional due dates, and partial/full
repayments.

Read these first and follow their conventions exactly:
- lib/main.dart (13.9k-line monolith: KoinlyDatabase at line 82, AppController at 1080, CRUD pattern
  at 2919-2996, Home screen at 5311, SettingsScreen at 10578)
- lib/models.dart (model shape: final fields, copyWith, toMap, fromMap, enumName/enumByName,
  dateToDb/dateFromDb)
- lib/app_config.dart, lib/ui_foundation.dart, lib/icon_helpers.dart, lib/persistence_stores.dart

HARD RULES
1. Put new code in lib/loans/ (loan_models.dart, loan_computation.dart, loan_repository.dart,
   loan_widgets.dart, loan_screens.dart, loan_sheets.dart, loan_reminders.dart). main.dart may grow
   by < 80 lines of wiring only.
2. Follow the existing mutation pattern: db write -> database.enqueueTableRow(table, id) ->
   reload(queueSync: true).
3. Every displayed amount goes through AppController.format() (honours amountsHidden + currency).
4. Do NOT add a new AccountType - it would break _rebuildLookupCaches and the Home balance card.
5. loan_computation.dart must be PURE Dart with no Flutter import, and LoanRepository must accept an
   injected Future<Database> Function() so tests can use an in-memory FFI database.
6. Use only existing widgets: PageScaffold, ResponsiveContent, ExpressiveCard, SectionHeader,
   EmptyCard, SleekPillSelector, AppleSelectionField, showKoinlyPopup, showSnack, iconBubble.

DATA (new SQLite tables, bump openDatabase version 6 -> 7, add to the idempotent _createSchema)
  loan_contacts(id, name, phone, note, icon_name, icon_color, archived, created_on, updated_on)
  loans(id, contact_id, direction['lent'|'borrowed'], principal, interest_type['none'|'simple'|
        'compound'], interest_rate, interest_period['daily'|'monthly'|'yearly'|'flat'], start_date,
        due_date, installment_count, interest_accrual_stop['settled'|'due_date'], note,
        status['active'|'closed'|'written_off'], closed_on, disbursal_transaction_id,
        created_on, updated_on)
  loan_payments(id, loan_id, amount, interest_component, principal_component, paid_on, note,
                transaction_id, created_on, updated_on)
  + indexes on loans(contact_id), loans(status, due_date), loan_payments(loan_id, paid_on)

MANDATORY WIRING (missing any of these silently loses data)
- KoinlyDatabase.syncTables (main.dart:490) += loan_contacts, loans, loan_payments
- exportAll tables (main.dart:443) += same three
- importAll tables (main.dart:453) child-first: loan_payments, loans, loan_contacts, then the
  existing six; add an optional skipTables parameter so restoring a pre-loan (version < 5) backup
  does not wipe current loans
- clearFinanceDataForRemoteLogin (main.dart:479) += same three
- hasLocalUserActivity (main.dart:468) += 'loans'
- BackupService payload 'version': 4 -> 5 (main.dart:867 and 880)
- AppController: loanRepo + 3 lists + reload() loading + _rebuildLookupCaches() + CRUD methods
- checkDataHealth(): orphan loan->contact, orphan payment->loan, split drift, 30+ days overdue;
  add loanCount/loanPaymentCount to DataHealthReport

BUSINESS RULES
- Round with round2(v) = (v*100).roundToDouble()/100; compare with nearZero(v) = v.abs() < 0.005.
- Always store both interest_component and principal_component so they sum exactly to amount.
- Simple interest accrues on the ORIGINAL principal; compound accrues on the remaining balance after
  payments. Implement one period-by-period simulation (works for both), applying payments
  chronologically with interest-first allocation:
  interestPart = min(amount, max(0, accruedInterest - interestPaidSoFar)).
- day counts: daily -> days/365, monthly -> days/30.4375, yearly -> days/365, flat -> whole term.
- outstanding = principal + accruedInterest - totalPaid; overpaid = max(0, -outstanding);
  settled when outstanding <= 0.005; overdue when active && dueDate < now && outstanding > 0.
- EMI (only when installmentCount > 0): reducing balance P*i*(1+i)^n/((1+i)^n-1) with i = per-period
  monthly rate, or (P + P*r*termFactor)/n for flat; EMI is advisory, never enforced.
- Optional money movement (default ON, pref loanRecordTransactionsByDefault): disbursal of a lent
  loan = expense from an account, borrowed = income; repayment of a lent loan = income, borrowed =
  expense. Auto-create categories via database.ensureCategory(...) and store the transaction id on
  the loan/payment row. Never delete a linked transaction without an explicit confirm.

UI
- Home dashboard: a "Loans" HomeNavigationTile after the Accounts section showing net position and
  "N owe you · you owe M · K overdue"; tap -> LoansScreen (pushed route).
- LoansScreen: summary hero (To collect / To pay / Net + overdue chip), SleekPillSelector filter
  (To collect | To pay | Settled | All), loans grouped by contact, EmptyCard, extended FAB "New loan".
- LoanDetailScreen: outstanding hero with progress, metric grid (principal, interest, paid,
  remaining, EMI, due date), payment history with swipe-to-delete, "Record payment" + "Edit".
- Sheets via showKoinlyPopup: LoanEditorSheet (direction pills, contact picker with inline new
  person, amount, date, collapsible interest section with live preview, collapsible installment
  plan with live EMI, optional due date, account + record toggle, note) and LoanPaymentSheet
  (amount with Full/Half/EMI/Round quick-fill chips, date, live interest-vs-principal split,
  remaining preview, account toggle).
- Plain-language copy: "Rahim will pay you ৳2,300", "4 days overdue", "10% per year, 44 days".
- Two-column layout at >= 860px like HomeDashboardScreen; verify 360px, 900px and 1180px.

TESTS (test/loans/)
- loan_computation_test.dart: 17 cases listed in docs/loans/IMPLEMENTATION_PLAN.md section 12
  (no-interest partial/full, simple vs compound, accrual base, interest-first allocation,
  overpayment, future payments excluded, at < startDate, EMI reducing/flat/zero-rate, overdue,
  accrual stop, rounding invariant over random cases).
- loan_repository_test.dart: CRUD round-trip, cascade delete, account balance moves the right
  direction for lent vs borrowed, enum snake_case round-trip (written_off, due_date).
- loan_sync_wiring_test.dart: syncTables contains all three, all match ^[a-z_]{2,64}$,
  exportAll includes them, backup version == 5.

DELIVER IN PHASES (0 spike, 1 data, 2 computation + tests, 3 controller + UI, 4 sync/health/
reminders, 5 polish + CHANGELOG + version bump) and report the acceptance checklist from
docs/loans/IMPLEMENTATION_PLAN.md section 13 after each phase. Run `flutter analyze` and
`flutter test` before you declare each phase done.
```

---

*Plan authored against commit `229a6a5` on `arena/01a047ad-koinly`. All line numbers are from that
revision — re-run the `grep -n` commands in §1.3 before editing.*
