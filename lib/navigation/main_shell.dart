import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers.dart';
import '../widgets/notification_listener.dart';

final _notificationsPlugin = FlutterLocalNotificationsPlugin();

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

  // Task 5: away-from-home
  bool _awaySheetDismissed = false;
  bool _notifyWhenBack = false;
  Timer? _awayTimer;
  Timer? _pingTimer;

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _notificationsPlugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  int _indexOf(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/dashboard')) return 0;
    if (loc.startsWith('/files')) return 1;
    if (loc.startsWith('/more') || loc.startsWith('/family')) return 2;
    return 0;
  }

  @override
  void dispose() {
    _disconnectTimer?.cancel();
    _awayTimer?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idx = _indexOf(context);
    final connection = ref.watch(connectionProvider);
    final upload = ref.watch(shareUploadProvider);

    // Away-from-home bottom sheet logic
    ref.listen<ConnectionStatus>(connectionProvider, (prev, next) {
      if (next == ConnectionStatus.disconnected) {
        // Show away sheet after a brief delay (ConnectionNotifier already
        // debounces 10s before emitting `disconnected`)
        _awayTimer ??= Timer(const Duration(seconds: 2), () {
          _awayTimer = null;
          if (mounted && !_awaySheetDismissed) _showAwaySheet();
        });
      } else {
        _awayTimer?.cancel();
        _awayTimer = null;
        if (prev == ConnectionStatus.disconnected) {
          // Connection restored — reset dismissed state for next outage
          setState(() => _awaySheetDismissed = false);
          _pingTimer?.cancel();
          _pingTimer = null;
        }
      }
    });

    // Debounce disconnect banner â€” only show after 12 continuous seconds
    if (connection == ConnectionStatus.disconnected) {
      _disconnectTimer ??= Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _showDisconnected = true);
      });
    } else {
      _disconnectTimer?.cancel();
      _disconnectTimer = null;
      if (_showDisconnected) {
        _showDisconnected = false;
      }
    }

    return AhcNotificationOverlay(
      child: Scaffold(
        body: Column(
          children: [
            if (connection == ConnectionStatus.reconnecting)
              Semantics(
                label: 'Reconnecting to AiHomeCloud',
                liveRegion: true,
                child: Container(
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
                    Text(AppLocalizations.of(context)!.shellReconnecting),
                  ],
                ),
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
                      AppLocalizations.of(context)!.shellUploadingProgress(upload.done, upload.total),
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
                      AppLocalizations.of(context)!.shellUploadComplete(upload.done, upload.total),
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.shellNotReachable,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppLocalizations.of(context)!.shellCheckWifi,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => context.go('/scan-network'),
                        icon: const Icon(Icons.wifi_find_rounded, size: 14),
                        label: Text(AppLocalizations.of(context)!.shellReconnect, style: const TextStyle(fontSize: 12)),
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
                context.go('/more');
            }
          },
          destinations: [
            _dest(Icons.home_outlined, Icons.home_rounded,
                AppLocalizations.of(context)!.navHome, idx == 0),
            _dest(Icons.folder_outlined, Icons.folder_rounded,
                AppLocalizations.of(context)!.navMyFiles, idx == 1),
            _dest(Icons.more_horiz_rounded, Icons.more_horiz_rounded,
                AppLocalizations.of(context)!.navMore, idx == 2),
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
          size: 22,
          semanticLabel: label),
      selectedIcon: Icon(activeIcon, color: AppColors.primary, size: 22,
          semanticLabel: label),
      label: label,
      tooltip: label,
    );
  }

  // ── Task 5: away-from-home helpers ──────────────────────────────────────

  void _showAwaySheet() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: AppColors.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Away from home?',
                      style: GoogleFonts.sora(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'AiHomeCloud hasn\u2019t been reachable for a while. You may be outside your home network.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Notify me when I\u2019m back',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Switch(
                      value: _notifyWhenBack,
                      activeTrackColor: AppColors.primary,
                      onChanged: (value) {
                        setSheetState(() {});
                        setState(() => _notifyWhenBack = value);
                        if (value) {
                          _startPingTimer();
                        } else {
                          _pingTimer?.cancel();
                          _pingTimer = null;
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() => _awaySheetDismissed = true);
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Dismiss'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (!mounted) { timer.cancel(); return; }
      final host = ref.read(apiServiceProvider).host;
      if (host == null) return;
      final alive = await _ping(host);
      if (alive) {
        timer.cancel();
        _pingTimer = null;
        if (mounted) setState(() => _notifyWhenBack = false);
        _fireReconnectedNotification();
      }
    });
  }

  Future<bool> _ping(String host) async {
    try {
      final socket = await Socket.connect(
        host,
        AppConstants.apiPort,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _fireReconnectedNotification() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'ahc_reconnect',
        'Connection Restored',
        channelDescription: 'Alerts when AiHomeCloud becomes reachable again',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _notificationsPlugin.show(
      0,
      'AiHomeCloud is back 🏠',
      'Your home server is reachable again.',
      details,
    );
  }
}
