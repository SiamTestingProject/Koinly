import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/main.dart';
import 'package:koinly/models.dart';
import 'package:provider/provider.dart';

MoneyTransaction titledTransaction({String title = 'Lunch with friends'}) {
  final now = DateTime.utc(2026, 8, 28, 12, 30);
  return MoneyTransaction(
    id: 'transaction-1',
    type: MoneyTransactionType.expense,
    amount: 24.50,
    title: title,
    notes: 'Cafe',
    categoryId: 'food',
    fromAccountId: 'cash',
    createdOn: now,
    updatedOn: now,
  );
}

void main() {
  test('transaction title survives map and copy round trips', () {
    final original = titledTransaction();
    final restored = MoneyTransaction.fromMap(original.toMap());

    expect(restored.title, 'Lunch with friends');
    expect(restored.copyWith(title: 'Dinner').title, 'Dinner');
  });

  test('older transaction rows without a title remain readable', () {
    final map = titledTransaction().toMap()..remove('title');
    expect(MoneyTransaction.fromMap(map).title, isEmpty);
  });

  testWidgets('transaction history uses the saved title as its primary label', (tester) async {
    final controller = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(body: TransactionTile(tx: titledTransaction())),
        ),
      ),
    );

    expect(find.text('Lunch with friends'), findsOneWidget);
    expect(find.textContaining('Cafe'), findsOneWidget);
  });

  testWidgets('title input is available for expense and income but not transfer', (tester) async {
    final controller = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(body: TransactionEditor()),
        ),
      ),
    );

    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
    await tester.tap(find.text('Income'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);

    await tester.tap(find.text('Transfer'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Title'), findsNothing);
  });
}
