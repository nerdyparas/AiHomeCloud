# AiHomeCloud — Engineering Blueprint v1.0

> Verified against codebase as of 2025-07-25.
> Note: Bugs B1 (threading.Lock → asyncio.Lock) and B3 (bcrypt run_in_executor) from critique.md are now fixed in code.

> **Document purpose:** Authoritative engineering reference for transitioning from
> AI-generated prototype (~65% complete) to production-grade system. All future
> task orchestration, code review, and architectural decisions must be validated
> against this document.
>
> **Scope:** Backend (FastAPI / Python / ARM SBC) + Flutter Android client.
> **Baseline:** Milestones 1–3 complete as of March 2026.
> **Not in scope:** Web UI, cloud sync, multi-device federation.

---

## Part 1 — Engineered Requirements

### 1.1 Hard Constraints (Non-Negotiable)

#### Hardware

| Constraint | Value | Rationale |
|---|---|---|
| Backend resident RAM | ≤ 256 MB | Shares SBC with OS, journald, SMB daemon, NFS |
| Idle CPU budget | ≤ 15% single core | 4× ARM Cortex-A55 at 1.8 GHz — thermal throttling at 60°C |
| Active transfer CPU | ≤ 60% single core | Leave headroom for OS I/O scheduling |
| Backend startup time | ≤ 15 seconds (cold boot) | Includes auto-remount, TLS cert check |
| Auto-remount timeout | ≤ 30 seconds | Must not block systemd boot target |
| Max upload buffering | 0 bytes in memory | Streaming multipart only; no `await request.body()` for large files |
| AI inference | CPU-only | No GPU on Cubie A7Z; plan for background-only at low priority |

#### Operational

- SD card is OS-only. NAS data **must** live on external USB or NVMe.
- Backend must survive USB device disconnect without crashing or hanging.
- Backend must survive SD card I/O errors on `/var/lib/cubie/` writes (atomic writes + graceful degradation).
- App must be fully usable with no internet connection.
- App must detect device unreachability within 5 seconds and show a clear status — not a generic exception.
- All destructive operations (format, delete, eject, remove user) **require** explicit typed confirmation.

#### Scale

| Dimension | Ceiling | Note |
|---|---|---|
| Concurrent users | 8 | Family NAS, not enterprise |
| Max single file upload | 4 GB | Chunked multipart required above 100 MB |
| Max directory listing | 10,000 files | Pagination required; default page size = 100 |
| Concurrent WebSocket clients | 8 | One per active user session |
| JSON store write frequency | ≤ 1 write/second sustained | Low — users.json is not a hot path |

---

### 1.2 Functional Requirements

Each requirement is tagged with its current status against the v1 prototype.

#### Authentication & Authorization

| ID | Requirement | Status |
|---|---|---|
| FR-AUTH-01 | Device pairing requires serial + time-limited OTP (not static key) | ❌ Static key |
| FR-AUTH-02 | Access token expiry ≤ 1 hour; refresh token pattern (7-day refresh) | ❌ 720h hardcoded |
| FR-AUTH-03 | PIN stored as bcrypt hash (cost=10), never plaintext | ❌ Plaintext in users.json |
| FR-AUTH-04 | `POST /api/v1/auth/logout` must invalidate token server-side | ❌ Client-side clear only |
| FR-AUTH-05 | Rate limit: 5 requests/minute on `/api/v1/pair` | ❌ No rate limiting |
| FR-AUTH-06 | `require_admin` must validate role from store, not from token claim | ⚠️ Partial — device tokens bypass |
| FR-AUTH-07 | JWT secret must be auto-generated on first boot | ❌ Defaults to literal `"change-me-in-production"` |

#### File Operations

| ID | Requirement | Status |
|---|---|---|
| FR-FILE-01 | `GET /api/v1/files/list` supports `?page=&limit=` (default limit=100) | ❌ No pagination |
| FR-FILE-02 | Upload rejects executable extensions: `.sh .py .elf .bin .exe .apk .so` | ❌ No type filter |
| FR-FILE-03 | All file paths validated via `_safe_resolve()` before every FS operation | ⚠️ Present but not systematic |
| FR-FILE-04 | Delete moves to `.trash/` before permanent removal (soft-delete) | ❌ Hard delete |
| FR-FILE-05 | Download supports `Range` header for resumable transfers | ❌ |
| FR-FILE-06 | Large uploads (> 100 MB) use chunked multipart, not single POST body | ❌ Single POST |

