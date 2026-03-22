# Backend Patterns — AiHomeCloud

> Descriptions of patterns actually used in the FastAPI backend.
> Verified against source code as of 2025-07-25.

---

## Route Structure

**Router registration:** Each route file creates an `APIRouter` and is registered in `main.py`:
```python
from app.routes.auth_routes import router as auth_router
app.include_router(auth_router)
```

**Auth dependency chain:** Protected endpoints use `Depends()`:
```python
@router.get("/info")
async def get_info(user: dict = Depends(get_current_user)):
    ...

@router.post("/shutdown")
async def shutdown(user: dict = Depends(require_admin)):
    ...
```

- `get_current_user` — decodes JWT, returns user dict (with `sub` = user_id)
- `require_admin` — calls `get_current_user` + checks `is_admin` flag

**JWT sub claim:** Always access user ID via `user.get("sub")` — not `user["id"]` or `user["user_id"]`.

---

## run_command() Usage

**Signature:** `async def run_command(cmd: list[str], timeout: int = 30) -> Tuple[int, str, str]`

**Always unpack all three values:**
```python
rc, stdout, stderr = await run_command(["lsblk", "-J"])
if rc != 0:
    raise HTTPException(status_code=500, detail=f"lsblk failed: {stderr}")
data = json.loads(stdout)
```

**Never shell=True:** Commands are always passed as a list of strings, never a single string with `shell=True`.

**Timeout:** Default 30s. Long-running ops (format) use longer timeouts or background jobs.

---

## store.py Usage

**Global lock:** All store operations are protected by a single `asyncio.Lock()`:
```python
_store_lock = asyncio.Lock()

async def get_users() -> list:
    async with _store_lock:
        return await _read_json(USERS_FILE)
```

**TTL cache:** Frequently-read data (users) is cached with a TTL to avoid repeated disk reads:
```python
_cache: dict[str, tuple[float, Any]] = {}
_CACHE_TTL = 1.0  # seconds
```

**Atomic writes:** JSON files are written atomically (write to temp file, then rename):
```python
async def _write_json(path: Path, data: Any):
    tmp = path.with_suffix(".tmp")
    async with aiofiles.open(tmp, "w") as f:
        await f.write(json.dumps(data, indent=2, default=str))
    tmp.rename(path)
```

**Key store functions:**
- `get_users()`, `save_users()`, `find_user()`, `add_user()`, `remove_user()`
- `update_user_pin()`, `update_user_profile()`, `remove_pin()`
- `get_services()`, `save_services()`, `toggle_service()`
- `get_device_state()`, `save_device_state()`
- `get_storage_state()`, `save_storage_state()`
- `get_tokens()`, `save_tokens()`
- `get_otp()`, `save_otp()`
- `get_trash()`, `save_trash()`
- `kv_get()`, `kv_set()` — generic key-value store

---

## Path Safety

**_safe_resolve() pattern:** All file operations resolve paths relative to NAS root and reject traversal:
```python
def _safe_resolve(user_path: str) -> Path:
    base = Path(settings.nas_root)
    target = (base / user_path).resolve()
    if not str(target).startswith(str(base.resolve())):
        raise HTTPException(status_code=403, detail="Access denied")
    return target
```

Used in: `file_routes.py` for list, mkdir, delete, rename, upload, download, search, sort.

**Never expose raw paths:** User-facing responses use `displayName` (not `/dev/sda`) and relative NAS paths (not absolute filesystem paths).

---

## Error Response Patterns

**HTTPException with status codes:**
```python
# 400 — Bad request (invalid input)
raise HTTPException(status_code=400, detail="Name is required")

# 401 — Unauthorized (invalid/expired JWT)
raise HTTPException(status_code=401, detail="Invalid token")

# 403 — Forbidden (path traversal, non-admin)
raise HTTPException(status_code=403, detail="Admin required")

# 404 — Not found
raise HTTPException(status_code=404, detail="User not found")

# 409 — Conflict (duplicate)
raise HTTPException(status_code=409, detail="User already exists")

# 500 — Internal error (subprocess failure)
raise HTTPException(status_code=500, detail=f"Command failed: {stderr}")
```

