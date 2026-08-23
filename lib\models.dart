import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

enum AccountType { regular, credit, savings }
enum CategoryType { income, expense }
enum MoneyTransactionType { income, expense, transfer }
enum LoanType { given, taken }
enum LoanStatus { open, completed }
enum DateRangeType { today, thisWeek, thisMonth, thisYear, allTime, custom }
enum FinancialHealthPeriod { monthly, yearly }
enum CurrencyPosition { prefix, suffix }
enum ThemePreference { system, light, dark, batterySaver }
enum SyncDatabaseProvider { turso, mongoDb, local, cloudflareD1, supabase, neonPostgres, firebaseFirestore }

const List<SyncDatabaseProvider> userSyncDatabaseProviders = [
  SyncDatabaseProvider.mongoDb,
];

String enumName(Object value) => value.toString().split('.').last;

T enumByName<T>(Iterable<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final value in values) {
    if (enumName(value as Object) == name) return value;
  }
  return fallback;
}

String syncDatabaseProviderLabel(SyncDatabaseProvider provider) {
  switch (provider) {
    case SyncDatabaseProvider.turso:
      return 'Turso Database (hidden)';
    case SyncDatabaseProvider.mongoDb:
      return 'MongoDB Database';
    case SyncDatabaseProvider.local:
      return 'Local Database';
    case SyncDatabaseProvider.cloudflareD1:
      return 'Cloudflare D1';
    case SyncDatabaseProvider.supabase:
      return 'Supabase Postgres';
    case SyncDatabaseProvider.neonPostgres:
      return 'Neon Postgres';
    case SyncDatabaseProvider.firebaseFirestore:
      return 'Firebase Firestore';
  }
}

IconData syncDatabaseProviderIcon(SyncDatabaseProvider provider) {
  switch (provider) {
    case SyncDatabaseProvider.turso:
      return Icons.block_rounded;
    case SyncDatabaseProvider.mongoDb:
      return Icons.storage_rounded;
    case SyncDatabaseProvider.local:
      return Icons.phone_android_rounded;
    case SyncDatabaseProvider.cloudflareD1:
      return Icons.cloud_queue_rounded;
    case SyncDatabaseProvider.supabase:
      return Icons.account_tree_rounded;
    case SyncDatabaseProvider.neonPostgres:
      return Icons.auto_awesome_rounded;
    case SyncDatabaseProvider.firebaseFirestore:
      return Icons.local_fire_department_rounded;
  }
}

String syncDatabaseProviderSubtitle(SyncDatabaseProvider provider) {
  switch (provider) {
    case SyncDatabaseProvider.turso:
      return 'Hidden for users until Turso sync is ready again.';
    case SyncDatabaseProvider.mongoDb:
      return 'Use a MongoDB URL to store app sync snapshots.';
    case SyncDatabaseProvider.local:
      return 'Keep data on this device only. No cloud credentials required.';
    case SyncDatabaseProvider.cloudflareD1:
      return 'Free Cloudflare database option through your Koinly Worker API.';
    case SyncDatabaseProvider.supabase:
      return 'Free Supabase Postgres option through your Koinly Worker API.';
    case SyncDatabaseProvider.neonPostgres:
      return 'Free Neon Postgres option through your Koinly Worker API.';
    case SyncDatabaseProvider.firebaseFirestore:
      return 'Free Firebase Firestore option through your Koinly Worker API.';
  }
}

String redactSyncSecrets(String value) {
  return value
      .replaceAll(RegExp(r'mongodb(\+srv)?:\/\/[^\s\)\]\}]+', caseSensitive: false), 'mongodb://••••')
      .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._~+\/=-]+', caseSensitive: false), 'Bearer ••••')
      .replaceAllMapped(RegExp(r'(token|password|auth)[=:]\s*[^,;\s]+', caseSensitive: false), (match) => '${match.group(1)}=••••');
}


