/// Real-time notification models — NotificationSeverity, AppNotification.
///
/// Used by the notification stream (WebSocket /ws/events) and history display.
library;
import 'package:flutter/material.dart';

/// Severity level for in-app notifications.
enum NotificationSeverity { info, success, warning, error }

/// A real-time notification pushed from the backend via /ws/events.
class AppNotification {
  final String type;
  final String title;
  final String body;
  final NotificationSeverity severity;
  final DateTime timestamp;
  final Map<String, dynamic>? data;

  const AppNotification({
    required this.type,
    required this.title,
    required this.body,
    required this.severity,
    required this.timestamp,
    this.data,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      severity: NotificationSeverity.values.firstWhere(
        (s) => s.name == json['severity'],
        orElse: () => NotificationSeverity.info,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        ((json['timestamp'] as num) * 1000).toInt(),
      ),
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  /// Color accent for this severity.
  Color get color => switch (severity) {
        NotificationSeverity.info => const Color(0xFF4C9BE8),
        NotificationSeverity.success => const Color(0xFF4CE88A),
        NotificationSeverity.warning => const Color(0xFFE8A84C),
        NotificationSeverity.error => const Color(0xFFE85C5C),
      };

  /// Icon for this severity.
  IconData get icon => switch (severity) {
        NotificationSeverity.info => Icons.info_outline_rounded,
        NotificationSeverity.success => Icons.check_circle_outline_rounded,
        NotificationSeverity.warning => Icons.warning_amber_rounded,
        NotificationSeverity.error => Icons.error_outline_rounded,
      };
}
