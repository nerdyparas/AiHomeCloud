# Backend Audit — AiHomeCloud
> Audited: 2026-03-15  
> Scope: All files under `backend/app/`. Read-only — nothing implemented here.

---

## How to read this file

- **BUG** — confirmed incorrect behaviour that will cause failures
- **SECURITY** — exploitable vulnerability or policy violation
- **RACE** — data-race or TOCTOU issue
- **PERF** — measurable performance problem on ARM hardware
- **DESIGN** — questionable architecture that will bite later
- **MINOR** — low-severity rough edge / inconsistency

---

## 1. BUGS

### BUG-1 — `store.get_users()` cache served outside lock; stale data reaches callers
**File:** `backend/app/store.py` — `get_users()`

```python
async def get_users() -> List[dict]:
    cached = _get_cached("users")
    if cached is not None:
        return cached          # ← returns BEFORE acquiring lock

    async with _store_lock:
        users = _read_json(settings.users_file, [])
        _set_cached("users", users)
        return users
```

`_set_cached` stores a **direct reference** to the list; callers that mutate this list (e.g. `for u in users: u["pin"] = ...`) mutate the cached copy. The next caller gets a partially-mutated list without a disk read. This happens in `migrate_plaintext_pins()` and the inline pin-check loops in `auth_routes.py`.

**Same pattern exists in** `get_services()`, `get_tokens()`, `get_storage_state()`, `get_trash_items()`, `get_device_state()`.

**Impact:** After a PIN migration or token revocation, subsequent calls within the 5-second TTL window may see inconsistent data in-memory while disk is authoritative.

---

### BUG-2 — `update_user_profile` invalidates cache *after* writing, not before
**File:** `backend/app/store.py` — `update_user_profile()`

```python
async def update_user_profile(...):
    users = await get_users()           # ← reads (possibly cached) list
    for u in users:
        if u["id"] == user_id:
            ...
            await save_users(users)
            _set_cached("users", None)  # ← invalidated AFTER write
            return True
```

`save_users()` itself calls `_set_cached("users", users)` (the new value) under lock. Then immediately after, `update_user_profile` sets it back to `None`. This double-write of the cache is harmless in isolation but demonstrates inconsistent cache invalidation discipline — `save_users` always populates the cache, making the extra `_set_cached("users", None)` calls in `update_user_profile` and `remove_pin` redundant and misleading.

---

### BUG-3 — `pair` endpoint has no OTP validation, issues permanent device token
**File:** `backend/app/routes/auth_routes.py` — `POST /pair`

```python
@router.post("/pair", response_model=TokenResponse)
async def pair_device(request: Request, body: PairRequest):
    if body.serial != settings.device_serial:
        raise HTTPException(403, "Unknown serial")
    if body.key != settings.pairing_key:
        raise HTTPException(403, "Invalid pairing key")
    token = create_token(subject=body.serial, extra={"type": "device"})
    return TokenResponse(token=token)
```

`/pair` requires only `serial + pairing_key`. The `pairing_key` is stored in a world-readable (mode 0644 by default) file on the device. An attacker with read access to `/var/lib/aihomecloud/pairing_key` or who intercepts it once on the network can replay the pairing request indefinitely and obtain a device-level (admin-equivalent) token. The secure endpoint is `/pair/complete` which requires OTP, but `/pair` bypasses it entirely. `/pair` should be deprecated or removed in favor of `/pair/complete`.

---

### BUG-4 — `_failed_logins` dictionary is in-process memory only; restarts reset it
**File:** `backend/app/routes/auth_routes.py` — `_failed_logins`

After a process restart (e.g. `systemctl restart aihomecloud`) the brute-force lockout counter is reset. An attacker can get 10 tries per restart. On a device with auto-restart configured this could allow unlimited brute-force in batches of 10. The lockout should be persisted (e.g. in the KV store) or use a sliding window that survives restart.

---

### BUG-5 — `format_device` uses `sudo mkfs.ext4` without `-n` flag
**File:** `backend/app/routes/storage_routes.py` — `_run_format_job()`

```python
rc, _, stderr = await run_command([
    "sudo", "mkfs.ext4", "-F", "-L", req.label, req.device
], timeout=600)
```

