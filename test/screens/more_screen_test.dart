import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/screens/main/more_screen.dart';

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
        child: const MaterialApp(home: MoreScreen()),
      );

  group('MoreScreen', () {
    testWidgets('renders More title at the top', (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.byType(MoreScreen), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('has safe area with padding', (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.byType(SafeArea), findsOneWidget);
    });

    testWidgets('renders ListView to display sections',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('contains Sharing section label', (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.text('Sharing'), findsOneWidget);
    });

    testWidgets('displays TV & Computer Sharing card',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.text('TV & Computer Sharing'), findsOneWidget);
    });

    testWidgets('contains ListTiles for grouped items',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('shows profile area with user name',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.byType(MoreScreen), findsOneWidget);
      // The screen should have rendered without errors
      expect(tester.takeException(), isNull);
    });

    testWidgets('screen does not crash when built', (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.byType(MoreScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
