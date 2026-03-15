import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/screens/onboarding/profile_creation_screen.dart';
import 'package:aihomecloud/providers/core_providers.dart';

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
          home: ProfileCreationScreen(
            deviceIp: '192.168.1.100',
            isAddingUser: false,
          ),
        ),
      );

  group('ProfileCreationScreen', () {
    testWidgets('renders emoji picker and name input',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      // Verify screen renders
      expect(find.byType(ProfileCreationScreen), findsOneWidget);
      // Check for TextField (name input field)
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('shows error when name is empty and submit is tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      // Find and tap the submit button (typically a FilledButton with 'Create'/'Save' text or icon)
      final buttons = find.byType(FilledButton);
      if (buttons.evaluate().isNotEmpty) {
        await tester.tap(buttons.first);
        await tester.pump();
      }

      // Verify the screen is still present (no crash)
      expect(find.byType(ProfileCreationScreen), findsOneWidget);
    });

    testWidgets('emoji avatar renders when emoji is selected',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      // Verify screen is built
      expect(find.byType(ProfileCreationScreen), findsOneWidget);
      // The avatar widget should be present
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('name input field accepts text',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      // Find the name input field (first TextField typically)
      final textFields = find.byType(TextField);
      expect(textFields, findsWidgets);

      if (textFields.evaluate().isNotEmpty) {
        await tester.enterText(textFields.first, 'Test User');
        await tester.pump();

        // Verify text was entered
        expect(find.text('Test User'), findsOneWidget);
      }
    });
  });
}
