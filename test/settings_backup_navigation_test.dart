import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/main.dart';
import 'package:provider/provider.dart';

Future<void> pumpSettingsScreen(WidgetTester tester, Widget screen) async {
  final controller = AppController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: controller,
      child: MaterialApp(home: screen),
    ),
  );
}

void main() {
  testWidgets('main Settings omits duplicate backup loading', (tester) async {
    await pumpSettingsScreen(tester, const SettingsScreen());

    expect(find.text('Load backup'), findsNothing);
    expect(find.text('Advanced settings'), findsOneWidget);
  });

  testWidgets('Advanced settings keeps backup loading available', (tester) async {
    await pumpSettingsScreen(tester, const AdvancedSettingsScreen());

    expect(find.text('Backup'), findsOneWidget);
    expect(find.text('Load backup'), findsOneWidget);
  });
}
