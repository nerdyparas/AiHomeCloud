/// AuthSessionNotifier and ConnectionNotifier tests (TASK-P7-02).
///
/// Covers the critical state machines:
///   - AuthSessionNotifier: login, logout, token update
///   - ConnectionNotifier: grace period debounce before marking disconnected
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aihomecloud/core/constants.dart';
import 'package:aihomecloud/models/models.dart';
import 'package:aihomecloud/providers/device_providers.dart';
import 'package:aihomecloud/services/auth_session.dart';

// ---------------------------------------------------------------------------
// Helper â€” create a fresh notifier backed by an in-memory SharedPreferences
// ---------------------------------------------------------------------------

Future<({AuthSessionNotifier notifier, SharedPreferences prefs})>
    _makeNotifier() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final notifier = AuthSessionNotifier(prefs);
  return (notifier: notifier, prefs: prefs);
}

void main() {
  // ---------------------------------------------------------------------------
  // AuthSessionNotifier â€” login
  // ---------------------------------------------------------------------------

  group('AuthSessionNotifier â€” login', () {
    test('login() sets all session fields on the state', () async {
      final (:notifier, prefs: _) = await _makeNotifier();

      await notifier.login(
        host: '192.168.1.100',
        port: 8443,
        token: 'access-token-abc',
        refreshToken: 'refresh-token-xyz',
        username: 'priya',
        isAdmin: true,
      );

      final session = notifier.state;
      expect(session, isNotNull);
      expect(session!.host, '192.168.1.100');
      expect(session.port, 8443);
      expect(session.token, 'access-token-abc');
      expect(session.refreshToken, 'refresh-token-xyz');
      expect(session.username, 'priya');
      expect(session.isAdmin, true);
    });

    test('login() persists host, port, username to SharedPreferences', () async {
      final (:notifier, :prefs) = await _makeNotifier();

      await notifier.login(
        host: '10.0.0.5',
        port: 8443,
        token: 'tok',
        refreshToken: null,
        username: 'rajan',
        isAdmin: false,
      );

      expect(prefs.getString(AppConstants.prefDeviceIp), '10.0.0.5');
      expect(prefs.getInt(AppConstants.prefDevicePort), 8443);
      expect(prefs.getString(AppConstants.prefUserName), 'rajan');
    });
  });

  // ---------------------------------------------------------------------------
  // AuthSessionNotifier â€” logout
  // ---------------------------------------------------------------------------

  group('AuthSessionNotifier â€” logout', () {
    test('logout() clears all session state fields to null', () async {
      final (:notifier, prefs: _) = await _makeNotifier();

      await notifier.login(
        host: '192.168.1.1',
        port: 8443,
        token: 'tok',
        refreshToken: 'refresh',
        username: 'user1',
        isAdmin: false,
      );

      expect(notifier.state, isNotNull);

      await notifier.logout();

      expect(notifier.state, isNull);
    });

    test('logout() removes token keys from SharedPreferences', () async {
      final (:notifier, :prefs) = await _makeNotifier();

      await notifier.login(
        host: '192.168.1.1',
        port: 8443,
        token: 'tok',
        refreshToken: 'refresh',
        username: 'user1',
        isAdmin: false,
      );

      await notifier.logout();

      expect(prefs.getString(AppConstants.prefAuthToken), isNull);
      expect(prefs.getString(AppConstants.prefRefreshToken), isNull);
      expect(prefs.getString(AppConstants.prefUserName), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // AuthSessionNotifier â€” updateToken
  // ---------------------------------------------------------------------------

  group('AuthSessionNotifier â€” updateToken', () {
    test('updateToken() replaces token without touching other fields', () async {
      final (:notifier, prefs: _) = await _makeNotifier();

      await notifier.login(
        host: '10.0.0.1',
        port: 8443,
        token: 'old-token',
        refreshToken: null,
        username: 'admin',
        isAdmin: true,
      );

      await notifier.updateToken('new-refreshed-token');

      expect(notifier.state!.token, 'new-refreshed-token');
      expect(notifier.state!.username, 'admin');
      expect(notifier.state!.isAdmin, true);
    });

    test('updateToken() is a no-op when not logged in', () async {
      final (:notifier, prefs: _) = await _makeNotifier();

      // Should not throw
      await notifier.updateToken('some-token');

      expect(notifier.state, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // ConnectionNotifier â€” grace period debounce
  // ---------------------------------------------------------------------------

  group('ConnectionNotifier â€” grace period', () {
    test('state does NOT change to disconnected within 9 seconds of failure',
        () {
      fakeAsync((async) {
        final notifier = ConnectionNotifier();
        expect(notifier.state, ConnectionStatus.connected);

        // Simulate connection failure starting reconnect cycle.
        notifier.markReconnectStart();
        expect(notifier.state, ConnectionStatus.reconnecting);

        // Advance 9 seconds â€” grace period still active.
        async.elapse(const Duration(seconds: 9));
        expect(notifier.state, ConnectionStatus.reconnecting,
            reason: 'Should still be reconnecting, not disconnected, at 9s');

        notifier.dispose();
      });
    });

    test('state transitions to disconnected after 10-second grace period', () {
      fakeAsync((async) {
        final notifier = ConnectionNotifier();
        notifier.markReconnectStart();

        // Advance past the 10-second timer.
        async.elapse(const Duration(seconds: 11));
        expect(notifier.state, ConnectionStatus.disconnected,
            reason: 'Should be disconnected after grace period expires');

        notifier.dispose();
      });
    });

    test('markConnected() cancels debounce and resets to connected', () {
      fakeAsync((async) {
        final notifier = ConnectionNotifier();
        notifier.markReconnectStart();

        // Reconnect before the timer fires.
        async.elapse(const Duration(seconds: 5));
        notifier.markConnected();

        // Advancing past where the timer would have fired shouldn't change state.
        async.elapse(const Duration(seconds: 10));
        expect(notifier.state, ConnectionStatus.connected);

        notifier.dispose();
      });
    });
  });
}
