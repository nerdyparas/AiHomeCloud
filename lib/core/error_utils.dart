import 'dart:async';
import 'dart:io';

/// Convert raw exception objects to user-friendly error messages.
///
/// Catches SocketException, TimeoutException, HttpException, and
/// generic Exception wrappers to produce clean, actionable text
/// instead of raw stack traces or class names.
String friendlyError(Object error) {
  final msg = error.toString();

  // ── Network / connectivity ──────────────────────────────────────────────
  if (error is SocketException || msg.contains('SocketException')) {
    if (msg.contains('Connection refused')) {
      return 'AiHomeCloud is not reachable. Make sure it\'s powered on and connected to your network.';
    }
    if (msg.contains('Network is unreachable') ||
        msg.contains('No route to host')) {
      return 'You are not connected to the same network as your AiHomeCloud. Check your Wi-Fi connection.';
    }
    if (msg.contains('Connection reset')) {
      return 'Connection to AiHomeCloud was interrupted. Please try again.';
    }
    return 'Cannot connect to AiHomeCloud. Check that you\'re on the same network.';
  }

  // ── Timeout ─────────────────────────────────────────────────────────────
  if (error is TimeoutException || msg.contains('TimeoutException')) {
    return 'AiHomeCloud is taking too long to respond. It may be busy or unreachable.';
  }

  // ── HTTP errors ─────────────────────────────────────────────────────────
  if (error is HttpException || msg.contains('HttpException')) {
    return 'Communication error with AiHomeCloud. Please try again.';
  }

  // ── HandshakeException (TLS) ────────────────────────────────────────────
  if (msg.contains('HandshakeException') || msg.contains('CERTIFICATE_VERIFY')) {
    return 'Secure connection failed. The device certificate may have changed.';
  }

  // ── ClientException (http package) ──────────────────────────────────────
  if (msg.contains('ClientException')) {
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return 'AiHomeCloud is not reachable. Make sure it\'s powered on and connected to your network.';
    }
    return 'Cannot connect to AiHomeCloud. Check your network connection.';
  }

  // ── StateError (session not configured) ─────────────────────────────────
  if (error is StateError || msg.contains('Host is not configured')) {
    return 'No device paired. Please set up your AiHomeCloud first.';
  }

  // ── Storage conflict — drive already active (HTTP 409) ─────────────────
  if (msg.contains('mounted') &&
      (msg.contains('already') ||
          msg.contains('currently') ||
          msg.contains('unmount'))) {
    return 'Another drive is already active. Safely remove it first.';
  }

  // ── Storage server failure (HTTP 500) ────────────────────────────────────
  if (msg.contains('Internal Server Error')) {
    return 'Could not activate drive. Check the USB connection and try again.';
  }

  // ── HTTP 401 Unauthorized ──────────────────────────────────────────────
  if (msg.contains('401') || msg.contains('Unauthorized')) {
    return 'Please sign in again.';
  }

  // ── Generic Exception wrapper — strip "Exception: " prefix ─────────────
  if (msg.startsWith('Exception: ')) {
    final inner = msg.substring(11);
    // Re-run through the same checks now that the prefix is stripped.
    return friendlyError(Exception(inner));
  }

  // ── Fallback ────────────────────────────────────────────────────────────
  return msg;
}
