import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers.dart';
import '../widgets/notification_listener.dart';

/// Persistent bottom navigation bar shell used by the main app routes.
class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _showDisconnected = false;
  Timer? _disconnectTimer;

  int _indexOf(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/dashboard')) return 0;
    if (loc.startsWith('/files')) return 1;
    if (loc.startsWith('/family')) return 2;
    if (loc.startsWith('/more')) return 3;
    return 0;
  }

  @override
  void dispose() {
    _disconnectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idx = _indexOf(context);
    final connection = ref.watch(connectionProvider);
    final upload = ref.watch(shareUploadProvider);
    final api = ref.read(apiServiceProvider);
    final isRemote = api.connectionMode == ConnectionMode.remote;

    // Debounce disconnect banner — only show after 12 continuous seconds
    if (connection == ConnectionStatus.disconnected) {
      if (_disconnectTimer == null) {
        _disconnectTimer = Timer(const Duration(seconds: 12), () {
          if (mounted) setState(() => _showDisconnected = true);
        });
      }
    } else {
      _disconnectTimer?.cancel();
      _disconnectTimer = null;
      if (_showDisconnected) {
        _showDisconnected = false;
      }
    }

    return CubieNotificationOverlay(
      child: Scaffold(
        body: Column(
          children: [
            if (connection == ConnectionStatus.reconnecting)
              Container(
                width: double.infinity,
                color: AppColors.primary.withValues(alpha: 0.18),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Reconnecting…'),
                  ],
                ),
              ),
            if (isRemote)
              Container(
                width: double.infinity,
                color: AppColors.secondary.withValues(alpha: 0.18),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: const Row(
                  children: [
                    Icon(Icons.vpn_lock_rounded,
                        size: 13, color: AppColors.secondary),
                    SizedBox(width: 6),
                    Text(
                      'via Remote',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.secondary),
                    ),
                  ],
                ),
              ),
            if (upload.active)
              Container(
                width: double.infinity,
                color: AppColors.primary.withValues(alpha: 0.18),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Uploading ${upload.done} of ${upload.total} file(s)…',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              )
            else if (upload.total > 0)
              Container(
                width: double.infinity,
                color: Colors.green.withValues(alpha: 0.18),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 14, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      '${upload.done} of ${upload.total} file(s) saved to AiHomeCloud',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            if (_showDisconnected)
              SafeArea(
                bottom: false,
                child: Container(
                  width: double.infinity,
                  color: AppColors.error.withValues(alpha: 0.2),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.cloud_off_rounded, size: 14, color: AppColors.error),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AiHomeCloud is not reachable.',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Check your Wi-Fi and make sure the device is powered on.',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => context.go('/scan-network'),
                        icon: const Icon(Icons.wifi_find_rounded, size: 14),
                        label: const Text('Reconnect', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(child: widget.child),
          ],
        ),
        bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.cardBorder, width: 1),
          ),
        ),
        child: NavigationBar(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.primary.withValues(alpha: 0.12),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          height: 68,
          selectedIndex: idx,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) {
            switch (i) {
              case 0:
                context.go('/dashboard');
              case 1:
                context.go('/files');
              case 2:
                context.go('/family');
              case 3:
                context.go('/more');
            }
          },
          destinations: [
            _dest(Icons.home_outlined, Icons.home_rounded, 'Home', idx == 0),
            _dest(Icons.folder_outlined, Icons.folder_rounded, 'Files',
                idx == 1),
            _dest(Icons.people_outline_rounded, Icons.people_rounded, 'Family',
                idx == 2),
            _dest(Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More',
                idx == 3),
          ],
        ),
      ),
      ),
    );
  }

  NavigationDestination _dest(
      IconData icon, IconData activeIcon, String label, bool active) {
    return NavigationDestination(
      icon: Icon(icon,
          color: active ? AppColors.primary : AppColors.textMuted,
          size: 22),
      selectedIcon: Icon(activeIcon, color: AppColors.primary, size: 22),
      label: label,
    );
  }
}
