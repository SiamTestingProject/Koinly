import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const Color kSleekBackground = Color(0xFF020B0F);
const Color kSleekSurface = Color(0xFF07171D);
const Color kSleekSurfaceHigh = Color(0xFF0C2028);
const Color kSleekSurfaceHigher = Color(0xFF132B34);
const Color kSleekAccent = Color(0xFF00D7E8);
const Color kSleekIncome = Color(0xFF27D17F);
const Color kSleekExpense = Color(0xFFFF5353);
const Color kSleekWarning = Color(0xFFF59E0B);
const Color kSleekMuted = Color(0xFF90A4AD);

const appTitle = 'Koinly';
const appVersion = String.fromEnvironment('KOINLY_APP_VERSION', defaultValue: '1.0.70');
const backupPassword = 'YOUR_SECRET_PASSWORD';
const kSyncAdminTelegramUrl = 'https://t.me/Ch0wdhury_Siam';
final bool kLoansFeatureEnabled = bool.fromEnvironment('KOINLY_ENABLE_LOANS', defaultValue: true);

const int kHomeTabIndex = 0;
const int kAnalysisTabIndex = 1;
int get kLoansTabIndex => 2;
int get kTransactionTabIndex => kLoansFeatureEnabled ? 3 : 2;
int get kCategoriesTabIndex => kLoansFeatureEnabled ? 4 : 3;

bool get kUsesDesktopSqlite => !kIsWeb && (Platform.isWindows || Platform.isLinux);
bool get kIsDesktopApp => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
bool get kSupportsLocalNotifications => !kIsWeb && Platform.isAndroid;

// Desktop builds store SharedPreferences separately from Android. Older Windows
// builds could inherit `onboardingCompleted=true` and skip the setup flow.
// Bumping this desktop setup marker forces the setup pages to appear once on PC
// without resetting mobile users or deleting any finance data. Revision 20260621 also
// corrects installs that previously skipped the Windows setup flow.
const int kRequiredDesktopSetupVersion = 20260623;