All other `sudo` calls in the codebase use `sudo -n` (non-interactive, fail rather than prompt). This one is missing `-n`. If `NOPASSWD` is not configured for `mkfs.ext4` in sudoers, this call will block indefinitely waiting for a password that never comes — making the job hang forever. The job status shows `running` with no timeout on the UI side.

---

### BUG-6 — `list_user_names` leaks `icon_emoji` for all users — no auth required
**File:** `backend/app/routes/auth_routes.py` — `GET /auth/users/names`

The endpoint is intentionally public (needed for the login picker) but it returns `icon_emoji`, which is user-set personal data. For a system with 8 users, a LAN-local attacker learns every user's emoji avatar without any authentication. The field should be returned only after login, or at minimum be opt-in (most login-picker UIs only need `name` + `has_pin`).

---

### BUG-7 — Upload does not validate `Content-Type` header; MIME sniffing only
**File:** `backend/app/routes/file_routes.py` — `POST /files/upload`

The upload endpoint blocks by file extension (`BLOCKED_EXTENSIONS`) but does not verify that the actual bytes match the declared MIME type. A `.jpg` file containing a shell script passes all checks. Blocked extensions are only checked against the filename suffix — renaming `evil.sh` to `evil.jpg.sh` would be caught, but `evil.sh` renamed to `evil.jpg` would not (`.jpg` is not in blocked list). Consider validating magic bytes via `python-magic` for uploads into the NAS.

---

### BUG-8 — `delete_file` calculates directory size synchronously on event loop
**File:** `backend/app/routes/file_routes.py` — `delete_file()`

```python
size_bytes = sum(f.stat().st_size for f in resolved.rglob("*") if f.is_file())
```

`rglob("*")` on a large directory tree runs synchronously on the event loop, blocking all other requests for the duration. This could freeze the entire API for several seconds on a large folder. This should be wrapped in `run_in_executor`.

---

### BUG-9 — `kv.json` read-modify-write in `set_value` is not atomic across concurrent callers
**File:** `backend/app/store.py` — `set_value()`

```python
async def set_value(key: str, value: Any) -> None:
    _set_cached(f"kv:{key}", None)
    async with _store_lock:
        data = _read_json(settings.data_dir / "kv.json", {})  # full read
        data[key] = value
        _write_json(settings.data_dir / "kv.json", data)      # full write
```

Each key-value pair requires reading and rewriting the entire `kv.json`. Under concurrent writes (e.g. Telegram config save + trash prefs save simultaneously), the single `_store_lock` serializes them correctly — but both read the full file. The second write overwrites the first write's key with its own fresh copy. This is actually fine because of the lock, but it means `kv.json` grows unboundedly; there is no cleanup of stale/old keys.

---

### BUG-10 — `document_index.py` uses `asyncio.get_event_loop()` (deprecated in Python 3.10+)
**File:** `backend/app/document_index.py` — `init_db()`

```python
async def init_db() -> None:
    loop = asyncio.get_event_loop()      # ← deprecated; use asyncio.get_running_loop()
    await loop.run_in_executor(None, _init_db_sync)
```

`get_event_loop()` is deprecated since Python 3.10 and emits `DeprecationWarning` in 3.12. Should be `asyncio.get_running_loop()`. The same issue exists in other document_index async functions.

---

### BUG-11 — `main.py` uses `asyncio.get_event_loop()` in lifespan
**File:** `backend/app/main.py` — lifespan around line 162

```python
_hashed = await asyncio.get_event_loop().run_in_executor(
    None, lambda: _bcrypt_hash.hash("0000")
)
```

Same deprecation as BUG-10. Should be `asyncio.get_running_loop()`.

---

### BUG-12 — `PairRequest` serial/key compared with `==` instead of `hmac.compare_digest`
**File:** `backend/app/routes/auth_routes.py` — `pair_device()` and `pair_complete()`

```python
if body.serial != settings.device_serial:    # timing-vulnerable
if body.key != settings.pairing_key:         # timing-vulnerable
```

String equality (`==`) is not constant-time. A timing side-channel could allow an attacker to infer character-by-character matches on the pairing key over many requests from LAN. `hmac.compare_digest` should be used for all secret comparisons. The OTP comparison in `pair_complete` correctly uses `hmac.compare_digest`, but the serial and key checks do not.