DateTime dateFromDb(Object? value) {
  if (value == null) return DateTime.now();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
  return DateTime.now();
}

int dateToDb(DateTime value) => value.millisecondsSinceEpoch;

Color colorFromHex(String value, {Color fallback = const Color(0xFF78D8E8)}) {
  final cleaned = value.replaceAll('#', '').trim();
  if (cleaned.isEmpty) return fallback;
  final normalized = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
  return Color(int.tryParse(normalized, radix: 16) ?? fallback.value);
}

String colorToHex(Color color) => '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';

class Account {
  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.iconName,
    required this.iconColor,
    required this.amount,
    required this.creditLimit,
    required this.sequence,
    required this.createdOn,
    required this.updatedOn,
  });

  final String id;
  final String name;
  final AccountType type;
  final String iconName;
  final String iconColor;
  final double amount;
  final double creditLimit;
  final int sequence;
  final DateTime createdOn;
  final DateTime updatedOn;

  double get availableCredit => type == AccountType.credit ? creditLimit + amount : 0;

  Account copyWith({
    String? id,
    String? name,
    AccountType? type,
    String? iconName,
    String? iconColor,
    double? amount,
    double? creditLimit,
    int? sequence,
    DateTime? createdOn,
    DateTime? updatedOn,
  }) => Account(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        iconName: iconName ?? this.iconName,
        iconColor: iconColor ?? this.iconColor,
        amount: amount ?? this.amount,
        creditLimit: creditLimit ?? this.creditLimit,
        sequence: sequence ?? this.sequence,
        createdOn: createdOn ?? this.createdOn,
        updatedOn: updatedOn ?? this.updatedOn,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': enumName(type),
        'icon_name': iconName,
        'icon_color': iconColor,
        'amount': amount,
        'credit_limit': creditLimit,
        'sequence': sequence,
        'created_on': dateToDb(createdOn),
        'updated_on': dateToDb(updatedOn),
      };

  static Account fromMap(Map<String, Object?> map) => Account(
        id: map['id'] as String,
        name: map['name'] as String,
        type: enumByName(AccountType.values, map['type'] as String?, AccountType.regular),
        iconName: map['icon_name'] as String? ?? 'wallet',
        iconColor: map['icon_color'] as String? ?? '#78D8E8',
        amount: (map['amount'] as num? ?? 0).toDouble(),
        creditLimit: (map['credit_limit'] as num? ?? 0).toDouble(),
        sequence: (map['sequence'] as num? ?? 0).toInt(),
        createdOn: dateFromDb(map['created_on']),
        updatedOn: dateFromDb(map['updated_on']),
      );
}

class Category {
  Category({
    required this.id,
    required this.name,
    required this.type,
    required this.iconName,
    required this.iconColor,
    required this.createdOn,
    required this.updatedOn,
  });

  final String id;
  final String name;
  final CategoryType type;
  final String iconName;
  final String iconColor;
  final DateTime createdOn;
  final DateTime updatedOn;

  Category copyWith({
    String? id,
    String? name,
    CategoryType? type,
    String? iconName,
    String? iconColor,
    DateTime? createdOn,
    DateTime? updatedOn,
  }) => Category(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        iconName: iconName ?? this.iconName,
        iconColor: iconColor ?? this.iconColor,
        createdOn: createdOn ?? this.createdOn,
        updatedOn: updatedOn ?? this.updatedOn,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': enumName(type),
        'icon_name': iconName,
        'icon_color': iconColor,
        'created_on': dateToDb(createdOn),
        'updated_on': dateToDb(updatedOn),
      };

  static Category fromMap(Map<String, Object?> map) => Category(
        id: map['id'] as String,
        name: map['name'] as String,
        type: enumByName(CategoryType.values, map['type'] as String?, CategoryType.expense),
        iconName: map['icon_name'] as String? ?? 'category',
        iconColor: map['icon_color'] as String? ?? '#78D8E8',
        createdOn: dateFromDb(map['created_on']),
        updatedOn: dateFromDb(map['updated_on']),
      );

