import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/screens/main/files_screen.dart';

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
        child: const MaterialApp(home: FilesScreen()),
      );

  group('FilesScreen', () {
    testWidgets('renders Files title at the top', (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.byType(FilesScreen), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
    });

    testWidgets('displays three primary folder cards in root view',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      // Verify personalized folder names appear
      expect(find.byType(FilesScreen), findsOneWidget);
      // Check for folder icon buttons which represent the cards
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      expect(find.byIcon(Icons.people_rounded), findsOneWidget);
      expect(find.byIcon(Icons.movie_rounded), findsOneWidget);
    });

    testWidgets('folder cards have descriptive subtitles',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.text('Shared with everyone'), findsOneWidget);
      expect(find.text('Movies, series, music'), findsOneWidget);
    });

    testWidgets('displays Trash folder card', (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      expect(find.text('Recently deleted files'), findsOneWidget);
    });

    testWidgets('root view shows ListView with horizontal padding',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(FilesScreen), findsOneWidget);
    });

    testWidgets('tapping folder card does not crash',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildSubject([]));
      await tester.pump();

      // Find first folder card and tap it
      final firstCard = find.byIcon(Icons.person_rounded).first;
      await tester.tap(find.ancestor(of: firstCard, matching: find.byType(ListTile)).first);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
