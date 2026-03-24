import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../screens/main/auto_backup_screen.dart';
import '../screens/main/dashboard_screen.dart';
import '../screens/main/family_screen.dart';
import '../screens/main/file_preview_screen.dart';
import '../screens/main/files_screen.dart';
import '../screens/main/folder_view_screen.dart';
import '../screens/main/more_screen.dart';
import '../screens/main/settings/device_settings_screen.dart';
import '../screens/main/settings/services_settings_screen.dart';
import '../screens/main/telegram_setup_screen.dart';
import '../screens/main/storage_explorer_screen.dart';
import '../screens/main/profile_edit_screen.dart';
import '../screens/onboarding/network_scan_screen.dart';
import '../screens/onboarding/pin_entry_screen.dart';
import '../screens/onboarding/profile_creation_screen.dart';
import '../screens/onboarding/splash_screen.dart';
import '../providers/core_providers.dart';
import '../providers/discovery_providers.dart';
import '../services/auth_session.dart';
import 'main_shell.dart';

/// Lightweight ChangeNotifier used to trigger GoRouter redirect re-evaluation
/// when auth state changes — without recreating the entire router.
class _RouterRefresher extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresher = _RouterRefresher();

  // Re-run GoRouter's redirect whenever auth state changes.
  // This avoids the bug where watching auth state recreates the GoRouter,
  // resetting the navigation stack to '/' and causing a loading loop.
  ref.listen<AuthSession?>(authSessionProvider, (_, __) => refresher.refresh());

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresher,
    redirect: (_, state) {
      final authSession = ref.read(authSessionProvider);
      final loc = state.matchedLocation;
      final onOnboarding = loc == '/' ||
          loc == '/scan-network' ||
          loc == '/pin-entry' ||
          loc == '/user-picker' ||
          loc == '/profile-creation';

      // Not logged in and trying to access main app → go to splash
      if (authSession == null && !onOnboarding) {
        return '/';
      }

      // /profile-creation requires discovery to have completed first.
      // Only redirect to scan-network if there is no extra data (i.e. a bare
      // navigation with no IP — deep-link or back-stack reconstruction).
      // When extra is present the caller already knows the device IP (e.g.
      // PinEntryScreen "Add User" / first-boot onboarding), so let it through.
      if (loc == '/profile-creation' && authSession == null) {
        final extra = state.extra;
        if (extra is! Map<String, dynamic> || (extra['ip'] as String?)?.isEmpty != false) {
          final discovery = ref.read(discoveryNotifierProvider);
          if (discovery.status != DiscoveryStatus.found) {
            return '/scan-network';
          }
        }
      }

      // Allow /scan-network when authenticated (for reconnection).
      // Splash handles session-exists → user-picker redirect itself.
      return null;
    },
    routes: [
      // ── Onboarding ────────────────────────────────────────────────────────
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/scan-network', builder: (_, __) => const NetworkScanScreen()),
      GoRoute(
        path: '/pin-entry',
        builder: (_, state) {
          final ip = state.extra as String;
          return PinEntryScreen(deviceIp: ip);
        },
      ),
      GoRoute(
        path: '/user-picker',
        builder: (_, state) {
          final ip = state.extra as String;
          return PinEntryScreen(deviceIp: ip);
        },
      ),
      GoRoute(
        path: '/profile-creation',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is! Map<String, dynamic>) {
            // Guard: extra is missing when navigation bypassed the onboarding
            // flow. Redirect to splash so the router can handle it properly.
            return const SplashScreen();
          }
          return ProfileCreationScreen(
            deviceIp: extra['ip'] as String,
            isAddingUser: extra['isAddingUser'] as bool? ?? false,
          );
        },
      ),

      // ── Main app (with bottom navigation shell) ───────────────────────────
      ShellRoute(
        builder: (_, __, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: DashboardScreen()),
          ),
          GoRoute(
            path: '/files',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: FilesScreen()),
          ),
          GoRoute(
            path: '/family',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: FamilyScreen()),
          ),
          GoRoute(
            path: '/more',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: MoreScreen()),
          ),
        ],
      ),

      // ── Standalone folder view (pushed on top, no bottom nav) ─────────────
      GoRoute(
        path: '/folder-view',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return FolderViewScreen(
            title: extra['title'] as String,
            folderPath: extra['folderPath'] as String,
            readOnly: extra['readOnly'] as bool? ?? false,
          );
        },
      ),

      // ── Storage explorer (pushed on top, no bottom nav) ───────────────────
      GoRoute(
        path: '/storage-explorer',
        builder: (_, __) => const StorageExplorerScreen(),
      ),

      // ── Settings sub-screens (pushed on top, no bottom nav) ───────────────
      GoRoute(
        path: '/settings/device',
        builder: (_, __) => const DeviceSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/services',
        builder: (_, __) => const ServicesSettingsScreen(),
      ),

      // ── Telegram setup (pushed on top, no bottom nav) ──────────────────────
      GoRoute(
        path: '/telegram-setup',
        builder: (_, __) => const TelegramSetupScreen(),
      ),

      // ── Profile edit (pushed on top, no bottom nav) ────────────────────────
      GoRoute(
        path: '/profile-edit',
        builder: (_, __) => const ProfileEditScreen(),
      ),
      // ── Auto Backup (pushed on top, no bottom nav) ────────────────────────────
      GoRoute(
        path: '/auto-backup',
        builder: (_, __) => const AutoBackupScreen(),
      ),
      // ── File preview (pushed on top, no bottom nav) ────────────────────────
      GoRoute(
        path: '/file-preview',
        builder: (_, state) {
          final file = state.extra;
          if (file is! FileItem) {
            return const Scaffold(
              body: Center(child: Text('File not found')),
            );
          }
          return FilePreviewScreen(file: file);
        },
      ),
    ],
  );

  ref.onDispose(router.dispose);
  ref.onDispose(refresher.dispose);
  return router;
});