  bool get isLoanSystemCategory => const {
        'Loan Given',
        'Loan Taken',
        'Loan Repayment Received',
        'Loan Repayment Paid',
      }.contains(name);
}

class MoneyTransaction {
  MoneyTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.notes,
    required this.categoryId,
    required this.fromAccountId,
    this.toAccountId,
    this.imagePath = '',
    this.loanId,
    this.repaymentId,
    required this.createdOn,
    required this.updatedOn,
  });

  final String id;
  final MoneyTransactionType type;
  final double amount;
  final String notes;
  final String categoryId;
  final String fromAccountId;
  final String? toAccountId;
  final String imagePath;
  final String? loanId;
  final String? repaymentId;
  final DateTime createdOn;
  final DateTime updatedOn;

  bool get isLoanMovement => loanId != null;
  bool get isLoanPrincipal => loanId != null && repaymentId == null;
  bool get isLoanRepayment => loanId != null && repaymentId != null;

  // Loan principal and repayment movements update account balances, but they are
  // balance-sheet movements rather than income or expense for reports.
  bool get countsAsIncome => type == MoneyTransactionType.income && !isLoanMovement;
  bool get countsAsExpense => type == MoneyTransactionType.expense && !isLoanMovement;

  String get displayType {
    if (isLoanPrincipal) {
      return type == MoneyTransactionType.income ? 'Loan Taken' : 'Loan Given';
    }
    if (isLoanRepayment) {
      return type == MoneyTransactionType.income ? 'Loan Repayment Received' : 'Loan Repayment Paid';
    }
    return enumName(type);
  }

  MoneyTransaction copyWith({
    String? id,
    MoneyTransactionType? type,
    double? amount,
    String? notes,
    String? categoryId,
    String? fromAccountId,
    String? toAccountId,
    String? imagePath,
    String? loanId,
    String? repaymentId,
    DateTime? createdOn,
    DateTime? updatedOn,
  }) => MoneyTransaction(
        id: id ?? this.id,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        notes: notes ?? this.notes,
        categoryId: categoryId ?? this.categoryId,
        fromAccountId: fromAccountId ?? this.fromAccountId,
        toAccountId: toAccountId ?? this.toAccountId,
        imagePath: imagePath ?? this.imagePath,
        loanId: loanId ?? this.loanId,
        repaymentId: repaymentId ?? this.repaymentId,
        createdOn: createdOn ?? this.createdOn,
        updatedOn: updatedOn ?? this.updatedOn,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'type': enumName(type),
        'amount': amount,
        'notes': notes,
        'category_id': categoryId,
        'from_account_id': fromAccountId,
        'to_account_id': toAccountId,
        'image_path': imagePath,
        'loan_id': loanId,
        'repayment_id': repaymentId,
        'created_on': dateToDb(createdOn),
        'updated_on': dateToDb(updatedOn),
      };

  static MoneyTransaction fromMap(Map<String, Object?> map) => MoneyTransaction(
        id: map['id'] as String,
        type: enumByName(MoneyTransactionType.values, map['type'] as String?, MoneyTransactionType.expense),
        amount: (map['amount'] as num? ?? 0).toDouble(),
        notes: map['notes'] as String? ?? '',
        categoryId: map['category_id'] as String? ?? '',
        fromAccountId: map['from_account_id'] as String? ?? '',
        toAccountId: map['to_account_id'] as String?,
        imagePath: map['image_path'] as String? ?? '',
        loanId: map['loan_id'] as String?,
        repaymentId: map['repayment_id'] as String?,
        createdOn: dateFromDb(map['created_on']),
        updatedOn: dateFromDb(map['updated_on']),
      );
}

class Budget {
  Budget({
    required this.id,
    required this.selectedMonth,
    required this.amount,
    required this.allAccountsSelected,
    required this.allCategoriesSelected,
    required this.accountIds,
    required this.categoryIds,
    required this.createdOn,
    required this.updatedOn,
  });

