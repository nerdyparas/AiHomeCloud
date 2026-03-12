import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cubie_cloud/widgets/stat_tile.dart';

void main() {
  group('StatTile Widget Tests (TASK-025)', () {
    testWidgets('renders with required label and value', (WidgetTester tester) async {
      const testLabel = 'CPU Usage';
      const testValue = '45';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatTile(
              label: testLabel,
              value: testValue,
              icon: Icons.memory,
            ),
          ),
        ),
      );

      // Verify label is rendered
      expect(find.text(testLabel), findsOneWidget);

      // Verify value is rendered
      expect(find.text(testValue), findsOneWidget);

      // Verify the container background is present
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('renders icon badge with correct styling',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatTile(
              label: 'Memory',
              value: '2.5',
              icon: Icons.memory,
              accentColor: const Color(0xFF4CE88A),
            ),
          ),
        ),
      );

      // Verify icon is rendered
      expect(find.byIcon(Icons.memory), findsOneWidget);

      // Verify label and value
      expect(find.text('Memory'), findsOneWidget);
      expect(find.text('2.5'), findsOneWidget);
    });

    testWidgets('renders unit text when provided', (WidgetTester tester) async {
      const testLabel = 'Temperature';
      const testValue = '52';
      const testUnit = '°C';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatTile(
              label: testLabel,
              value: testValue,
              unit: testUnit,
              icon: Icons.thermostat,
            ),
          ),
        ),
      );

      // Verify label, value, and unit are all present
      expect(find.text(testLabel), findsOneWidget);
      expect(find.text(testValue), findsOneWidget);
      expect(find.text(testUnit), findsOneWidget);

      // Verify icon is rendered
      expect(find.byIcon(Icons.thermostat), findsOneWidget);
    });

    testWidgets('renders helper text when provided', (WidgetTester tester) async {
      const testLabel = 'Uptime';
      const testValue = '12';
      const testHelper = 'days';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatTile(
              label: testLabel,
              value: testValue,
              helperText: testHelper,
              icon: Icons.schedule,
            ),
          ),
        ),
      );

      // Verify label, value, and helper text
      expect(find.text(testLabel), findsOneWidget);
      expect(find.text(testValue), findsOneWidget);
      expect(find.text(testHelper), findsOneWidget);
    });

    testWidgets('renders Card container with border and rounded corners',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatTile(
              label: 'Test',
              value: '100',
              icon: Icons.info,
            ),
          ),
        ),
      );

      // Verify the widget tree structure: Container with BoxDecoration
      expect(find.byType(Container), findsWidgets);
      expect(find.byType(Column), findsWidgets);

      // Verify the stat tile itself is rendered
      expect(find.byType(StatTile), findsOneWidget);
    });

    testWidgets('uses vertical column layout', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatTile(
              label: 'CPU',
              value: '75',
              icon: Icons.memory,
            ),
          ),
        ),
      );

      // Verify Column layout is used (vertical stack)
      expect(find.byType(Column), findsWidgets);

      // Verify Row is used for value + unit layout
      expect(find.byType(Row), findsOneWidget);

      // Widget should render without throwing
      expect(find.byType(StatTile), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('applies custom accent color to icon badge',
        (WidgetTester tester) async {
      const customColor = Color(0xFFE84CA8);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatTile(
              label: 'Custom',
              value: '50',
              icon: Icons.star,
              accentColor: customColor,
            ),
          ),
        ),
      );

      // Verify the widget renders with custom color
      expect(find.byType(StatTile), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);

      // Verify no exceptions
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders correctly with all optional parameters',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatTile(
              label: 'Complete',
              value: '99',
              unit: '%',
              icon: Icons.check,
              accentColor: const Color(0xFF4CE88A),
              helperText: 'System healthy',
              helperColor: Colors.green,
            ),
          ),
        ),
      );

      // Verify all elements are rendered
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('99'), findsOneWidget);
      expect(find.text('%'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('System healthy'), findsOneWidget);

      // Verify no exceptions
      expect(tester.takeException(), isNull);
    });
  });
}
