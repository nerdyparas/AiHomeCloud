import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/models/models.dart';
import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/providers/device_providers.dart';
import 'package:aihomecloud/screens/main/settings/device_settings_screen.dart';

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
        child: const MaterialApp(home: DeviceSettingsScreen()),
      );

  testWidgets('shows loading indicator while device info loads',
      (WidgetTester tester) async {
    final overrides = [
      deviceInfoProvider.overrideWith(
        (ref) => Future<AhcDevice>.delayed(const Duration(days: 9999)),
      ),
    ];
    await tester.pumpWidget(buildSubject(overrides));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('shows error text when device info fails',
      (WidgetTester tester) async {
    final overrides = [
      deviceInfoProvider
          .overrideWith((ref) async => throw Exception('connection refused')),
    ];
    await tester.pumpWidget(buildSubject(overrides));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DeviceSettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders device information when data is available',
      (WidgetTester tester) async {
    const mockDevice = AhcDevice(
      serial: 'AHC-TEST-001',
      name: 'My AiHomeCloud',
      ip: '192.168.1.42',
      firmwareVersion: '2.1.0',
    );

    final overrides = [
      deviceInfoProvider.overrideWith((ref) async => mockDevice),
    ];
    await tester.pumpWidget(buildSubject(overrides));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('My AiHomeCloud'), findsWidgets);
    expect(find.text('AHC-TEST-001'), findsOneWidget);
    expect(find.text('192.168.1.42'), findsOneWidget);
    expect(find.text('2.1.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