  final String id;
  final DateTime selectedMonth;
  final double amount;
  final bool allAccountsSelected;
  final bool allCategoriesSelected;
  final List<String> accountIds;
  final List<String> categoryIds;
  final DateTime createdOn;
  final DateTime updatedOn;

  Map<String, Object?> toMap() => {
        'id': id,
        'selected_month': DateFormat('yyyy-MM').format(selectedMonth),
        'amount': amount,
        'all_accounts_selected': allAccountsSelected ? 1 : 0,
        'all_categories_selected': allCategoriesSelected ? 1 : 0,
        'created_on': dateToDb(createdOn),
        'updated_on': dateToDb(updatedOn),
      };

  static Budget fromMap(Map<String, Object?> map, List<String> accountIds, List<String> categoryIds) {
    final month = DateTime.tryParse('${map['selected_month'] as String? ?? DateFormat('yyyy-MM').format(DateTime.now())}-01') ?? DateTime.now();
    return Budget(
      id: map['id'] as String,
      selectedMonth: month,
      amount: (map['amount'] as num? ?? 0).toDouble(),
      allAccountsSelected: (map['all_accounts_selected'] as num? ?? 1).toInt() == 1,
      allCategoriesSelected: (map['all_categories_selected'] as num? ?? 1).toInt() == 1,
      accountIds: accountIds,
      categoryIds: categoryIds,
      createdOn: dateFromDb(map['created_on']),
      updatedOn: dateFromDb(map['updated_on']),
    );
  }

  Budget copyWith({
    String? id,
    DateTime? selectedMonth,
    double? amount,
    bool? allAccountsSelected,
    bool? allCategoriesSelected,
    List<String>? accountIds,
    List<String>? categoryIds,
    DateTime? createdOn,
    DateTime? updatedOn,
  }) => Budget(
        id: id ?? this.id,
        selectedMonth: selectedMonth ?? this.selectedMonth,
        amount: amount ?? this.amount,
        allAccountsSelected: allAccountsSelected ?? this.allAccountsSelected,
        allCategoriesSelected: allCategoriesSelected ?? this.allCategoriesSelected,
        accountIds: accountIds ?? this.accountIds,
        categoryIds: categoryIds ?? this.categoryIds,
        createdOn: createdOn ?? this.createdOn,
        updatedOn: updatedOn ?? this.updatedOn,
      );
}

enum DataHealthSeverity { info, warning, error }

class DataHealthItem {
  const DataHealthItem({
    required this.severity,
    required this.title,
    required this.body,
    this.actionLabel,
  });

  final DataHealthSeverity severity;
  final String title;
  final String body;
  final String? actionLabel;
}

class DataHealthReport {
  const DataHealthReport({
    required this.checkedAt,
    required this.items,
    required this.accountCount,
    required this.categoryCount,
    required this.transactionCount,
    required this.budgetCount,
    required this.pendingSyncOperations,
    required this.openSyncConflicts,
    required this.skippedStarterPlaceholdersVisible,
  });

  final DateTime checkedAt;
  final List<DataHealthItem> items;
  final int accountCount;
  final int categoryCount;
  final int transactionCount;
  final int budgetCount;
  final int pendingSyncOperations;
  final int openSyncConflicts;
  final bool skippedStarterPlaceholdersVisible;

  bool get hasErrors => items.any((item) => item.severity == DataHealthSeverity.error);
  bool get hasWarnings => items.any((item) => item.severity == DataHealthSeverity.warning);

  String get statusTitle {
    if (hasErrors) return 'Needs attention';
    if (hasWarnings) return 'Looks okay, with notes';
    return 'Healthy';
  }

  String get statusBody {
    if (items.isEmpty) return 'No broken references, sync conflicts, or skipped setup leftovers were found.';
    return '${items.length} item${items.length == 1 ? '' : 's'} found during the last check.';
  }
}

