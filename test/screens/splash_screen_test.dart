import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/screens/onboarding/splash_screen.dart';

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
        child: const MaterialApp(home: SplashScreen()),
      );

  testWidgets('renders splash screen without crashing',
      (WidgetTester tester) async {
    // No session — stays on splash, won't navigate away
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Pump past animations to avoid hanging timers
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('shows app name', (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();

    expect(find.text('AiHomeCloud'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