---

## 2. SECURITY

### SEC-1 — `/pair` endpoint exposes permanent device token without OTP (see BUG-3)

### SEC-2 — `pairing_key` file permissions not enforced
**File:** `backend/app/config.py` — `generate_pairing_key()`

```python
key_file.write_text(key)
key_file.chmod(stat.S_IRUSR | stat.S_IWUSR)  # ← good, 0600
```

`generate_jwt_secret()` correctly sets 0600. `generate_pairing_key()` also sets 0600. However, the file is only `chmod`'d after writing. On systems where `umask` is permissive (e.g. 0000 in Docker), the file is briefly world-readable between `write_text()` and `chmod()`. Use `os.open(path, O_CREAT | O_WRONLY, 0o600)` to create with correct permissions atomically.

### SEC-3 — JWT `HS256` with a short 1-hour expiry is reasonable but `jwt_algorithm` is configurable via env
**File:** `backend/app/config.py`

`AHC_JWT_ALGORITHM=none` would bypass signature verification in some JWT libraries. The `python-jose` / `PyJWT` libraries used here should be pinned to reject `none` algorithm, but there is no explicit check. Add `algorithms=[settings.jwt_algorithm]` assertion that rejects `"none"` at startup.

### SEC-4 — Telegram upload route (`/telegram-upload`) uses token-in-URL
**File:** `backend/app/routes/telegram_upload_routes.py`

Upload tokens passed as query parameters appear in server access logs, proxy logs, and browser history. Should use `Authorization` header instead for the token.

### SEC-5 — Rate limiting is IP-based with `_failed_logins` in-memory (see BUG-4)
The rate limiter (SlowAPI) is also IP-based and resets on process restart. Behind a NAT or shared WiFi, a single bad actor can trigger lockout for all users sharing the same public IP.

### SEC-6 — `set_trash_prefs` is not admin-restricted
**File:** `backend/app/routes/file_routes.py` — `PUT /files/trash/prefs`

Any authenticated user can enable or disable 30-day auto-delete globally. This should require `require_admin`.

---

## 3. RACE CONDITIONS

### RACE-1 — `create_user` has a TOCTOU window between checking `is_first_user` and adding the user
**File:** `backend/app/routes/auth_routes.py` — `create_user()`

```python
existing = await store.get_users()      # read
is_first_user = len(existing) == 0

if not is_first_user:
    if caller is None: raise ...
    await require_admin(caller)

# ... bcrypt hash (slow, ~100ms) ...
user = await store.add_user(...)        # write
```

Between the `get_users()` and `add_user()` calls there is a ~100ms bcrypt window. Two simultaneous unauthenticated requests could both see `is_first_user = True`, both skip the admin check, and both become admins. On a fresh device this creates two admin accounts instead of one. Should hold `_store_lock` across the check + write, or re-check inside `add_user`.

### RACE-2 — `toggle_service` reads then writes without holding lock across both
**File:** `backend/app/store.py` — `toggle_service()`

`get_services()` acquires the lock to read; it then releases it. `save_services()` acquires the lock again to write. Between the two lock acquisitions another coroutine can modify services. The pattern `read → modify in memory → write` must all be inside a single lock acquisition for correctness.

---

## 4. PERFORMANCE

### PERF-1 — `_folder_size_gb_sync` uses `os.walk` (not `os.scandir`) — slow on large trees
**File:** `backend/app/routes/family_routes.py`

`os.walk` has higher overhead than `os.scandir`-based recursion on Python 3.12. For a 100 GB music collection with tens of thousands of files, each `GET /family` call runs N directory-walk threads in parallel (one per user). Consider caching folder sizes with a short TTL (e.g. 60 seconds).

### PERF-2 — `get_trash_items()` loads all users' trash into memory for every operation
**File:** `backend/app/store.py` — `get_trash_items()`

`list_trash` filters `deletedBy == user_id` in Python **after** loading the full list. With N users and many items this is O(N*M). Partitioned storage (one trash file per user, or an index by user_id) would allow O(1) lookup.

### PERF-3 — `store.get_users()` is called on every authenticated request
**File:** `backend/app/auth.py` — `require_admin()`