#### Storage Management

| ID | Requirement | Status |
|---|---|---|
| FR-STOR-01 | Format requires `confirmDevice == device` exact match | ✅ |
| FR-STOR-02 | Unmount blocked if user processes have open file handles | ✅ |
| FR-STOR-03 | Auto-remount has explicit 30s timeout; failure is non-fatal to startup | ⚠️ No timeout on asyncio.create_subprocess_exec calls |
| FR-STOR-04 | Device path validated against `^/dev/[a-z]+[0-9]*p?[0-9]*$` before subprocess | ❌ No regex validation |
| FR-STOR-05 | All subprocess calls use list form (never `shell=True` with user input) | ❌ Mixed |

#### Monitoring

| ID | Requirement | Status |
|---|---|---|
| FR-MON-01 | `GET /ws/monitor` requires auth (`?token=<jwt>` on upgrade) | ❌ Open, no auth |
| FR-MON-02 | Monitor stream includes NAS health: `{nasMounted: bool, nasDevice: str}` | ❌ |
| FR-MON-03 | Monitor emits `{event: "nas_disconnected"}` if NAS device disappears mid-session | ❌ |

#### API Contract

| ID | Requirement | Status |
|---|---|---|
| FR-API-01 | All routes carry major version prefix: `/api/v1/` | ❌ Unversioned |
| FR-API-02 | `GET /api/version` (unversioned) returns `{apiVersion, backendVersion, minAppVersion}` | ❌ |
| FR-API-03 | Flutter app checks `/api/version` on connect; shows update dialog if incompatible | ❌ |

---

### 1.3 Non-Functional Requirements

#### Security

| ID | Requirement |
|---|---|
| NFR-SEC-01 | TLS uses ECDSA cert (not RSA — 4× smaller on ARM) |
| NFR-SEC-02 | CORS middleware must be removed for native app; only enabled if web UI is ever added |
| NFR-SEC-03 | Flutter must pin the TLS cert fingerprint on first successful pairing |
| NFR-SEC-04 | All subprocess calls audited: list form only, no shell interpolation, path validated |
| NFR-SEC-05 | users.json and TLS key files must have `0600` permissions, owned by `cubie` service user |
| NFR-SEC-06 | Backend systemd unit must run as non-root `cubie` user with `NoNewPrivileges=true` |
| NFR-SEC-07 | `CAP_SYS_ADMIN` (for mount/umount) must be granted via a narrow sudo wrapper, not full root |

#### Reliability

| ID | Requirement |
|---|---|
| NFR-REL-01 | All JSON file writes must be atomic: write to `.tmp`, then `os.replace()` |
| NFR-REL-02 | All JSON files must include `_schema_version` for safe migration |
| NFR-REL-03 | Startup failure of any route module must not prevent other routes from loading (isolated try/except on router registration) |
| NFR-REL-04 | WebSocket disconnects must not leak asyncio tasks or file handles |
| NFR-REL-05 | Backend must enforce a max of 8 concurrent WebSocket connections; reject with 503 above limit |

#### Observability

| ID | Requirement |
|---|---|
| NFR-OBS-01 | All requests logged as structured JSON: `{ts, level, method, path, status, duration_ms, user_id, request_id}` |
| NFR-OBS-02 | All subprocess calls logged at DEBUG: `{cmd, exit_code, stderr_truncated}` |
| NFR-OBS-03 | Startup log emits device serial, firmware version, NAS mount status, TLS status, active service list |
| NFR-OBS-04 | No `print()` statements anywhere — `logging.getLogger()` only |
| NFR-OBS-05 | journald configured: `SystemMaxUse=50M` to prevent SD card fill |

#### Performance

| ID | Requirement |
|---|---|
| NFR-PERF-01 | File listing for 1,000 items: < 500 ms |
| NFR-PERF-02 | WebSocket monitor frame generation: < 50 ms |
| NFR-PERF-03 | Downloads use `FileResponse` or streaming generator — never load file into memory |
| NFR-PERF-04 | JSON store reads cached for 1 second to prevent thrashing on concurrent requests |

---

