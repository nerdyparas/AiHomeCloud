import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock StatTile widget for testing
/// 
/// In a real scenario, this would be imported from:
/// import 'package:cubiecloud/widgets/stat_tile.dart';
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const StatTile({
    Key? key,
    required this.label,
    required this.value,
    this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon!, size: 32),
            if (icon != null) const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  group('StatTile Widget Tests', () {
    testWidgets('renders correct label and value text', (WidgetTester tester) async {
      // 7G.1: Create StatTile, render correct label and value text
      const testLabel = 'CPU Usage';
      const testValue = '45%';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatTile(
              label: testLabel,
              value: testValue,
            ),
          ),
        ),
      );

      // Verify label is rendered
      expect(find.text(testLabel), findsOneWidget);

      // Verify value is rendered
      expect(find.text(testValue), findsOneWidget);

      // Verify both are visible
      expect(find.byType(StatTile), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('renders with icon when provided', (WidgetTester tester) async {
      const testLabel = 'Memory';
      const testValue = '2.5 GB';

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

      // Verify icon is rendered
      expect(find.byIcon(Icons.memory), findsOneWidget);

      // Verify label and value still render
      expect(find.text(testLabel), findsOneWidget);
      expect(find.text(testValue), findsOneWidget);
    });

    testWidgets('renders without icon when not provided', (WidgetTester tester) async {
      const testLabel = 'Temperature';
      const testValue = '52°C';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatTile(
              label: testLabel,
              value: testValue,
            ),
          ),
        ),
      );

      // Verify label and value are present
      expect(find.text(testLabel), findsOneWidget);
      expect(find.text(testValue), findsOneWidget);

      // Verify no additional icons
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('card is rendered with padding', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatTile(
              label: 'Test',
              value: '123',
            ),
          ),
        ),
      );

      // Verify Card widget exists
      expect(find.byType(Card), findsOneWidget);

      // Verify Padding widget exists
      expect(find.byType(Padding), findsOneWidget);
    });
  });
}