**Consistent detail field:** Always provide a human-readable `detail` string. Flutter's `friendlyError()` parses the HTTP status code, not the detail text, for user display.

---

## In-Memory Cache Eviction

**Bounded caches:** Caches that grow on every request must be evicted when writing new entries to prevent unbounded memory growth on ARM devices.

```python
# Pattern used in file_routes.py _scan_cache:
def _evict_expired_scan_cache() -> None:
    """Remove expired entries — call before every write."""
    now = _time.monotonic()
    stale = [k for k, (_, exp) in _scan_cache.items() if now >= exp]
    for k in stale:
        _scan_cache.pop(k, None)

# In the write path:
_evict_expired_scan_cache()
_scan_cache[cache_key] = (result, now + _TTL)
```

**Opportunistic prune pattern:** Security dicts (e.g. `_failed_logins`) should prune stale entries whenever the dict is written to:
```python
def _record_failure(ip: str) -> None:
    ...  # update entry
    _prune_failed_logins()  # remove expired lockouts on every write
```

**Blocking I/O in async handlers:** CPU-bound or blocking I/O (rglob, stat calls on large trees) must be offloaded to a thread executor:
```python
def _calc_dir_size(path: Path) -> int:
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file())

# Inside async handler:
loop = asyncio.get_running_loop()
size_bytes = await loop.run_in_executor(None, _calc_dir_size, resolved)
```

---

## SQLite (document_index.py)

**WAL mode:** All SQLite connections use WAL journal mode and NORMAL sync for concurrent read/write performance on SD card / NVMe:
```python
def _new_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(str(_db_path()), timeout=10, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")   # eliminates read/write contention
    conn.execute("PRAGMA synchronous=NORMAL") # safe with WAL; faster on SD/NVMe
    return conn
```
WAL mode allows concurrent readers without blocking writers. `NORMAL` sync is safe with WAL (no data loss on crash, only on power failure mid-write).

---

## Background Tasks & Jobs

**Job store pattern:** Long-running operations (storage format) use `job_store.py`:
```python
job_id = create_job()
asyncio.create_task(_do_format(job_id, device, label))
return {"jobId": job_id}
```

**Client polls:** Flutter polls `GET /api/v1/jobs/{job_id}` until `status` is `"completed"` or `"failed"`.

**Job lifecycle:** `pending` → `running` → `completed` | `failed`

---

## Config Access

**Settings singleton:** `config.py` provides `Settings` via pydantic-settings:
```python
from app.config import settings

nas_root = settings.nas_root      # /srv/nas
data_dir = settings.data_dir      # /var/lib/cubie
port = settings.port              # 8443
device_serial = settings.device_serial
pairing_key = settings.pairing_key
```

**Env prefix:** All env vars use `CUBIE_` prefix: `CUBIE_NAS_ROOT`, `CUBIE_DATA_DIR`, `CUBIE_PORT`, etc.

**Never hardcode paths:** Always use `settings.nas_root` and `settings.data_dir`.

---

## Pydantic Model Conventions

**camelCase aliases:** All models use `Field(alias="camelCase")` to match Flutter's JSON expectations:
```python
class FileItem(BaseModel):
    name: str
    path: str
    is_directory: bool = Field(alias="isDirectory")
    size_bytes: int = Field(alias="sizeBytes")

    model_config = ConfigDict(populate_by_name=True)
```

**populate_by_name=True:** Allows setting fields by Python name OR alias. Responses serialize using the alias (camelCase).

---

## WebSocket Patterns

**Token auth:** WebSocket endpoints accept JWT as a query parameter:
```python
@router.websocket("/ws/monitor")
async def monitor(ws: WebSocket, token: str = Query(...)):
    user = decode_token(token)
    await ws.accept()
    ...
```

**Continuous push:** Monitor and event WebSockets push data on a timer or event trigger, not request-response. Client reconnects on disconnect with exponential backoff (handled in Flutter's `ConnectionNotifier`).