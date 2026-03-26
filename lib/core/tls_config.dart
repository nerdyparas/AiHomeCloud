/// Shared mutable TLS configuration for the device self-signed cert bypass.
///
/// [trustedDeviceHost] is set from two places:
///   - main.dart: reads the saved IP from SharedPreferences at startup
///   - AuthSessionNotifier: updates on login/logout
///
/// Keeping this in its own file avoids circular imports between main.dart
/// and auth_session.dart.
String? trustedDeviceHost;
