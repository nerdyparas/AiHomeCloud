# Fix: Flutter WebSocket Token Expiry & Notification Reconnect

> Agent task — one session, one commit.
> Priority: HIGH — these bugs cause the dashboard stats and notification bell to permanently die after 1 hour without an app restart.

---

## Context

Audit on 2026-03-19 found two related WebSocket bugs in `lib/services/api/system_api.dart`:

1. **`monitorSystemStats()` — reconnect uses a stale JWT**
   The `uri` (which embeds the token) is built *once before the retry loop*. JWTs expire in 1 hour. After expiry, every reconnect attempt hits `code=4003 Invalid token` on the backend, burns through all 30 retries in a few minutes, then the `StreamProvider` closes permanently. The dashboard shows a dead/static state until the app is fully restarted.

2. **`notificationStream()` — no reconnect at all**
   The events WebSocket (`/ws/events`) builds a channel once and wires a `listen()` callback. When the channel closes (network hiccup, token expiry, server restart), `onDone` fires, the `StreamController` is closed, and the stream ends. The `ServicesNetifier` and notification bell never recover. This needs the same retry pattern as `monitorSystemStats`.

---

## Files to change

| File | Change |
|---|---|
| `lib/services/api/system_api.dart` | Fix both WebSocket methods |

No other files need changing.

---

## Exact changes required

### 1. `monitorSystemStats()` — rebuild URI inside retry loop

Move the `uri` construction inside the `while` loop so each reconnect attempt picks up the current (possibly refreshed) token from `_session?.token`.

```dart
Stream<SystemStats> monitorSystemStats({int maxRetries = 30}) async* {
  final host = _session?.host;
  final port = _session?.port ?? AppConstants.apiPort;
  if (host == null || host.isEmpty) {
    throw StateError('Host is not configured in auth session');
  }

  int attempts = 0;
  while (attempts <= maxRetries) {
    // ✅ Rebuild URI on every attempt — picks up refreshed token
    final token = _session?.token;
    final uri = Uri.parse(
      'wss://$host:$port/ws/monitor${token != null ? "?token=$token" : ""}',
    );

    try {
      final channel = IOWebSocketChannel.connect(
        uri,
        customClient: _createPinnedHttpClient(),
      );
      _connectionStatusCallback?.call(ConnectionStatus.connected);

      await for (final raw in channel.stream) {
        attempts = 0;
        _connectionStatusCallback?.call(ConnectionStatus.connected);
        final data = jsonDecode(raw as String);
        yield SystemStats(
          cpuPercent: (data['cpuPercent'] as num).toDouble(),
          ramPercent: (data['ramPercent'] as num).toDouble(),
          tempCelsius: (data['tempCelsius'] as num).toDouble(),
          uptime: Duration(seconds: data['uptimeSeconds'] as int),
          networkUpMbps: (data['networkUpMbps'] as num).toDouble(),
          networkDownMbps: (data['networkDownMbps'] as num).toDouble(),
          storage: StorageStats(
            totalGB: (data['storage']['totalGB'] as num).toDouble(),
            usedGB: (data['storage']['usedGB'] as num).toDouble(),
          ),
        );
      }
      // Channel closed cleanly — no reconnect needed.
      return;
    } catch (_) {
      attempts++;
      if (attempts > maxRetries) {
        _connectionStatusCallback?.call(ConnectionStatus.disconnected);
        return;
      }
      _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
      final backoff = Duration(seconds: (attempts * 2).clamp(2, 30));
      await Future.delayed(backoff);
    }
  }
}
```

---

### 2. `notificationStream()` — add reconnect loop

Replace the current single-shot `listen()` implementation with the same `async*` + retry pattern used by `monitorSystemStats`. Return a `Stream<AppNotification>` from an `async*` generator.

```dart
Stream<AppNotification> notificationStream({int maxRetries = 30}) async* {
  final host = _session?.host;
  final port = _session?.port ?? AppConstants.apiPort;
  if (host == null || host.isEmpty) {
    throw StateError('Host is not configured in auth session');
  }

  int attempts = 0;
  while (attempts <= maxRetries) {
    // Rebuild URI on every attempt — picks up refreshed token
    final token = _session?.token;
    final uri = Uri.parse(
      'wss://$host:$port/ws/events${token != null ? "?token=$token" : ""}',
    );

    try {
      final channel = IOWebSocketChannel.connect(
        uri,
        customClient: _createPinnedHttpClient(),
      );
      _connectionStatusCallback?.call(ConnectionStatus.connected);

      await for (final raw in channel.stream) {
        attempts = 0;
        _connectionStatusCallback?.call(ConnectionStatus.connected);
        final data = jsonDecode(raw as String);
        yield AppNotification.fromJson(data);
      }
      // Clean close — no reconnect
      return;
    } catch (_) {
      attempts++;
      if (attempts > maxRetries) {
        _connectionStatusCallback?.call(ConnectionStatus.disconnected);
        return;
      }
      _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
      final backoff = Duration(seconds: (attempts * 2).clamp(2, 30));
      await Future.delayed(backoff);
    }
  }
}
```

The old `StreamController` / `missedBeats` pattern is fully replaced. Delete it.

---

## Impact on callers

`notificationStream()` already returns `Stream<AppNotification>` so the signature is unchanged. The `notificationStreamProvider` in `lib/providers/data_providers.dart` calls it via:

```dart
final notificationStreamProvider = StreamProvider<AppNotification>((ref) {
  final api = ref.read(apiServiceProvider);
  return api.notificationStream();
});
```

This is compatible with the `async*` version — no changes needed in providers.

---

## Validation

```bash
flutter analyze   # 0 errors
flutter test      # all pass
```

Manually verify by:
1. Connecting to a device, letting the dashboard run for >60 minutes
2. Stats should keep updating after the 1-hour JWT mark (token gets refreshed by the HTTP layer; WS picks it up on next reconnect)
3. Kill and restart the backend — both WebSockets should reconnect automatically

---

## Docs to update after completing

- `kb/flutter-patterns.md` — add a note: "WebSocket streams must rebuild URI inside the retry loop to pick up refreshed tokens"
- `kb/changelog.md` — `2026-03-XX: Fixed WS token expiry on reconnect, added reconnect to notificationStream`
