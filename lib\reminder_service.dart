import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_config.dart';
import 'models.dart';

class ReminderService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> ensureInitialized() async {
    if (!kSupportsLocalNotifications) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(settings);
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> scheduleDaily(TimeOfDay time) async {
    if (!kSupportsLocalNotifications) return;
    await cancel();
    final scheduled = _next(time);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_expense_reminder',
        'Daily expense reminder',
        channelDescription: 'Reminder to add daily expenses.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _notifications.zonedSchedule(
      501,
      'Koinly',
      "Don’t forget to record your expenses",
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static tz.TZDateTime _next(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var date = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (date.isBefore(now)) date = date.add(const Duration(days: 1));
    return date;
  }

  static int _loanReminderNotificationId(String id) => 700000 + (id.hashCode.abs() % 200000);

  static Future<void> scheduleLoanRepaymentReminder({required Loan loan, required LoanRepaymentReminder reminder}) async {
    if (!kSupportsLocalNotifications || reminder.isPaid) return;
    final scheduled = tz.TZDateTime.from(reminder.reminderAt, tz.local);
    if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) return;
    final label = loan.type == LoanType.given ? 'Loan repayment expected' : 'Loan repayment due';
    final body = loan.type == LoanType.given
        ? 'Expected repayment from ${loan.personName} is due on ${DateFormat('MMM d, yyyy').format(reminder.dueDate)}.'
        : 'Repayment to ${loan.personName} is due on ${DateFormat('MMM d, yyyy').format(reminder.dueDate)}.';
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'loan_repayment_reminders',
        'Loan repayment reminders',
        channelDescription: 'Upcoming, due today, and overdue loan repayment alerts.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _notifications.zonedSchedule(
      _loanReminderNotificationId(reminder.id),
      label,
      body,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelLoanRepaymentReminder(String id) async {
    if (!kSupportsLocalNotifications) return;
    await _notifications.cancel(_loanReminderNotificationId(id));
  }

  static Future<void> cancel() async {
    if (!kSupportsLocalNotifications) return;
    await _notifications.cancel(501);
  }
}
