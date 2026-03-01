import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../screens/main/dashboard_screen.dart';
import '../screens/main/family_screen.dart';
import '../screens/main/file_preview_screen.dart';
import '../screens/main/folder_view_screen.dart';
import '../screens/main/my_folder_screen.dart';
import '../screens/main/settings_screen.dart';
import '../screens/main/shared_folder_screen.dart';
import '../screens/main/storage_explorer_screen.dart';
import '../screens/onboarding/discovery_screen.dart';
import '../screens/onboarding/qr_scan_screen.dart';
import '../screens/onboarding/setup_complete_screen.dart';
import '../screens/onboarding/splash_screen.dart';
import '../screens/onboarding/welcome_screen.dart';
import 'main_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      // ── Onboarding ────────────────────────────────────────────────────────
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/qr-scan', builder: (_, __) => const QrScanScreen()),
      GoRoute(path: '/discovery', builder: (_, __) => const DiscoveryScreen()),
      GoRoute(
          path: '/setup', builder: (_, __) => const SetupCompleteScreen()),

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
            path: '/my-folder',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: MyFolderScreen()),
          ),
          GoRoute(
            path: '/family',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: FamilyScreen()),
          ),
          GoRoute(
            path: '/shared',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: SharedFolderScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: SettingsScreen()),
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

      // ── File preview (pushed on top, no bottom nav) ────────────────────────
      GoRoute(
        path: '/file-preview',
        builder: (_, state) {
          final file = state.extra as FileItem;
          return FilePreviewScreen(file: file);
        },
      ),
    ],
  );
});
