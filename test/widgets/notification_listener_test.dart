import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/models/models.dart';
import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/providers/data_providers.dart';
import 'package:aihomecloud/widgets/notification_listener.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildSubject({
    List<Override> overrides = const [],
    Widget child = const Text('Content'),
  }) =>
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // Provide an empty notification stream so ref.listen doesn't crash
          notificationStreamProvider.overrideWith(
            (ref) => const Stream<AppNotification>.empty(),
          ),
          ...overrides,
        ],
        child: MaterialApp(
          home: AhcNotificationOverlay(child: child),
        ),
      );

  testWidgets('renders child widget', (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('Content'), findsOneWidget);
  });

  testWidgets('wraps child in Stack for overlay positioning',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.byType(Stack), findsWidgets);
  });

  testWidgets('shows toast when notification arrives',
      (WidgetTester tester) async {
    final notification = AppNotification(
      type: 'storage_warning',
      title: 'Low Disk Space',
      body: 'Only 5 GB remaining',
      severity: NotificationSeverity.warning,
      timestamp: DateTime(2026, 3, 16),
    );

    final overrides = [
      notificationStreamProvider.overrideWith(
        (ref) => Stream.value(notification),
      ),
    ];
    await tester.pumpWidget(buildSubject(overrides: overrides));
    await tester.pump();
    // Allow stream event to propagate
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Low Disk Space'), findsOneWidget);
    expect(find.text('Only 5 GB remaining'), findsOneWidget);

    // Pump past the 4-second auto-dismiss timer to avoid pending timer error
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('toast auto-dismisses after 4 seconds',
      (WidgetTester tester) async {
    final notification = AppNotification(
      type: 'test',
      title: 'Test Toast',
      body: 'Goes away soon',
      severity: NotificationSeverity.info,
      timestamp: DateTime(2026, 3, 16),
    );

    final overrides = [
      notificationStreamProvider.overrideWith(
        (ref) => Stream.value(notification),
      ),
    ];
    await tester.pumpWidget(buildSubject(overrides: overrides));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Test Toast'), findsOneWidget);

    // Advance past auto-dismiss (4 seconds)
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Test Toast'), findsNothing);
  });

  testWidgets('does not crash with no notifications',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