Every admin-protected endpoint calls `require_admin()` which calls `store.find_user()` which calls `store.get_users()`, reading users.json on every request (or serving from 5-second TTL cache). The `is_admin` flag is already in the JWT payload (`extra={"is_admin": ...}`). For the common case, reading from the JWT without hitting the store would be faster and still secure (JWT is signed).

### PERF-4 — `document_index.py` opens a new SQLite connection per operation
**File:** `backend/app/document_index.py` — `_connect()`

Every `index_document`, `search_documents`, `remove_document` call opens and closes a fresh `sqlite3.Connection`. SQLite has ~1ms connection setup cost. A connection pool or persistent connection (with WAL mode enabled) would improve throughput significantly for the index watcher scenario.

### PERF-5 — `kv.json` is read and rewritten in full for every `set_value` call
**File:** `backend/app/store.py` — `set_value()`

If Telegram is active and sends multiple files, each file triggers at least one `set_value` call, reading and rewriting the entire `kv.json`. Consider splitting high-frequency keys (e.g. `telegram_linked_ids`) into separate files or using SQLite for the KV store.

---

## 5. DESIGN ISSUES

### DESIGN-1 — `auth_routes.py` has duplicate router registration for `pair_device` and `pair_complete`
**File:** `backend/app/routes/auth_routes.py`

`pair_device` and `pair_complete` are defined **twice** in the file — once early in the file (around lines 104-170) and again later (lines 310-380). The second definition silently overwrites the first in FastAPI's route table. Any changes made to the earlier definition will have no effect.

### DESIGN-2 — `_failed_logins` uses IP as key, but requests proxied through uvicorn behind nginx/Caddy will all show `127.0.0.1`
**File:** `backend/app/routes/auth_routes.py`

If a reverse proxy is ever put in front of the backend, all login requests will share the same IP (`127.0.0.1`), making 10 failed logins lock **all** users out simultaneously. Should read `X-Forwarded-For` header with a configurable trusted proxy list.

### DESIGN-3 — `store.py` cache is a module-level dict — shared between all test runs in the same process
**File:** `backend/app/store.py` — `_cache`

The module-level `_cache` dict is not reset between test cases. Tests that modify the store leave stale cached data that bleeds into the next test. The conftest `tmp_data_dir` fixture changes the data directory but doesn't reset the in-memory cache, leading to subtle test ordering dependencies.

### DESIGN-4 — `main.py` lifespan has 15+ startup tasks in a single function with wide `except` clauses
**File:** `backend/app/main.py`

Each startup task catches `(OSError, RuntimeError, ValueError)` independently, making it impossible to know which task failed without reading logs. A single failed critical task (e.g. TLS cert generation) doesn't stop startup — it silently continues. This makes debugging production failures harder.

### DESIGN-5 — `board.py` detection is called once at startup but result stored in `app.state`; not accessible in routes that don't receive `Request`
**File:** `backend/app/board.py` + `main.py`

`board = detect_board()` is stored in `request.app.state.board` which requires a `Request` parameter. Routes like `monitor_routes.py` (WebSocket) that need board info (thermal zone) have to access it differently. Consider exposing board info as a module-level singleton set at startup.

### DESIGN-6 — Telegram bot state is module-level; restarting the bot (`stop_bot` + `start_bot`) is not concurrency-safe
**File:** `backend/app/telegram_bot.py`

`_application` is a module-level variable. `stop_bot()` and `start_bot()` in `telegram_routes.py` are called in sequence from an HTTP handler, but there is no lock preventing two concurrent admin requests from calling `start_bot` simultaneously, creating two polling loops.

### DESIGN-7 — `file_routes.py` `_safe_resolve` resolves symlinks BEFORE checking if the candidate is a symlink  
**File:** `backend/app/routes/file_routes.py`

```python
if candidate.is_symlink():
    raise HTTPException(403, "Symbolic links are not allowed")

try:
    resolved = candidate.resolve()
```

`candidate.resolve()` follows all symlinks. If a directory in the path _above_ the final component is a symlink, `is_symlink()` only checks the final component. A parent symlink would be followed silently. Use `candidate.resolve(strict=False)` and then check `resolved.is_relative_to(nas_resolved)` which covers all parent symlinks.

