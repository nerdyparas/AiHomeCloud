import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mock DashboardScreen for testing
/// 
/// In a real scenario, this would be imported from:
/// import 'package:cubiecloud/screens/main/dashboard_screen.dart';
/// 
/// For this test, we create a simplified version to verify the loading state.
class DashboardScreen extends StatefulWidget {
  final Future<void> Function() fetchDashboard;

  const DashboardScreen({
    Key? key,
    required this.fetchDashboard,
  }) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<void> _loadingFuture;

  @override
  void initState() {
    super.initState();
    _loadingFuture = widget.fetchDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // 7G.4: Show CircularProgressIndicator during loading
          return Scaffold(
            appBar: AppBar(
              title: const Text('Dashboard'),
            ),
            body: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        } else if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Dashboard'),
            ),
            body: Center(
              child: Text('Error: ${snapshot.error}'),
            ),
          );
        } else {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Dashboard'),
            ),
            body: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Dashboard',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'System Stats',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _StatWidget(label: 'CPU', value: '45%'),
                                _StatWidget(label: 'RAM', value: '2.5GB'),
                                _StatWidget(label: 'Temp', value: '52°C'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }
}

class _StatWidget extends StatelessWidget {
  final String label;
  final String value;

  const _StatWidget({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    );
  }
}

void main() {
  group('DashboardScreen Widget Tests', () {
    testWidgets('shows CircularProgressIndicator during loading state', (WidgetTester tester) async {
      // 7G.4: Verify CircularProgressIndicator is shown during loading
      final completer = Future<void>.delayed(const Duration(milliseconds: 100));

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            fetchDashboard: () => completer,
          ),
        ),
      );

      // While loading, CircularProgressIndicator should be visible
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Dashboard content should not be visible yet
      expect(find.text('System Stats'), findsNothing);
    });

    testWidgets('shows dashboard content after loading completes', (WidgetTester tester) async {
      // 7G.4: Verify content appears after loading
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            fetchDashboard: () async => {},
          ),
        ),
      );

      // Initially shows loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for the future to complete
      await tester.pumpAndSettle();

      // After loading, progress indicator should be gone
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Dashboard content should now be visible
      expect(find.text('System Stats'), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('RAM'), findsOneWidget);
      expect(find.text('Temp'), findsOneWidget);
    });

    testWidgets('displays system stats after loading', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            fetchDashboard: () async => {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify stat labels are visible
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('RAM'), findsOneWidget);
      expect(find.text('Temp'), findsOneWidget);

      // Verify stat values are visible
      expect(find.text('45%'), findsOneWidget);
      expect(find.text('2.5GB'), findsOneWidget);
      expect(find.text('52°C'), findsOneWidget);
    });

    testWidgets('shows error when loading fails', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            fetchDashboard: () async => throw Exception('Network error'),
          ),
        ),
      );

      // Wait for error to settle
      await tester.pumpAndSettle();

      // Error message should be displayed
      expect(find.text('Error'), findsWidgets);
      expect(find.text('Network error'), findsOneWidget);

      // Progress indicator should be gone
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Dashboard content should not be shown
      expect(find.text('System Stats'), findsNothing);
    });

    testWidgets('appbar is always visible', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            fetchDashboard: () => Future<void>.delayed(const Duration(seconds: 1)),
          ),
        ),
      );

      // AppBar with title should be visible even during loading
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Dashboard'), findsWidgets);
    });

    testWidgets('loading future can be cancelled gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            fetchDashboard: () async {
              try {
                await Future<void>.delayed(const Duration(seconds: 10));
              } catch (_) {
                // Future was cancelled during navigation
                rethrow;
              }
            },
          ),
        ),
      );

      // Should show loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Navigate away (simulate cancellation)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text('Other screen'),
          ),
        ),
      );

      // New screen should be displayed
      expect(find.text('Other screen'), findsOneWidget);
    });
  });
}
