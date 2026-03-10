import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers.dart';

/// Listens to the backend event WebSocket and shows in-app toast notifications.
///
/// Place this widget once near the top of the widget tree (e.g. inside the shell).
class CubieNotificationOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const CubieNotificationOverlay({super.key, required this.child});

  @override
  ConsumerState<CubieNotificationOverlay> createState() =>
      _CubieNotificationOverlayState();
}

class _CubieNotificationOverlayState extends ConsumerState<CubieNotificationOverlay> {
  final List<_ToastEntry> _visible = [];
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    // Listen to the notification stream and show toasts
    ref.listen<AsyncValue<AppNotification>>(notificationStreamProvider,
        (prev, next) {
      next.whenData((notification) {
        // Add to history
        ref.read(notificationHistoryProvider.notifier).add(notification);
        // Show toast
        _showToast(notification);
      });
    });

    return Stack(
      children: [
        widget.child,
        // Toast overlay
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          child: Column(
            children: _visible
                .map((entry) => _CubieToast(
                      key: ValueKey(entry.id),
                      notification: entry.notification,
                      onDismiss: () => _removeToast(entry.id),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  void _showToast(AppNotification notification) {
    final id = ++_counter;
    final entry = _ToastEntry(id: id, notification: notification);

    setState(() => _visible.add(entry));

    // Auto-dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) _removeToast(id);
    });
  }

  void _removeToast(int id) {
    setState(() => _visible.removeWhere((e) => e.id == id));
  }
}

class _ToastEntry {
  final int id;
  final AppNotification notification;
  const _ToastEntry({required this.id, required this.notification});
}

/// Themed toast card matching AiHomeCloud design system.
class _CubieToast extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onDismiss;

  const _CubieToast({
    super.key,
    required this.notification,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key!,
      direction: DismissDirection.horizontal,
      onDismissed: (_) => onDismiss(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: notification.color.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: notification.color.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: notification.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                notification.icon,
                color: notification.color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    notification.title,
                    style: GoogleFonts.sora(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.body,
                    style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDismiss,
              child: const Icon(
                Icons.close_rounded,
                color: AppColors.textMuted,
                size: 18,
              ),
            ),
          ],
        ),
      ).animate().slideY(begin: -1, duration: 300.ms, curve: Curves.easeOut).fadeIn(duration: 300.ms),
    );
  }
}