## Part 2 — Layered Architecture Blueprint

### 2.1 Prototype Risk Assessment

These are **specific, identified problems** in the current codebase — not generic concerns.

---

**RISK-01: No layer separation in route files** *(Critical)*

Current route files (`storage_routes.py`, `file_routes.py`, `network_routes.py`) combine HTTP handling, business logic, and raw subprocess execution in the same function. A single handler in `storage_routes.py` calls `subprocess.run(["lsblk", ...])`, parses its JSON output, builds a Pydantic model, and returns it — all inline.

**Impact:** Cannot unit-test business logic without spinning up FastAPI. Cannot mock system calls. Changes to lsblk output format require touching the HTTP handler.

**Fix:** Introduce `backend/app/services/` and `backend/app/system/` layers. See Section 2.2.

---

**RISK-02: JSON store is not thread-safe** *(Critical)*

`store.py` uses `path.write_text()` with no locking. Under concurrent requests, two writers can interleave: Writer A reads users.json, Writer B reads users.json, A writes (adding user X), B writes (adding user Y, overwriting A's write). Net result: user X is silently lost.

**Fix:**
```python
# store.py — required pattern
import threading, tempfile, os

_file_locks: dict[Path, threading.Lock] = {}

def _get_lock(path: Path) -> threading.Lock:
    if path not in _file_locks:
        _file_locks[path] = threading.Lock()
    return _file_locks[path]

def _write_json_atomic(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with _get_lock(path):
        fd, tmp = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
        try:
            with os.fdopen(fd, 'w') as f:
                json.dump(data, f, indent=2)
            os.replace(tmp, path)  # atomic on POSIX
        except Exception:
            os.unlink(tmp)
            raise
```

---

**RISK-03: CORS is incorrectly configured** *(High)*

`main.py` sets `allow_origins=["*"]` with `allow_credentials=True`. This combination is rejected by browsers (the Fetch spec prohibits credentials with wildcard origin) and is a security misconfiguration. Since the Flutter client is a native Android app, CORS middleware serves no purpose and should be **removed entirely** in production.

**Fix:** Remove `CORSMiddleware` registration. Add it back only if and when a web UI is built, at which point it must specify explicit allowed origins.

---

**RISK-04: WebSocket `/ws/monitor` has no authentication** *(High)*

Any device on the LAN can connect to the WebSocket and receive a continuous stream of CPU usage, RAM usage, temperature, and storage stats. This is real-time system intelligence for an attacker.

**Fix:**
```python
# monitor_routes.py
@router.websocket("/ws/monitor")
async def monitor_ws(websocket: WebSocket, token: str = Query(...)):
    try:
        user = decode_token(token)  # raises on invalid
    except HTTPException:
        await websocket.close(code=1008)  # Policy Violation
        return
    await websocket.accept()
    # ... existing loop
```

---

**RISK-05: PIN stored as plaintext** *(Critical)*

`store.py` `add_user()` stores `"pin": pin` verbatim. If `users.json` is ever readable by an unauthorized party (NFS export misconfiguration, backup exposure, path traversal), all PINs are trivially exposed.

**Fix:** Hash before storage, verify during auth:
```python
from passlib.hash import bcrypt  # add passlib[bcrypt] to requirements.txt

def add_user(name: str, pin: str | None = None, is_admin: bool = False) -> dict:
    user = {
        "id": f"user_{uuid.uuid4().hex[:8]}",
        "name": name,
        "pin_hash": bcrypt.hash(pin) if pin else None,  # NOT "pin"
        "is_admin": is_admin,
    }
    ...

def verify_pin(user: dict, pin: str) -> bool:
    h = user.get("pin_hash")
    if not h:
        return False
    return bcrypt.verify(pin, h)
```
This also requires a schema migration (see devops-testing-strategy.md §7.1).

---

**RISK-06: Flutter accepts any TLS certificate unconditionally** *(Critical)*

`api_service.dart` line ~30: `badCertificateCallback = (cert, host, port) => true`. This completely disables TLS validation. Any attacker on the home LAN performing ARP spoofing can intercept all traffic including auth tokens and file contents.

**Fix — Certificate Pinning on First Pair:**

```dart
// api_service.dart
static http.Client _createTlsClient({String? pinnedFingerprint}) {
  final httpClient = HttpClient()
    ..badCertificateCallback = (X509Certificate cert, String host, int port) {
      if (pinnedFingerprint == null) {
        // First connect — record fingerprint, allow
        return true;
      }
      final fingerprint = _sha256Fingerprint(cert.der);
      return fingerprint == pinnedFingerprint;
    };
  return IOClient(httpClient);
}

String _sha256Fingerprint(Uint8List der) {
  return sha256.convert(der).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
}
```

On first successful pairing, store the fingerprint in `SharedPreferences`. On subsequent `ApiService.configure()` calls, pass the stored fingerprint to `_createTlsClient`. A "re-pair" action clears the stored fingerprint and allows one new first-connect.

The QR code generated by `/api/v1/pair/qr` must include the cert fingerprint so the app can pre-pin it before the first connection, eliminating the TOFU (Trust On First Use) window.

---

**RISK-07: JWT secret defaults to `"change-me-in-production"`** *(Critical)*

`config.py` line 26: `jwt_secret: str = "change-me-in-production"`. This is a known-plaintext secret. Any attacker who knows this (it is in a public repo) can forge valid JWTs for any user on any device that was never reconfigured.

**Fix — Auto-generate on first boot:**
```python
# backend/app/config.py
@property
def _secret_file(self) -> Path:
    return self.data_dir / "secret.key"

@property
def jwt_secret(self) -> str:
    if not self._secret_file.exists():
        import secrets
        key = secrets.token_hex(32)
        self._secret_file.write_text(key)
        self._secret_file.chmod(0o600)
        return key
    return self._secret_file.read_text().strip()
```
Remove `jwt_secret` from `BaseSettings` fields entirely. The generated secret persists across restarts. It is never committed to git or exposed in env vars.

---

**RISK-08: No API versioning** *(Medium, but becomes Critical at first breaking change)*

All routes are at `/api/*`. The first time a field is renamed or removed, every installed app breaks simultaneously with no upgrade path.

**Fix:** See Section 2.4.

---

**RISK-09: `ApiService` is a mutable singleton** *(Medium)*

`ApiService.instance` stores `_host` and `_token` as mutable fields. In Riverpod, providers should not depend on mutable singleton state. If the user logs out and logs back in as a different user, stale state can persist. The connection state machine (connected / degraded / offline) has no canonical representation.

**Fix:** See Section 2.5.

---

**RISK-10: Lazy unmount silently masks data loss** *(High)*

`storage_routes.py` falls back to `umount -l` (lazy unmount) if the clean unmount fails. Lazy unmount detaches the filesystem from the directory tree but keeps it alive until all file handles are closed. The NAS drive then sits in a partially-detached state that is invisible to the app. If the user physically removes the USB drive in this state, data loss is near-certain.

**Fix:** Remove the lazy unmount fallback entirely. Either the unmount succeeds cleanly (all handles closed, services stopped) or it fails with a 409. Force only on explicit `?force=true`. Document this clearly in the UI.

---

### 2.2 Target Directory Structure

```
backend/app/
├── routes/           ← HTTP layer ONLY: parse request, call service, format response
│   ├── auth_routes.py
│   ├── file_routes.py
│   ├── storage_routes.py
│   └── ...
├── services/         ← Business logic: no subprocess calls, no HTTP, no Pydantic I/O
│   ├── file_service.py       # list, upload, delete, rename, safe_resolve
│   ├── storage_service.py    # mount, unmount, format, scan, auto-remount
│   ├── monitor_service.py    # system stats aggregation
│   ├── network_service.py    # wifi, hotspot, LAN status
│   └── auth_service.py       # token creation, verification, refresh, revocation
├── system/           ← Low-level I/O adapters: subprocess wrappers only
│   ├── block_devices.py      # lsblk wrapper, device classification
│   ├── proc_reader.py        # /proc/stat, /proc/meminfo, /sys/class/thermal
│   ├── net_utils.py          # nmcli, ip, ethtool wrappers
│   └── subprocess_runner.py  # async subprocess with timeout, logging, path validation
├── models.py         ← Pydantic models (keep)
├── store.py          ← Persistence (atomic writes, locks, schema versioning)
├── auth.py           ← FastAPI auth dependencies (thin, calls auth_service)
├── config.py         ← Settings (fix JWT secret, add debug_mode)
├── middleware.py     ← Request logging, request ID injection
├── logging_config.py ← JSON structured logging setup
└── main.py           ← App factory, middleware registration, router mounting
```

**Rule:** A `routes/` file must never call `subprocess`. A `services/` file must never call `subprocess` directly — it calls `system/subprocess_runner.py`. A `system/` file must never import from `routes/` or `services/`.

---

### 2.3 Subprocess Safety Contract

All subprocess calls must go through a single utility:

```python
# backend/app/system/subprocess_runner.py
import asyncio
import logging
import re
from typing import Sequence

logger = logging.getLogger("cubie.subprocess")

_DEVICE_PATH_RE = re.compile(r"^/dev/[a-z]+[0-9]*(p[0-9]+)?$")

def validate_device_path(path: str) -> str:
    """Raises ValueError if path is not a valid Linux block device path."""
    if not _DEVICE_PATH_RE.match(path):
        raise ValueError(f"Invalid device path: {path!r}")
    return path

async def run(
    cmd: Sequence[str],
    timeout: float = 30.0,
    check: bool = True,
) -> tuple[int, str, str]:
    """
    Run a subprocess command. Never use shell=True.
    Returns (returncode, stdout, stderr).
    Raises asyncio.TimeoutError on timeout.
    Raises subprocess.CalledProcessError on non-zero exit if check=True.
    """
    logger.debug("subprocess.start", extra={"cmd": list(cmd)})
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        raise

    rc = proc.returncode
    out = stdout.decode(errors="replace")
    err = stderr.decode(errors="replace")[:500]  # Truncate long stderr
    logger.debug("subprocess.done", extra={"cmd": cmd[0], "rc": rc, "stderr": err})

    if check and rc != 0:
        raise RuntimeError(f"Command {cmd[0]} failed (rc={rc}): {err}")
    return rc, out, err
```

**Every existing subprocess call in `storage_routes.py` and `network_routes.py` must be replaced with calls to this function.** No exceptions.

---

### 2.4 API Versioning Strategy

**Immediate action:**
- Mount all existing routers under `/api/v1` prefix in `main.py`
- Keep `/api/*` routes active for exactly 2 release cycles (backward compat shim via `APIRouter` with a deprecation middleware)
- Add `GET /api/version` (unversioned, no auth) returning:

```json
{
  "api_version": "v1",
  "backend_version": "0.2.0",
  "min_app_version": "1.1.0",
  "download_url": "https://github.com/your-org/aihomecloud/releases/latest"
}
```

**Breaking change rules:**

| Change type | Action |
|---|---|
| Add optional response field | Safe — no version bump |
| Add optional request field | Safe — no version bump |
| Remove response field | Breaking — bump to v2 |
| Change field type | Breaking — bump to v2 |
| Change required → optional | Breaking — bump to v2 |
| Rename endpoint path | Breaking — bump to v2 |

**Deprecation signaling:**
```python
# In any v1 route that has a v2 equivalent
response.headers["X-Deprecated: true"]
response.headers["X-Sunset-Date: 2026-09-01"]
logger.warning("deprecated_endpoint_called", extra={"path": request.url.path})
```

**Flutter version check:**
```dart
// Call on every successful connect
Future<void> _checkApiVersion() async {
  final v = await apiService.getVersion();
  if (Version.parse(v.minAppVersion) > AppConfig.currentVersion) {
    if (!mounted) return;
    showDialog(context: context, builder: (_) => UpdateRequiredDialog(
      downloadUrl: v.downloadUrl,
    ));
  }
}
```

---

### 2.5 Flutter State Architecture

**Problem with current design:** Six separate `StateProvider` instances read from `SharedPreferences` at construction time. There is no single source of truth for session state. Logout does not cleanly invalidate dependent providers.

**Required replacement — single `AuthSession` notifier:**

```dart
// lib/auth/auth_session.dart
@immutable
class AuthSession {
  final String host;
  final String token;
  final String userName;
  final String certFingerprint;
  const AuthSession({...});
}

class AuthSessionNotifier extends StateNotifier<AuthSession?> {
  final SharedPreferences _prefs;
  AuthSessionNotifier(this._prefs) : super(_load(_prefs));

  static AuthSession? _load(SharedPreferences p) {
    final host = p.getString(CubieConstants.prefDeviceIp);
    final token = p.getString(CubieConstants.prefAuthToken);
    if (host == null || token == null) return null;
    return AuthSession(host: host, token: token, ...);
  }

  Future<void> login(AuthSession session) async {
    await _prefs.setString(CubieConstants.prefDeviceIp, session.host);
    await _prefs.setString(CubieConstants.prefAuthToken, session.token);
    state = session;
  }

  Future<void> logout() async {
    await _prefs.clear();
    state = null;
  }
}

final authSessionProvider = StateNotifierProvider<AuthSessionNotifier, AuthSession?>((ref) {
  return AuthSessionNotifier(ref.read(sharedPreferencesProvider));
});
```

**All data providers must gate on `authSessionProvider`:**
```dart
final deviceInfoProvider = FutureProvider<CubieDevice>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session == null) throw const UnauthenticatedException();
  return ref.read(apiServiceProvider).getDeviceInfo();
});
```

When `logout()` is called, `authSessionProvider.state` becomes `null`, which invalidates all watching providers simultaneously. Clean, deterministic.

---

### 2.6 Connection State Machine

Define three states, surfaced in the app shell:

```dart
enum CubieConnectionState { connected, degraded, offline }

// connected:  WebSocket active, last ping < 5s ago
// degraded:   WebSocket dropped, HTTP still responding
// offline:    Last HTTP call threw SocketException or TimeoutException
```

The connection state must appear as a persistent indicator in the app's `AppBar` or `BottomNavigationBar` — not buried in individual screen error widgets. A red/amber/green dot with a tooltip is sufficient.

---

## Part 3 — Security & Threat Model

### 3.1 Threat Actors

| Actor | Capability | In-scope |
|---|---|---|
| LAN guest (coffee shop or home visitor) | Can observe LAN traffic, send HTTP requests | Yes |
| Stolen phone with app installed | Has stored JWT, may have saved PIN | Yes |
| Physical access to SBC | Can read SD card, users.json | Yes |
| ARP spoofing on home LAN | Full MITM on plaintext/unvalidated TLS | Yes |
| Remote attacker via port-forwarded router | Can reach port 8443 from internet | Yes (if user enables) |
| Nation-state / advanced persistent threat | — | Out of scope for v1 |

---

### 3.2 Vulnerability Register (Current Prototype)

**Critical — Fix before any production deployment:**

| ID | File | Line | Vulnerability | Fix |
|---|---|---|---|---|
| SEC-01 | `config.py` | 26 | JWT secret defaults to known string in public repo | Auto-generate to `/var/lib/cubie/secret.key` on first boot; never in env or git |
| SEC-02 | `api_service.dart` | ~30 | TLS cert accepted unconditionally | Cert fingerprint pinning from QR code on first pair |
| SEC-03 | `store.py` | 44 | PIN stored plaintext | bcrypt hash (cost=10) before storage |
| SEC-04 | Various routes | — | Some subprocess calls use `shell=True` with request-body values | Audit all subprocess calls; enforce `subprocess_runner.py` use |

**High — Fix in next milestone:**

| ID | File | Vulnerability | Fix |
|---|---|---|---|
| SEC-05 | `main.py` | CORS `allow_origins=["*"]` on native app | Remove CORS middleware entirely |
| SEC-06 | `monitor_routes.py` | WebSocket no auth | `?token=` query param validation on upgrade |
| SEC-07 | `auth_routes.py` | No rate limiting on `/api/pair` | `slowapi`: 5 req/min, return 429 |
| SEC-08 | `auth.py` | No server-side token revocation | In-memory denylist (bounded 1000 entries, LRU eviction) |
| SEC-09 | `config.py` | JWT expiry 720 hours | 1-hour access token + 7-day refresh token |

**Medium — Fix before v2.0:**

| ID | File | Vulnerability | Fix |
|---|---|---|---|
| SEC-10 | `file_routes.py` | No upload type restriction | Reject executable extensions |
| SEC-11 | `tls.py` | Cert fingerprint not included in QR code | Embed fingerprint in QR payload |
| SEC-12 | `store.py` | users.json default permissions | `os.chmod(0o600)` after every write |
| SEC-13 | `family_routes.py` | Any authenticated user can add family members | Require `require_admin` on POST /api/v1/users/family |

---

### 3.3 Pairing Security — Required Redesign

**Current model is broken:** The `pairing_key` in `config.py` is a static secret. If it is observed once (from the QR code, from the service file, from the git repo), any device can pair with any Cubie running the default config.

**Required model — time-limited OTP:**

```
Admin opens "Add Device" in app
         │
         ▼
Backend: POST /api/v1/pair/generate-otp (requires admin JWT)
         │ → generates 6-digit OTP, stores in memory with 5-minute TTL
         │ → returns QR payload: {serial, otp, ip, certFingerprint}
         ▼
Backend: GET /api/v1/pair/qr → displays QR to admin on screen (or terminal)
         │
         ▼
New device scans QR → extracts {serial, otp, ip, certFingerprint}
         │ → pins certFingerprint before connecting
         │ → POST /api/v1/pair {serial, otp}
         ▼
Backend: validates OTP (single-use, 5-min TTL), issues JWT
         │ → OTP is immediately invalidated after one use
         ▼
Device receives JWT → stored in SharedPreferences
```

This eliminates the static secret entirely. An observed OTP is useless after 5 minutes or after first use.

---

### 3.4 systemd Hardening

The `cubie-backend.service` unit must be hardened:

```ini
[Unit]
Description=AiHomeCloud Backend
After=network.target

[Service]
User=cubie
Group=cubie
WorkingDirectory=/opt/cubie/backend
EnvironmentFile=/var/lib/cubie/cubie.env
ExecStartPre=/opt/cubie/scripts/setup-secrets.sh
ExecStart=/opt/cubie/venv/bin/uvicorn app.main:app \
    --host 0.0.0.0 \
    --port 8443 \
    --ssl-certfile /var/lib/cubie/tls/cert.pem \
    --ssl-keyfile /var/lib/cubie/tls/key.pem \
    --workers 1
Restart=on-failure
RestartSec=5s

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/srv/nas /var/lib/cubie
PrivateTmp=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
# mount/umount via sudo wrapper — NOT via direct capability

[Install]
WantedBy=multi-user.target
```

**For mount/umount operations**, the `cubie` user requires a narrow sudoers entry:
```
# /etc/sudoers.d/cubie-mount
cubie ALL=(root) NOPASSWD: /bin/mount /dev/* /srv/nas, /bin/umount /srv/nas
```
The route handler calls `sudo mount /dev/sdX1 /srv/nas` via the subprocess runner. It does not have general root privileges.

---

### 3.5 Data Classification & Protection

| Data | Location | Classification | Required Protection |
|---|---|---|---|
| JWT secret | `/var/lib/cubie/secret.key` | Secret | `0600`, cubie-owned, never in env/git |
| TLS private key | `/var/lib/cubie/tls/key.pem` | Secret | `0600`, cubie-owned |
| User PINs | `users.json` | Confidential | bcrypt hash, `0600` |
| JWT tokens | Client `SharedPreferences` | Confidential | Short TTL (1h), revocable |
| NAS file content | `/srv/nas/` | User data | Per-user dir permissions, sandbox enforced |
| Device config | `services.json`, `storage.json` | Internal | `0644` acceptable |
| Backend logs | journald | Operational | No PII in logs (file paths, usernames redacted at DEBUG) |

---

### 3.6 Known Acceptable Trade-offs

These are deliberate decisions, not oversights:

| Trade-off | Decision | Rationale |
|---|---|---|
| Self-signed TLS vs. Let's Encrypt | Self-signed, cert-pinned | No public DNS for local device; ACME requires outbound internet |
| Single-process uvicorn vs. gunicorn + workers | Single worker | ≤ 8 concurrent users, RAM ceiling 256 MB; multi-worker doubles memory |
| JSON files vs. SQLite vs. PostgreSQL | JSON files (v1), SQLite (v2) | No database daemon on ARM saves ~50 MB RAM; JSON is sufficient for ≤ 8 users |
| No file encryption at rest | Unencrypted NAS data | Physical security is the user's responsibility; adds significant overhead for ARM CPU |
| No 2FA | PIN only | 2FA on a local home device adds friction with minimal threat reduction |

---

*Document continues in `devops-testing-strategy.md`*
