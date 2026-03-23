# Fix: Quick Wins — WAL Mode, get_local_ip, Bot Supervisor, Unawaited Persist

> Agent task — one session, one commit.
> Priority: LOW-MEDIUM — small effort, meaningful quality improvement.
> All 4 fixes are independent one-liners or tiny function rewrites. Do them all in a single session.

---

## Context

Audit on 2026-03-19 identified 4 low-effort improvements:

1. **SQLite not in WAL mode** (`document_index.py`) — FTS5 searches and concurrent uploads can block each other. WAL mode eliminates this.
2. **`get_local_ip()` requires internet route** (`config.py`) — connects to `8.8.8.8` to discover local IP. Fails silently on internet-less LANs, returning `127.0.0.1`.
3. **Telegram bot supervisor wastes CPU** (`main.py`) — always sleeps before checking if bot is alive. When bot is healthy, this spins pointlessly every 5s resetting `attempt = 0`.
4. **`_persistLogin` is a fire-and-forget future in Flutter** (`auth_session.dart`) — SharedPreferences writes are not awaited. On crash immediately after login, session may not be persisted.

---

## Files to change

| File | Change |
|---|---|
| `backend/app/document_index.py` | Enable WAL mode on new connections |
| `backend/app/config.py` | Rewrite `get_local_ip()` to use interface enumeration |
| `backend/app/main.py` | Fix `_supervise_telegram_bot()` sleep logic |
| `lib/services/auth_session.dart` | Add `unawaited()` annotation to `_persistLogin` call |

---

## Exact changes required

### 1. `document_index.py` — WAL mode

In the `_new_conn()` function, enable WAL journal mode immediately after creating the connection:

```python
def _new_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(str(_db_path()), timeout=10, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")   # ← add this line
    conn.execute("PRAGMA synchronous=NORMAL") # ← safe with WAL; faster than FULL
    return conn
```

`PRAGMA synchronous=NORMAL` is safe with WAL and gives a meaningful throughput boost on the SD card / NVMe on ARM hardware without sacrificing durability.

---

### 2. `config.py` — rewrite `get_local_ip()`

The current implementation requires a working route to the internet. Replace it with an interface-based approach:

```python
def get_local_ip() -> str:
    """Get the device's primary local IP address.

    Tries interface enumeration first (works on LAN-only devices).
    Falls back to routing-based discovery, then 127.0.0.1.
    """
    import socket

    # Method 1: Enumerate interfaces and pick first non-loopback IPv4.
    # Works even when there's no default route to the internet.
    try:
        import socket as _socket
        hostname = _socket.gethostname()
        addrs = _socket.getaddrinfo(hostname, None, _socket.AF_INET)
        for addr in addrs:
            ip = addr[4][0]
            if not ip.startswith("127.") and not ip.startswith("169.254."):
                return ip
    except Exception:
        pass

    # Method 2: Routing-based (original approach — requires default route).
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"
```

---

### 3. `main.py` — fix Telegram bot supervisor

The current supervisor always sleeps first, then checks. Restructure so it checks health continuously with a shorter poll interval and only does the backoff sleep when the bot is actually down:

```python
async def _supervise_telegram_bot() -> None:
    """Watch the Telegram bot task and restart on crash with exponential backoff."""
    from .telegram_bot import start_bot as _start_bot
    from .config import settings as _settings

    if not _settings.telegram_bot_token:
        return

    attempt = 0
    while True:
        await asyncio.sleep(10)  # health-check poll interval (not a backoff sleep)

        from . import telegram_bot as _tb_mod
        if _tb_mod._application is not None:
            attempt = 0  # bot is healthy — reset counter
            continue

        # Bot is down — apply backoff before attempting restart
        attempt += 1
        if attempt > _BOT_MAX_RESTARTS:
            logger.error(
                "Telegram bot supervisor giving up after %d restart attempts",
                _BOT_MAX_RESTARTS,
            )
            return

        delay = _BOT_BACKOFF_SCHEDULE[min(attempt - 1, len(_BOT_BACKOFF_SCHEDULE) - 1)]
        logger.warning(
            "Telegram bot down — restart attempt %d/%d, waiting %ds",
            attempt, _BOT_MAX_RESTARTS, delay,
        )
        await asyncio.sleep(delay)

        try:
            await _start_bot()
            if _tb_mod._application is not None:
                logger.info("Telegram bot recovered after %d attempt(s)", attempt)
                attempt = 0
        except Exception as exc:
            logger.error("Telegram bot restart failed: %s", exc)
```

Key changes:
- Poll interval is a flat 10s, not the backoff schedule
- Backoff sleep only happens when the bot is actually down
- `_BOT_BACKOFF_SCHEDULE` is still used for time between restart *attempts*
- Remove the `attempt < _BOT_MAX_RESTARTS` condition from `while` — handled inside loop

---

### 4. `auth_session.dart` — annotate unawaited persist

`_persistLogin` is intentionally fire-and-forget (to avoid blocking navigation). The call is correct — it just needs to be explicitly annotated so linters and future developers know it's deliberate:

```dart
import 'package:flutter/foundation.dart'; // add if not already imported — for unawaited

// In login():
// BEFORE:
_persistLogin(host, port, token, refreshToken, username, isAdmin, iconEmoji);

// AFTER:
unawaited(
  Future(() => _persistLogin(host, port, token, refreshToken, username, isAdmin, iconEmoji)),
);
```

If `_persistLogin` already returns `void` (not `Future`), simply add a comment instead:

```dart
// Intentionally not awaited — persists in background, must not block navigation.
_persistLogin(host, port, token, refreshToken, username, isAdmin, iconEmoji);
```

Check: if `analysis_options.yaml` has `unawaited_futures: true`, use `unawaited()` — otherwise the comment is sufficient. Check `analysis_options.yaml` before deciding.

---

## Validation

```bash
# Backend
cd backend && python -m pytest tests/ -q

# Flutter
flutter analyze
flutter test
```

Verify `get_local_ip()` manually on the Radxa:
```bash
python3 -c "from app.config import get_local_ip; print(get_local_ip())"
# Should print the LAN IP (e.g. 192.168.1.x), not 127.0.0.1
```

---

## Docs to update after completing

- `kb/backend-patterns.md` — add: "SQLite connections use WAL mode + NORMAL sync for concurrent read performance"
- `kb/changelog.md` — `2026-03-XX: WAL mode on docs.db, get_local_ip fallback, bot supervisor health poll, unawaited persist annotation`
