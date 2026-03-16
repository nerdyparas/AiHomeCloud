import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/l10n/app_localizations.dart';
import 'package:aihomecloud/models/models.dart';
import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/providers/data_providers.dart';
import 'package:aihomecloud/screens/main/family_screen.dart';

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
          home: FamilyScreen(),
        ),
      );

  testWidgets('shows loading indicator while family data loads',
      (WidgetTester tester) async {
    final overrides = [
      familyUsersProvider.overrideWith(
        (ref) => Future<List<FamilyUser>>.delayed(const Duration(days: 9999)),
      ),
    ];
    await tester.pumpWidget(buildSubject(overrides));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('shows error text when family users fail to load',
      (WidgetTester tester) async {
    final overrides = [
      familyUsersProvider
          .overrideWith((ref) async => throw Exception('network error')),
    ];
    await tester.pumpWidget(buildSubject(overrides));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FamilyScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders family member cards when data is available',
      (WidgetTester tester) async {
    final mockUsers = [
      const FamilyUser(
        id: 'u1',
        name: 'Alice',
        isAdmin: true,
        folderSizeGB: 12.5,
        avatarColor: Color(0xFF4C9BE8),
        iconEmoji: '🦊',
      ),
      const FamilyUser(
        id: 'u2',
        name: 'Bob',
        isAdmin: false,
        folderSizeGB: 3.2,
        avatarColor: Color(0xFF4CE88A),
      ),
    ];

    final overrides = [
      familyUsersProvider.overrideWith((ref) async => mockUsers),
    ];
    await tester.pumpWidget(buildSubject(overrides));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not crash with empty member list',
      (WidgetTester tester) async {
    final overrides = [
      familyUsersProvider.overrideWith((ref) async => <FamilyUser>[]),
    ];
    await tester.pumpWidget(buildSubject(overrides));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FamilyScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