class Loan {
  Loan({
    required this.id,
    required this.type,
    required this.accountId,
    required this.personName,
    required this.amount,
    required this.loanDate,
    this.dueDate,
    required this.notes,
    required this.repaidAmount,
    required this.status,
    required this.createdOn,
    required this.updatedOn,
  });

  final String id;
  final LoanType type;
  final String accountId;
  final String personName;
  final double amount;
  final DateTime loanDate;
  final DateTime? dueDate;
  final String notes;
  final double repaidAmount;
  final LoanStatus status;
  final DateTime createdOn;
  final DateTime updatedOn;

  double get remainingAmount => math.max<double>(0.0, amount - repaidAmount);
  bool get isCompleted => status == LoanStatus.completed || remainingAmount <= 0.0001;

  Map<String, Object?> toMap() => {
        'id': id,
        'type': enumName(type),
        'account_id': accountId,
        'person_name': personName,
        'amount': amount,
        'loan_date': dateToDb(loanDate),
        'due_date': dueDate == null ? null : dateToDb(dueDate!),
        'notes': notes,
        'repaid_amount': repaidAmount,
        'status': enumName(status),
        'created_on': dateToDb(createdOn),
        'updated_on': dateToDb(updatedOn),
      };

  static Loan fromMap(Map<String, Object?> map) => Loan(
        id: map['id'] as String,
        type: enumByName(LoanType.values, map['type'] as String?, LoanType.given),
        accountId: map['account_id'] as String? ?? '',
        personName: map['person_name'] as String? ?? '',
        amount: (map['amount'] as num? ?? 0).toDouble(),
        loanDate: dateFromDb(map['loan_date']),
        dueDate: map['due_date'] == null ? null : dateFromDb(map['due_date']),
        notes: map['notes'] as String? ?? '',
        repaidAmount: (map['repaid_amount'] as num? ?? 0).toDouble(),
        status: enumByName(LoanStatus.values, map['status'] as String?, LoanStatus.open),
        createdOn: dateFromDb(map['created_on']),
        updatedOn: dateFromDb(map['updated_on']),
      );

  Loan copyWith({
    String? id,
    LoanType? type,
    String? accountId,
    String? personName,
    double? amount,
    DateTime? loanDate,
    DateTime? dueDate,
    String? notes,
    double? repaidAmount,
    LoanStatus? status,
    DateTime? createdOn,
    DateTime? updatedOn,
  }) => Loan(
        id: id ?? this.id,
        type: type ?? this.type,
        accountId: accountId ?? this.accountId,
        personName: personName ?? this.personName,
        amount: amount ?? this.amount,
        loanDate: loanDate ?? this.loanDate,
        dueDate: dueDate ?? this.dueDate,
        notes: notes ?? this.notes,
        repaidAmount: repaidAmount ?? this.repaidAmount,
        status: status ?? this.status,
        createdOn: createdOn ?? this.createdOn,
        updatedOn: updatedOn ?? this.updatedOn,
      );
}

class LoanRepayment {
  LoanRepayment({
    required this.id,
    required this.loanId,
    required this.accountId,
    required this.amount,
    required this.paidOn,
    required this.notes,
    required this.createdOn,
  });

  final String id;
  final String loanId;
  final String accountId;
  final double amount;
  final DateTime paidOn;
  final String notes;
  final DateTime createdOn;

  Map<String, Object?> toMap() => {
        'id': id,
        'loan_id': loanId,
        'account_id': accountId,
        'amount': amount,
        'paid_on': dateToDb(paidOn),
        'notes': notes,
        'created_on': dateToDb(createdOn),
      };

  static LoanRepayment fromMap(Map<String, Object?> map) => LoanRepayment(
        id: map['id'] as String,
        loanId: map['loan_id'] as String? ?? '',
        accountId: map['account_id'] as String? ?? '',
        amount: (map['amount'] as num? ?? 0).toDouble(),
        paidOn: dateFromDb(map['paid_on']),
        notes: map['notes'] as String? ?? '',
        createdOn: dateFromDb(map['created_on']),
      );
}