---

## 6. MINOR ISSUES

### MINOR-1 — `create_user` doesn't validate name uniqueness (case-insensitive)
**File:** `backend/app/routes/auth_routes.py` — `create_user()`

`create_user` checks `not body.name.strip()` but not for duplicate names. Two users named `Admin` and `admin` can coexist. The login endpoint uses `u.get("name") == body.name` (case-sensitive), so `Admin` and `admin` would be treated as different accounts. `update_my_profile` does check for case-insensitive uniqueness, creating an inconsistency.

### MINOR-2 — `change_pin` allows changing to same PIN that was just used
**File:** `backend/app/routes/auth_routes.py` — `change_pin()`

No check that `new_pin != old_pin`. Minor UX issue, not a security concern.

### MINOR-3 — `delete_file` trash collision counter starts at 1, meaning the second file in a collision is named `{ts}_1_{filename}` (skips `_0_`)
**File:** `backend/app/routes/file_routes.py` — `delete_file()`

```python
counter = 1
while trash_path.exists():
    trash_path = user_trash_dir / f"{ts}_{counter}_{filename}"
    counter += 1
```

First collision: `1726000000_1_foo.txt`, second: `1726000000_2_foo.txt`. Cosmetic, but starts at 1 (not 2), which is inconsistent with the usual rename-collision pattern.

### MINOR-4 — `board.py` thermal zone fallback reads first zone arbitrarily
**File:** `backend/app/board.py`

When the preferred thermal zone is not found, the code falls back to the first available zone. On Rock Pi 4A (RK3399) there are multiple thermal zones (GPU, big cluster, little cluster). Zone 0 may not be the most representative for "system temperature." Should prefer zone with the highest temperature reading.

### MINOR-5 — `family_routes.py` `add_family` doesn't set `icon_emoji`
**File:** `backend/app/routes/family_routes.py`

`store.add_user(body.name)` is called without passing `icon_emoji`. The `AddFamilyUserRequest` model may or may not include an `icon_emoji` field — if it does, it's silently ignored. Family members always start with an empty emoji avatar.

### MINOR-6 — `network_routes.py` reads WiFi speed from `/sys/class/net` synchronously on event loop
**File:** `backend/app/routes/network_routes.py`

`operstate.read_text()` and `speed_file.read_text()` are synchronous `/sys` filesystem reads inside an `async def`. These are typically fast (kernel in-memory), but technically block the event loop. On a heavily loaded device, they could cause latency spikes.

### MINOR-7 — `document_index.py` `init_db()` uses `asyncio.get_event_loop()` (see BUG-10)

### MINOR-8 — `file_routes.py` `sort_by` query param is not validated against an allowlist
Accepts any string for `sort_by` (e.g. `sort_by=__class__`). Currently it falls through to the default name-sort, so no security impact, but an allowlist (`name`, `size`, `modified`) would be cleaner.

### MINOR-9 — `upload` endpoint `Content-Length` check uses `max_upload_bytes == 0` as unlimited
**File:** `backend/app/routes/file_routes.py`

```python
if settings.max_upload_bytes > 0 and int(content_length) > settings.max_upload_bytes:
```

A value of `0` intentionally means "unlimited" (documented). This is a footgun — a misconfiguration setting `AHC_MAX_UPLOAD_BYTES=0` silently disables upload caps. Should use a sentinel like `-1` for unlimited and validate that `max_upload_bytes >= 0`.

---

## Summary Table

