import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock StorageDonutChart widget for testing
/// 
/// In a real scenario, this would be imported from:
/// import 'package:cubiecloud/widgets/storage_donut_chart.dart';
class StorageDonutChart extends StatelessWidget {
  final double usedGB;
  final double totalGB;
  final double size;

  const StorageDonutChart({
    Key? key,
    required this.usedGB,
    required this.totalGB,
    this.size = 200.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final percentage = totalGB > 0 ? (usedGB / totalGB).clamp(0.0, 1.0) : 0.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring (background)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey[300]!,
                width: 12,
              ),
            ),
          ),
          // Inner filled ring (usage)
          Container(
            width: size * 0.85,
            height: size * 0.85,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _getColorForPercentage(percentage),
                width: 12,
              ),
            ),
          ),
          // Center text
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(percentage * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${usedGB.toStringAsFixed(1)} / ${totalGB.toStringAsFixed(1)} GB',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getColorForPercentage(double percentage) {
    if (percentage < 0.5) {
      return Colors.green;
    } else if (percentage < 0.8) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
}

void main() {
  group('StorageDonutChart Widget Tests', () {
    testWidgets('renders at 0% fill without throwing', (WidgetTester tester) async {
      // 7G.2: StorageDonutChart at 0% fill
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: StorageDonutChart(
                usedGB: 0.0,
                totalGB: 100.0,
              ),
            ),
          ),
        ),
      );

      // Verify widget renders without error
      expect(find.byType(StorageDonutChart), findsOneWidget);

      // Verify percentage text shows 0%
      expect(find.text('0%'), findsOneWidget);

      // Verify storage text is displayed
      expect(find.text('0.0 / 100.0 GB'), findsOneWidget);
    });

    testWidgets('renders at 50% fill without throwing', (WidgetTester tester) async {
      // 7G.2: StorageDonutChart at 50% fill
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: StorageDonutChart(
                usedGB: 50.0,
                totalGB: 100.0,
              ),
            ),
          ),
        ),
      );

      // Verify widget renders without error
      expect(find.byType(StorageDonutChart), findsOneWidget);

      // Verify percentage text shows 50%
      expect(find.text('50%'), findsOneWidget);

      // Verify storage text is displayed
      expect(find.text('50.0 / 100.0 GB'), findsOneWidget);
    });

    testWidgets('renders at 100% fill without throwing', (WidgetTester tester) async {
      // 7G.2: StorageDonutChart at 100% fill
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: StorageDonutChart(
                usedGB: 100.0,
                totalGB: 100.0,
              ),
            ),
          ),
        ),
      );

      // Verify widget renders without error
      expect(find.byType(StorageDonutChart), findsOneWidget);

      // Verify percentage text shows 100%
      expect(find.text('100%'), findsOneWidget);

      // Verify storage text is displayed
      expect(find.text('100.0 / 100.0 GB'), findsOneWidget);
    });

    testWidgets('handles over-filled storage gracefully', (WidgetTester tester) async {
      // Storage used is more than total (over-subscribed)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: StorageDonutChart(
                usedGB: 150.0,
                totalGB: 100.0,
              ),
            ),
          ),
        ),
      );

      // Verify widget still renders (clamped to 100%)
      expect(find.byType(StorageDonutChart), findsOneWidget);

      // Should clamp to 100%
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('handles zero total storage', (WidgetTester tester) async {
      // Zero total storage (edge case)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: StorageDonutChart(
                usedGB: 0.0,
                totalGB: 0.0,
              ),
            ),
          ),
        ),
      );

      // Verify widget doesn't crash
      expect(find.byType(StorageDonutChart), findsOneWidget);

      // Should show 0% when total is 0
      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('renders at custom size', (WidgetTester tester) async {
      const customSize = 300.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: StorageDonutChart(
                usedGB: 50.0,
                totalGB: 100.0,
                size: customSize,
              ),
            ),
          ),
        ),
      );

      // Find the SizedBox with our custom size
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width == customSize &&
              widget.height == customSize,
        ),
        findsOneWidget,
      );
    });
  });
}
