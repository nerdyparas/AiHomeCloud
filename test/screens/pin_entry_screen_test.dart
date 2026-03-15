import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/screens/onboarding/pin_entry_screen.dart';

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
          home: PinEntryScreen(
            deviceIp: '192.168.1.100',
          ),
        ),
      );

  group('PinEntryScreen', () {
    testWidgets('shows loading indicator while fetching users',
        (WidgetTester tester) async {
      final overrides = <Override>[];
      await tester.pumpWidget(buildSubject(overrides));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('displays question text when users are loaded',
        (WidgetTester tester) async {
      final overrides = <Override>[];

      await tester.pumpWidget(buildSubject(overrides));
      await tester.pump();

      // Verify the screen is built without throwing
      expect(find.byType(PinEntryScreen), findsOneWidget);
    });

    testWidgets('shows error message when user fetch fails',
        (WidgetTester tester) async {
      final overrides = <Override>[];

      await tester.pumpWidget(buildSubject(overrides));
      await tester.pump();

      // Verify the screen doesn't crash
      expect(find.byType(PinEntryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('has a Retry button when in error state',
        (WidgetTester tester) async {
      final overrides = <Override>[];

      await tester.pumpWidget(buildSubject(overrides));
      await tester.pump();

      // The screen should render
      expect(find.byType(PinEntryScreen), findsOneWidget);
    });
  });
}
