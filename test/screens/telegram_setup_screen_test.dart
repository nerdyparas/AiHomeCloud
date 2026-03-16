import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/l10n/app_localizations.dart';
import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/screens/main/telegram_setup_screen.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildSubject(List<Override> overrides) => ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...overrides,
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TelegramSetupScreen(),
        ),
      );

  // TelegramSetupScreen calls getTelegramConfig() in initState.
  // Without a server, it lands in error state.

  testWidgets('renders without crashing (error state on no server)',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();
    // Allow async _loadConfig to settle into error state
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(TelegramSetupScreen), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows loading indicator initially',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject([]));
    // First frame — _loading is true
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('contains AppBar', (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(AppBar), findsOneWidget);
  });
}
