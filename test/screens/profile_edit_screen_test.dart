import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/l10n/app_localizations.dart';
import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/services/auth_session.dart';
import 'package:aihomecloud/screens/main/profile_edit_screen.dart';

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
          home: ProfileEditScreen(),
        ),
      );

  testWidgets('renders without crashing when no session',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();
    // Allow background _loadProfileSilently to settle (silently catches errors)
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ProfileEditScreen), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pre-populates name from auth session',
      (WidgetTester tester) async {
    final notifier = AuthSessionNotifier(prefs);
    await notifier.login(
      host: '192.168.1.100',
      port: 8443,
      token: 'test-token',
      refreshToken: 'test-refresh',
      username: 'Alice',
      isAdmin: false,
      iconEmoji: '🦊',
    );

    final overrides = [
      authSessionProvider.overrideWith((ref) => notifier),
    ];
    await tester.pumpWidget(buildSubject(overrides));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Name field should be pre-populated
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Alice'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('contains emoji picker', (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject([]));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // EmojiPickerGrid should be present
    expect(find.byType(ProfileEditScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
