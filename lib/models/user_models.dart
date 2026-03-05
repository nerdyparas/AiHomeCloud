/// User and pairing models — FamilyUser, QrPairPayload.
///
/// Used by family management and onboarding QR-code pairing screens.
import 'package:flutter/material.dart';

class FamilyUser {
  final String id;
  final String name;
  final bool isAdmin;
  final double folderSizeGB;
  final Color avatarColor;

  const FamilyUser({
    required this.id,
    required this.name,
    required this.isAdmin,
    required this.folderSizeGB,
    required this.avatarColor,
  });
}

class QrPairPayload {
  final String serial;
  final String key;
  final String host;
  final int? expiresAt;

  const QrPairPayload({
    required this.serial,
    required this.key,
    required this.host,
    this.expiresAt,
  });

  factory QrPairPayload.fromUri(Uri uri) {
    final rawExpires = uri.queryParameters['expiresAt'];
    final expiresTimestamp =
        rawExpires != null ? int.tryParse(rawExpires) : null;
    return QrPairPayload(
      serial: uri.queryParameters['serial'] ?? '',
      key: uri.queryParameters['key'] ?? '',
      host: uri.queryParameters['host'] ?? '',
      expiresAt: expiresTimestamp,
    );
  }

  Duration? get timeUntilExpiry {
    if (expiresAt == null) return null;
    final now = DateTime.now().toUtc();
    final expiry =
        DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000, isUtc: true);
    final diff = expiry.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  bool get isExpired {
    final remaining = timeUntilExpiry;
    return remaining != null && remaining == Duration.zero;
  }
}
