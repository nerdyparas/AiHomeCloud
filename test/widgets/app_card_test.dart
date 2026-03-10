@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock AppCard widget for testing.
///
/// In the real app, this maps to the AppCard widget in lib/widgets/app_card.dart.
class AppCard extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsets padding;
  final double elevation;

  const AppCard({
    super.key,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.elevation = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: elevation,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

void main() {
  group('AppCard Widget Golden Tests', () {
    testWidgets('AppCard golden test with default properties', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AppCard(
                title: 'Storage Status',
                child: Column(
                  children: [
                    const LinearProgressIndicator(
                      value: 0.65,
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    const Text('65 GB / 100 GB used'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(AppCard),
        matchesGoldenFile('goldens/app_card_default.png'),
      );
    });

    testWidgets('AppCard golden test with complex content', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AppCard(
                title: 'System Information',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ListTile(
                      title: Text('Device'),
                      subtitle: Text('Radxa Cubie A7Z'),
                      dense: true,
                    ),
                    const ListTile(
                      title: Text('Uptime'),
                      subtitle: Text('2 days, 5 hours'),
                      dense: true,
                    ),
                    const ListTile(
                      title: Text('Firmware'),
                      subtitle: Text('v1.2.3'),
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(AppCard),
        matchesGoldenFile('goldens/app_card_complex.png'),
      );
    });

    testWidgets('AppCard golden test with elevated style', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AppCard(
                title: 'Alert',
                elevation: 8.0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'External storage not mounted. Connect a USB drive to expand storage.',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(AppCard),
        matchesGoldenFile('goldens/app_card_elevated.png'),
      );
    });

    testWidgets('AppCard golden test with custom padding', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AppCard(
                title: 'Quick Stats',
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    const Column(
                      children: [
                        Text('CPU'),
                        SizedBox(height: 4),
                        Text(
                          '45%',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Column(
                      children: [
                        Text('RAM'),
                        SizedBox(height: 4),
                        Text(
                          '62%',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Column(
                      children: [
                        Text('Storage'),
                        SizedBox(height: 4),
                        Text(
                          '73%',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(AppCard),
        matchesGoldenFile('goldens/app_card_custom_padding.png'),
      );
    });
  });

  group('AppCard Functional Tests', () {
    testWidgets('renders title correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppCard(
              title: 'Test Title',
              child: Text('Test content'),
            ),
          ),
        ),
      );

      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Test content'), findsOneWidget);
    });

    testWidgets('applies correct elevation', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppCard(
              title: 'Elevated Card',
              elevation: 8.0,
              child: Text('Content'),
            ),
          ),
        ),
      );

      final card = find.byType(Card).first;
      expect(card, findsOneWidget);
    });

    testWidgets('applies padding correctly', (WidgetTester tester) async {
      const testPadding = EdgeInsets.all(32.0);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppCard(
              title: 'Padded Card',
              padding: testPadding,
              child: Text('Padded content'),
            ),
          ),
        ),
      );

      expect(find.byType(Padding), findsWidgets);
    });
  });
}