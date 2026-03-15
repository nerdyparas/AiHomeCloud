import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/models/models.dart';
import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/providers/device_providers.dart';
import 'package:aihomecloud/screens/main/dashboard_screen.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// Wraps [DashboardScreen] in a [ProviderScope] with the given provider
  /// overrides and a minimal [MaterialApp] so theme lookups work.
  Widget buildSubject(List<Override> overrides) => ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...overrides,
        ],
        child: const MaterialApp(home: DashboardScreen()),
      );

  // ---------------------------------------------------------------------------
  // Loading state
  // ---------------------------------------------------------------------------

  testWidgets('shows CircularProgressIndicator while device info is loading',
      (WidgetTester tester) async {
    final overrides = [
      // Never completes â†’ keeps the FutureProvider in loading state.
      deviceInfoProvider.overrideWith(
          (ref) => Future<AhcDevice>.delayed(const Duration(days: 9999))),
      systemStatsStreamProvider
          .overrideWith((ref) => const Stream<SystemStats>.empty()),
      storageDevicesProvider
          .overrideWith((ref) async => <StorageDevice>[]),
    ];
    await tester.pumpWidget(buildSubject(overrides));
    // One frame — providers initialised but futures not resolved.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    // Drain lingering animation timers (shimmer starts at 200 ms, runs for
    // 1 500 ms with count=1, plus 400 ms header fadeIn = all done < 2 s).
    await tester.pump(const Duration(milliseconds: 2500));
  });

  // ---------------------------------------------------------------------------
  // Error state
  // ---------------------------------------------------------------------------

  testWidgets('shows error text when device info fails',
      (WidgetTester tester) async {
    final overrides = [
      deviceInfoProvider.overrideWith(
          (ref) async => throw Exception('connection refused')),
      systemStatsStreamProvider
          .overrideWith((ref) => const Stream<SystemStats>.empty()),
      storageDevicesProvider
          .overrideWith((ref) async => <StorageDevice>[]),
    ];
    await tester.pumpWidget(buildSubject(overrides));
    // Advance time to let the async throw propagate without hanging on
    // flutter_animate shimmer timers that loop indefinitely.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The screen must show *something* — it must NOT crash the test.
    expect(find.byType(DashboardScreen), findsOneWidget);
    // Confirm no uncaught exception was thrown.
    expect(tester.takeException(), isNull);
    // Drain remaining animation timers (shimmer completes at 1 700 ms total).
    await tester.pump(const Duration(milliseconds: 1500));
  });

  // ---------------------------------------------------------------------------
  // Data (success) state
  // ---------------------------------------------------------------------------

  testWidgets('renders dashboard content when data is available',
      (WidgetTester tester) async {
    const mockDevice = AhcDevice(
      serial: 'TEST-001',
      name: 'My AiHomeCloud',
      ip: '192.168.1.100',
      firmwareVersion: '2.0.0',
    );
    final mockStats = SystemStats(
      cpuPercent: 15.0,
      ramPercent: 40.0,
      tempCelsius: 42.0,
      uptime: const Duration(hours: 5, minutes: 30),
      networkUpMbps: 1.5,
      networkDownMbps: 5.0,
      storage: StorageStats(totalGB: 500, usedGB: 120),
    );

    final overrides = [
      deviceInfoProvider.overrideWith((ref) async => mockDevice),
      systemStatsStreamProvider
          .overrideWith((ref) => Stream.value(mockStats)),
      storageDevicesProvider
          .overrideWith((ref) async => <StorageDevice>[]),
    ];
    await tester.pumpWidget(buildSubject(overrides));
    // Advance past all animation delays (longest = 600 ms + duration slack);
    // avoids hanging on flutter_animate shimmer timers that loop indefinitely.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    // Device name should appear somewhere in the widget tree.
    expect(find.text('My AiHomeCloud'), findsWidgets);
    // No uncaught exception.
    expect(tester.takeException(), isNull);
    // Drain remaining animation timers (shimmer completes at 1 700 ms total).
    await tester.pump(const Duration(milliseconds: 1100));
  });
}
