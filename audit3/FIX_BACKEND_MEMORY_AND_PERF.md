# Fix: Backend Memory Leaks & Event Loop Blocking

> Agent task — one session, one commit.
> Priority: HIGH — these bugs cause gradual memory growth and UI stalls on a memory-constrained ARM device.

---

## Context

A full codebase audit on 2026-03-19 identified three backend issues:

1. **`_failed_logins` dict never pruned** (`auth_routes.py`) — every unique IP that attempts a login stays in memory forever. A scanning network or rotating IPs on a LAN slowly bloats this dict.
2. **`_scan_cache` entries never evicted** (`file_routes.py`) — entries expire logically (TTL 7 s) but the dict key is never removed. Browsing many folders with multiple sort states accumulates hundreds of dead entries.
3. **Directory size calculation blocks the event loop** (`file_routes.py` delete handler) — `sum(f.stat().st_size for f in resolved.rglob("*") if f.is_file())` runs synchronously. On a large NAS directory this can freeze the event loop for several seconds.
4. **`get_value` can't cache `None`** (`store.py`) — `if cached is not None` means keys whose legitimate value IS `None` (e.g. `trash_auto_delete` before it's been set) are never served from cache, causing a `kv.json` re-read on every call.

---

## Files to change

| File | Change |
|---|---|
| `backend/app/routes/auth_routes.py` | Prune stale `_failed_logins` entries on read |
| `backend/app/routes/file_routes.py` | Evict expired scan-cache entries; offload rglob to executor |
| `backend/app/store.py` | Use `_UNSET` sentinel instead of `None` check in `get_value` |

---

## Exact changes required

### 1. `auth_routes.py` — prune stale `_failed_logins`

Replace `_record_failure` and add a `_check_lockout` helper so that any read also prunes entries that have been unlocked long enough that they can never reach `_MAX_FAILURES` again (i.e. `lockout_until` has passed AND count < `_MAX_FAILURES`).

```python
def _record_failure(ip: str) -> None:
    record = _failed_logins.get(ip)
    count = (record[0] if record else 0) + 1
    lockout_until = (time.time() + _LOCKOUT_SECONDS) if count >= _MAX_FAILURES else 0.0
    _failed_logins[ip] = (count, lockout_until)
    # Opportunistic prune: remove unlocked entries while we have the dict open
    _prune_failed_logins()

def _prune_failed_logins() -> None:
    """Remove entries that are no longer locked out."""
    now = time.time()
    stale = [
        ip for ip, (count, lockout_until) in _failed_logins.items()
        if lockout_until > 0 and lockout_until < now  # lockout has expired
    ]
    for ip in stale:
        _failed_logins.pop(ip, None)
```

Also call `_prune_failed_logins()` at the TOP of the login handler (before checking the lockout), so old entries are cleaned on every login attempt.

---

### 2. `file_routes.py` — evict expired scan cache entries

The `_scan_cache` dict currently only grows. Add an eviction sweep whenever a new entry is written:

```python
def _evict_expired_scan_cache() -> None:
    """Remove expired entries from the scan cache. Called on write to keep memory bounded."""
    now = _time.monotonic()
    stale = [k for k, (_, exp) in _scan_cache.items() if now >= exp]
    for k in stale:
        _scan_cache.pop(k, None)
```

Call `_evict_expired_scan_cache()` just before writing a new entry in `list_files`:

```python
# inside the `else` branch of the cache check in list_files:
_evict_expired_scan_cache()
_scan_cache[cache_key] = ((paged, total_count), now + _SCAN_TTL)
```

---

### 3. `file_routes.py` — offload rglob to thread executor

In the `delete_file` handler, the size calculation must not run on the event loop:

```python
# BEFORE (blocks event loop):
size_bytes = sum(f.stat().st_size for f in resolved.rglob("*") if f.is_file())

# AFTER (offloaded):
def _calc_dir_size(path: Path) -> int:
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file())

# Inside delete_file, replace the else branch:
loop = asyncio.get_running_loop()
size_bytes = await loop.run_in_executor(None, _calc_dir_size, resolved)
```

Place `_calc_dir_size` as a module-level function (not inside the endpoint).

---

### 4. `store.py` — use `_UNSET` sentinel in `get_value`

`_UNSET` is already defined in `store.py`. The `get_value` function must use it as the "not in cache" marker so that `None` values are cached correctly.

```python
# Current (broken):
async def get_value(key: str, default: Any = None) -> Any:
    cached = _get_cached(f"kv:{key}")
    if cached is not None:          # ← BUG: never caches actual None values
        return cached
    ...

# Fixed:
async def get_value(key: str, default: Any = None) -> Any:
    cache_key = f"kv:{key}"
    cached = _cache.get(cache_key)
    if cached is not None:
        value, expires_at = cached
        if _time.monotonic() <= expires_at:
            return value            # could be None — that's valid
        _cache.pop(cache_key, None)
    async with _store_lock:
        data: Dict[str, Any] = _read_json(settings.data_dir / "kv.json", {})
        value = data.get(key, default)
        _set_cached(cache_key, value)   # ← now caches None correctly
        return value
```

Note: `_set_cached` skips caching `None` (it calls `_cache.pop`). That's fine — it just means `None` values always do a dict lookup but don't cause a disk read (lock is still acquired for the JSON read). If you want full caching of `None`, extend `_set_cached` to use `_UNSET` as the empty sentinel, but that's a larger refactor — the fix above is sufficient.

---

## Tests to write / update

- `backend/tests/test_auth.py` — add a test that calls the login endpoint 10 times from one IP, confirms lockout, waits for `_LOCKOUT_SECONDS` to pass (mock `time.time`), then confirms `_failed_logins` entry is pruned on the next call.
- `backend/tests/test_file_routes.py` — add a test that fills `_scan_cache` with 20 expired entries, triggers a `list_files` call, and asserts the cache size is smaller afterwards.
- `backend/tests/test_store.py` — add a test that calls `store.set_value("k", None)` then `store.get_value("k")` and asserts `None` is returned without a second disk read (mock `_read_json` with a call counter).

---

## Validation

```bash
cd backend && python -m pytest tests/ -q
```

All existing tests must still pass.

---

## Docs to update after completing

- `kb/backend-patterns.md` — note the scan cache eviction pattern
- `kb/changelog.md` — one-line entry: `2026-03-XX: Fixed _failed_logins memory leak, scan_cache eviction, rglob executor offload, get_value None caching`