class LoanRepaymentReminder {
  LoanRepaymentReminder({
    required this.id,
    required this.loanId,
    required this.accountId,
    required this.amount,
    required this.dueDate,
    required this.reminderTimeMinutes,
    required this.notes,
    required this.isPaid,
    this.paidOn,
    required this.createdOn,
    required this.updatedOn,
  });

  final String id;
  final String loanId;
  final String accountId;
  final double amount;
  final DateTime dueDate;
  final int reminderTimeMinutes;
  final String notes;
  final bool isPaid;
  final DateTime? paidOn;
  final DateTime createdOn;
  final DateTime updatedOn;

  bool get isOverdue {
    if (isPaid) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return dueDay.isBefore(today);
  }

  bool get isDueToday {
    if (isPaid) return false;
    final now = DateTime.now();
    return dueDate.year == now.year && dueDate.month == now.month && dueDate.day == now.day;
  }

  DateTime get reminderAt {
    final hour = reminderTimeMinutes ~/ 60;
    final minute = reminderTimeMinutes % 60;
    return DateTime(dueDate.year, dueDate.month, dueDate.day, hour, minute);
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'loan_id': loanId,
        'account_id': accountId,
        'amount': amount,
        'due_date': dateToDb(dueDate),
        'reminder_time_minutes': reminderTimeMinutes,
        'notes': notes,
        'is_paid': isPaid ? 1 : 0,
        'paid_on': paidOn == null ? null : dateToDb(paidOn!),
        'created_on': dateToDb(createdOn),
        'updated_on': dateToDb(updatedOn),
      };

  static LoanRepaymentReminder fromMap(Map<String, Object?> map) => LoanRepaymentReminder(
        id: map['id'] as String,
        loanId: map['loan_id'] as String? ?? '',
        accountId: map['account_id'] as String? ?? '',
        amount: (map['amount'] as num? ?? 0).toDouble(),
        dueDate: dateFromDb(map['due_date']),
        reminderTimeMinutes: (map['reminder_time_minutes'] as num? ?? (9 * 60)).toInt(),
        notes: map['notes'] as String? ?? '',
        isPaid: (map['is_paid'] as num? ?? 0).toInt() == 1,
        paidOn: map['paid_on'] == null ? null : dateFromDb(map['paid_on']),
        createdOn: dateFromDb(map['created_on']),
        updatedOn: dateFromDb(map['updated_on']),
      );

  LoanRepaymentReminder copyWith({
    String? id,
    String? loanId,
    String? accountId,
    double? amount,
    DateTime? dueDate,
    int? reminderTimeMinutes,
    String? notes,
    bool? isPaid,
    DateTime? paidOn,
    DateTime? createdOn,
    DateTime? updatedOn,
  }) => LoanRepaymentReminder(
        id: id ?? this.id,
        loanId: loanId ?? this.loanId,
        accountId: accountId ?? this.accountId,
        amount: amount ?? this.amount,
        dueDate: dueDate ?? this.dueDate,
        reminderTimeMinutes: reminderTimeMinutes ?? this.reminderTimeMinutes,
        notes: notes ?? this.notes,
        isPaid: isPaid ?? this.isPaid,
        paidOn: paidOn ?? this.paidOn,
        createdOn: createdOn ?? this.createdOn,
        updatedOn: updatedOn ?? this.updatedOn,
      );
}


class SavingsSuggestionProfile {
  const SavingsSuggestionProfile({
    required this.completed,
    required this.hobby,
    required this.occupation,
    required this.age,
    required this.savingsGoal,
    required this.spendingPreference,
    required this.extraDetails,
    required this.updatedOn,
  });

