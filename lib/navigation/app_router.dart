import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
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
import '../screens/onboarding/network_scan_screen.dart';
import '../screens/onboarding/pin_entry_screen.dart';
import '../screens/onboarding/splash_screen.dart';
import '../providers.dart';
import 'main_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authSession = ref.watch(authSessionProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (_, state) {
      final loc = state.matchedLocation;
      final onOnboarding =
          loc == '/' || loc == '/scan-network' || loc == '/pin-entry';

      if (authSession == null && !onOnboarding) {
        return '/';
      }

      // Allow /scan-network when authenticated (for reconnection)
      if (authSession != null && onOnboarding && loc != '/scan-network') {
        return '/dashboard';
      }

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