| ID | Severity | Category | File | Short description |
|---|---|---|---|---|
| BUG-1 | High | Bug | store.py | Cache holds mutable refs; mutation corrupts cached state |
| BUG-2 | Low | Bug | store.py | Redundant cache invalidation after save_users() |
| BUG-3 | High | Security | auth_routes.py | `/pair` bypasses OTP; issues permanent admin token |
| BUG-4 | Medium | Bug | auth_routes.py | Lockout counter resets on process restart |
| BUG-5 | Medium | Bug | storage_routes.py | `sudo mkfs.ext4` missing `-n`; can block indefinitely |
| BUG-6 | Low | Privacy | auth_routes.py | `/auth/users/names` leaks icon_emoji without auth |
| BUG-7 | Medium | Security | file_routes.py | Upload allows renamed executables via extension-only check |
| BUG-8 | Medium | Perf | file_routes.py | Directory size calc blocks event loop on delete |
| BUG-9 | Low | Design | store.py | kv.json grows unboundedly; no stale key cleanup |
| BUG-10 | Low | Bug | document_index.py | `get_event_loop()` deprecated in Python 3.10+ |
| BUG-11 | Low | Bug | main.py | `get_event_loop()` deprecated in lifespan |
| BUG-12 | Medium | Security | auth_routes.py | Timing-vulnerable string compare for serial/key in `/pair` |
| SEC-1 | High | Security | auth_routes.py | Permanent device token without OTP (duplicate of BUG-3) |
| SEC-2 | Medium | Security | config.py | pairing_key written with wrong permissions briefly |
| SEC-3 | Medium | Security | config.py | JWT `alg=none` not explicitly rejected at startup |
| SEC-4 | Low | Security | telegram_upload_routes.py | Token in URL appears in logs |
| SEC-5 | Medium | Security | auth_routes.py | Rate limiter resets on restart; shared IP lockout risk |
| SEC-6 | Medium | Security | file_routes.py | Trash auto-delete pref not admin-restricted |
| RACE-1 | High | Race | auth_routes.py | TOCTOU: two simultaneous signups both become admin |
| RACE-2 | Medium | Race | store.py | toggle_service read-modify-write not atomic |
| PERF-1 | Medium | Perf | family_routes.py | os.walk per-user folder size scan on each GET /family |
| PERF-2 | Medium | Perf | store.py | All trash loaded for single-user filter |
| PERF-3 | Medium | Perf | auth.py | store.get_users() called on every admin-protected request |
| PERF-4 | Low | Perf | document_index.py | New SQLite connection per document operation |
| PERF-5 | Low | Perf | store.py | kv.json full read+write per set_value call |
| DESIGN-1 | High | Design | auth_routes.py | `pair_device`/`pair_complete` defined twice; second silently wins |
| DESIGN-2 | Medium | Design | auth_routes.py | IP-based lockout breaks behind reverse proxy |
| DESIGN-3 | Medium | Design | store.py | Module-level cache bleeds between test runs |
| DESIGN-4 | Low | Design | main.py | 15+ startup tasks in one function, silent failures |
| DESIGN-5 | Low | Design | board.py | Board info in app.state, not accessible without Request param |
| DESIGN-6 | Medium | Design | telegram_bot.py | Bot restart not concurrency-safe |
| DESIGN-7 | Medium | Security | file_routes.py | Symlink check only on final path component, not parents |
| MINOR-1 | Low | Minor | auth_routes.py | No case-insensitive duplicate name check on create |
| MINOR-2 | Low | Minor | auth_routes.py | No same-PIN rejection in change_pin |
| MINOR-3 | Low | Minor | file_routes.py | Trash collision counter cosmetic inconsistency |
| MINOR-4 | Low | Minor | board.py | Thermal zone fallback picks zone[0] arbitrarily |
| MINOR-5 | Medium | Minor | family_routes.py | add_family ignores icon_emoji |
| MINOR-6 | Low | Minor | network_routes.py | /sys reads block event loop briefly |
| MINOR-7 | Low | Minor | document_index.py | get_event_loop() deprecated |
| MINOR-8 | Low | Minor | file_routes.py | sort_by not validated against allowlist |
| MINOR-9 | Low | Minor | file_routes.py | max_upload_bytes=0 silently disables limit |

---

## Priority Order for Implementation

1. **RACE-1** (BUG-3 + DESIGN-1) — first-user signup race + double route definition
2. **BUG-5** — `sudo mkfs.ext4` missing `-n`, can hang format jobs forever
3. **BUG-1** — cache mutation corruption (affects all cached stores)
4. **DESIGN-7** — symlink traversal through parent directory
5. **SEC-6** — trash prefs needs admin guard
6. **BUG-8** — directory-size calculation blocks event loop
7. **BUG-10 / BUG-11** — `get_event_loop()` deprecation warnings
8. **MINOR-5** — icon_emoji silently dropped on add_family