  final bool completed;
  final String hobby;
  final String occupation;
  final int age;
  final String savingsGoal;
  final String spendingPreference;
  final String extraDetails;
  final DateTime? updatedOn;

  static const empty = SavingsSuggestionProfile(
    completed: false,
    hobby: '',
    occupation: '',
    age: 0,
    savingsGoal: '',
    spendingPreference: '',
    extraDetails: '',
    updatedOn: null,
  );

  bool get hasPersonalDetails => hobby.trim().isNotEmpty || occupation.trim().isNotEmpty || age > 0 || savingsGoal.trim().isNotEmpty || spendingPreference.trim().isNotEmpty || extraDetails.trim().isNotEmpty;

  String get shortLabel {
    final parts = [
      if (occupation.trim().isNotEmpty) occupation.trim(),
      if (hobby.trim().isNotEmpty) hobby.trim(),
      if (savingsGoal.trim().isNotEmpty) savingsGoal.trim(),
    ];
    if (parts.isEmpty) return completed ? 'Generic suggestions' : 'Not configured';
    return parts.take(2).join(' • ');
  }

  Map<String, dynamic> toJson() => {
        'completed': completed,
        'hobby': hobby,
        'occupation': occupation,
        'age': age,
        'savingsGoal': savingsGoal,
        'spendingPreference': spendingPreference,
        'extraDetails': extraDetails,
        'updatedOn': updatedOn?.toIso8601String() ?? '',
      };

  static SavingsSuggestionProfile fromJson(Map<String, dynamic> json) => SavingsSuggestionProfile(
        completed: json['completed'] as bool? ?? false,
        hobby: json['hobby'] as String? ?? '',
        occupation: json['occupation'] as String? ?? '',
        age: (json['age'] as num? ?? 0).toInt(),
        savingsGoal: json['savingsGoal'] as String? ?? '',
        spendingPreference: json['spendingPreference'] as String? ?? '',
        extraDetails: json['extraDetails'] as String? ?? '',
        updatedOn: (json['updatedOn'] as String? ?? '').isEmpty ? null : DateTime.tryParse(json['updatedOn'] as String),
      );

  static SavingsSuggestionProfile fromJsonString(String raw) {
    if (raw.trim().isEmpty) return SavingsSuggestionProfile.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return SavingsSuggestionProfile.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {}
    return SavingsSuggestionProfile.empty;
  }

  SavingsSuggestionProfile copyWith({
    bool? completed,
    String? hobby,
    String? occupation,
    int? age,
    String? savingsGoal,
    String? spendingPreference,
    String? extraDetails,
    DateTime? updatedOn,
  }) => SavingsSuggestionProfile(
        completed: completed ?? this.completed,
        hobby: hobby ?? this.hobby,
        occupation: occupation ?? this.occupation,
        age: age ?? this.age,
        savingsGoal: savingsGoal ?? this.savingsGoal,
        spendingPreference: spendingPreference ?? this.spendingPreference,
        extraDetails: extraDetails ?? this.extraDetails,
        updatedOn: updatedOn ?? this.updatedOn,
      );
}

class SavingsPurchaseSuggestion {
  const SavingsPurchaseSuggestion({
    required this.id,
    required this.title,
    required this.costRange,
    required this.reason,
    required this.savingsFit,
    required this.iconName,
    required this.color,
  });

  final String id;
  final String title;
  final String costRange;
  final String reason;
  final String savingsFit;
  final String iconName;
  final String color;
}

class DateRange {
  const DateRange(this.start, this.end, this.label);
  final DateTime? start;
  final DateTime? end;
  final String label;
}

class Summary {
  const Summary({required this.income, required this.expense});
  final double income;
  final double expense;
  double get balance => income - expense;
}

class BudgetProgress {
  BudgetProgress(this.budget, this.spent, this.transactions);
  final Budget budget;
  final double spent;
  final List<MoneyTransaction> transactions;
  double get ratio => budget.amount <= 0 ? 0 : spent / budget.amount;
}

