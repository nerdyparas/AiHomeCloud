import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/l10n/app_localizations.dart';
import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/widgets/folder_view.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildSubject({
    String title = 'My Files',
    String folderPath = '/personal/alice',
    bool readOnly = false,
    bool showHeader = true,
    List<Override> overrides = const [],
  }) =>
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...overrides,
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FolderView(
              title: title,
              folderPath: folderPath,
              readOnly: readOnly,
              showHeader: showHeader,
            ),
          ),
        ),
      );

  // FolderView calls apiServiceProvider.listFiles() in initState.
  // Without a server, it lands in error state.

  testWidgets('renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject());
    // pumpAndSettle would hang on animations; use explicit pumps
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(FolderView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without crashing during initial load',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.byType(FolderView), findsOneWidget);
    // Allow async file load to settle into error state
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles read-only mode property',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject(readOnly: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(FolderView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
