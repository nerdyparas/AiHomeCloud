/// GoRouter redirect logic tests (P2-Task 24).
///
/// Tests the redirect rules from app_router.dart using a minimal test router
/// with stub routes. This avoids SplashScreen's google_fonts + async timers
/// which are incompatible with the fake-async widget test environment.
///
/// Redirect rules under test:
///   1. Unauthenticated user accessing a main-app route → '/'
///   2. /profile-creation without discovery → '/scan-network'
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/providers/core_providers.dart';
import 'package:aihomecloud/providers/discovery_providers.dart';
import 'package:aihomecloud/services/auth_session.dart';

// ---------------------------------------------------------------------------
// Stub route keys — used to identify where GoRouter ended up.
// ---------------------------------------------------------------------------

const _kSplash = Key('stub-splash');
const _kDashboard = Key('stub-dashboard');
const _kScanNetwork = Key('stub-scan-network');
const _kProfileCreation = Key('stub-profile-creation');

// ---------------------------------------------------------------------------
// Helper — build a minimal test app with the same redirect logic as
// app_router.dart but using stub Text widgets (no google_fonts, no timers).
// ---------------------------------------------------------------------------

Widget _buildTestApp({
  required SharedPreferences prefs,
  DiscoveryState discoveryState = const DiscoveryState(),
  String initialLocation = '/',
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authSessionProvider.overrideWith((_) => AuthSessionNotifier(prefs)),
      discoveryNotifierProvider.overrideWith(
          (ref) => _StaticDiscoveryNotifier(discoveryState)),
    ],
    child: _TestApp(
      initialLocation: initialLocation,
      discoveryState: discoveryState,
    ),
  );
}

class _TestApp extends ConsumerWidget {
  const _TestApp({
    required this.initialLocation,
    required this.discoveryState,
  });

  final String initialLocation;
  final DiscoveryState discoveryState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authSession = ref.watch(authSessionProvider);
    final discovery = ref.watch(discoveryNotifierProvider);

    final router = GoRouter(
      initialLocation: initialLocation,
      redirect: (_, state) {
        final loc = state.matchedLocation;
        const onboardingRoutes = {
          '/',
          '/scan-network',
          '/pin-entry',
          '/user-picker',
          '/profile-creation',
        };
        if (authSession == null && !onboardingRoutes.contains(loc)) {
          return '/';
        }
        if (loc == '/profile-creation' && authSession == null) {
          final extra = state.extra;
          final hasIp = extra is Map<String, dynamic> &&
              (extra['ip'] as String?)?.isNotEmpty == true;
          if (!hasIp && discovery.status != DiscoveryStatus.found) {
            return '/scan-network';
          }
        }
        return null;
      },
      routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => const Text('splash', key: _kSplash)),
        GoRoute(
            path: '/scan-network',
            builder: (_, __) =>
                const Text('scan-network', key: _kScanNetwork)),
        GoRoute(
            path: '/pin-entry',
            builder: (_, __) => const Text('pin-entry')),
        GoRoute(
            path: '/user-picker',
            builder: (_, __) => const Text('user-picker')),
        GoRoute(
            path: '/profile-creation',
            builder: (_, __) =>
                const Text('profile-creation', key: _kProfileCreation)),
        GoRoute(
            path: '/dashboard',
            builder: (_, __) =>
                const Text('dashboard', key: _kDashboard)),
      ],
    );

    return MaterialApp.router(routerConfig: router);
  }
}

class _StaticDiscoveryNotifier extends StateNotifier<DiscoveryState>
    implements DiscoveryNotifier {
  _StaticDiscoveryNotifier(DiscoveryState initial) : super(initial);

  @override
  Future<void> startDiscovery(String serial, String key) async {}

  @override
  Future<void> trustFingerprint(String fingerprint) async {}

  @override
  void reset() => state = const DiscoveryState();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Router redirects — unauthenticated', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    testWidgets('initial location / shows splash stub', (tester) async {
      await tester.pumpWidget(_buildTestApp(prefs: prefs));
      await tester.pump();

      expect(find.byKey(_kSplash), findsOneWidget);
    });

    testWidgets('unauthenticated /dashboard is redirected to splash',
        (tester) async {
      await tester.pumpWidget(
          _buildTestApp(prefs: prefs, initialLocation: '/dashboard'));
      await tester.pump();

      // GoRouter redirect should send unauthenticated user to '/'.
      expect(find.byKey(_kSplash), findsOneWidget);
      expect(find.byKey(_kDashboard), findsNothing);
    });
  });

  group('Router redirect — /profile-creation guard', () {
    testWidgets(
        '/profile-creation without discovery redirects to /scan-network',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const idleDiscovery = DiscoveryState(status: DiscoveryStatus.idle);

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        discoveryState: idleDiscovery,
        initialLocation: '/profile-creation',
      ));
      await tester.pump();

      // No discovery → redirect to /scan-network.
      expect(find.byKey(_kScanNetwork), findsOneWidget);
      expect(find.byKey(_kProfileCreation), findsNothing);
    });

    testWidgets(
        '/profile-creation with found discovery is NOT redirected',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const foundDiscovery = DiscoveryState(
        status: DiscoveryStatus.found,
        deviceIp: '192.168.0.10',
      );

      await tester.pumpWidget(_buildTestApp(
        prefs: prefs,
        discoveryState: foundDiscovery,
        initialLocation: '/profile-creation',
      ));
      await tester.pump();

      expect(find.byKey(_kProfileCreation), findsOneWidget);
    });
  });
}
