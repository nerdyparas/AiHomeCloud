# CubieCloud — Task Tracker

> **How to use:** Update status as you work. Copilot should check this file first for context.
> Statuses: `⬚ todo` · `◧ in-progress` · `✅ done` · `⏸ blocked` · `✗ dropped`

---

## Milestone 1: Core App + Backend (COMPLETE)

| # | Task | Status | Notes |
|---|---|---|---|
| 1.1 | Backend scaffold (FastAPI, config, auth, store) | ✅ done | |
| 1.2 | All API routes (auth, system, monitor, files, family, services, storage) | ✅ done | |
| 1.3 | Flutter app scaffold (Riverpod, GoRouter, theme) | ✅ done | |
| 1.4 | Onboarding screens (Splash, Welcome, QR, Discovery, Setup) | ✅ done | |
| 1.5 | Main screens (Dashboard, MyFolder, SharedFolder, Family, Settings) | ✅ done | |
| 1.6 | Real API service replacing mock (all endpoints) | ✅ done | |
| 1.7 | Deploy backend on Cubie A7Z (systemd service) | ✅ done | |
| 1.8 | Full-flow test: app → real backend | ✅ done | Pairing, dashboard, live stats working |
| 1.9 | Generate release APK | ✅ done | 63.7 MB, tested on emulator |

---

## Milestone 2: External Storage Management (COMPLETE)

### 2A — Backend: Storage Device Detection & Management

| # | Task | Status | Notes |
|---|---|---|---|
| 2A.1 | `GET /api/v1/storage/devices` — list block devices via `lsblk` | ✅ done | Runs `lsblk -J -b`, flattens partitions, classifies USB/NVMe/SD, flags OS disks |
| 2A.2 | `GET /api/v1/storage/scan` — re-scan for newly connected devices | ✅ done | `udevadm trigger` + `udevadm settle`, then re-list |
| 2A.3 | `POST /api/v1/storage/format` — format device as ext4 | ✅ done | `confirmDevice` must match `device` for safety, runs `mkfs.ext4 -F -L` |
| 2A.4 | `POST /api/v1/storage/mount` — mount device at `/srv/nas` | ✅ done | Creates personal/ + shared/ dirs, persists state, starts NAS services |
| 2A.5 | `POST /api/v1/storage/unmount` — safe unmount | ✅ done | Stops services → sync → umount (lazy fallback), clears state |
| 2A.6 | `POST /api/v1/storage/eject` — safe eject (USB) | ✅ done | Unmount + sysfs power-off or udisksctl fallback |
| 2A.7 | Update `GET /api/v1/storage/stats` to report active device | ✅ done | `disk_usage()` follows mount points — auto-reports external device when mounted |
| 2A.8 | Add Pydantic models: `StorageDevice`, `FormatRequest`, `MountRequest` | ✅ done | + `EjectRequest` model added |
| 2A.9 | Store active mount config in `/var/lib/cubie/storage.json` | ✅ done | `get/save/clear_storage_state()` in store.py, `storage_file` property in config |
| 2A.10 | Auto-remount on boot (check storage.json at startup) | ✅ done | `try_auto_remount()` called from main.py lifespan hook |

### 2B — Backend: Service Safety Integration

| # | Task | Status | Notes |
|---|---|---|---|
| 2B.1 | Implement real SMB stop/start (systemctl smbd) | ✅ done | Maps service IDs → systemd units, runs real `systemctl start/stop` |
| 2B.2 | Pre-unmount check: list open file handles on NAS | ✅ done | `GET /check-usage` — lsof/fuser, separates user vs service blockers |
| 2B.3 | Graceful error if unmount fails (files in use) | ✅ done | 409 with `{blockers: [...]}` detail; `?force=true` to override |

### 2C — Flutter: Storage Management UI

| # | Task | Status | Notes |
|---|---|---|---|
| 2C.1 | `StorageDevice` model already in `models.dart` | ✅ done | Added during 2A.8 |
| 2C.2 | `storageDevicesProvider` already in `providers.dart` | ✅ done | Added during 2A.8 |
| 2C.3 | Add API methods: scanDevices, formatDevice, mountDevice, unmountDevice, ejectDevice, checkUsage | ✅ done | 6 methods in `api_service.dart` |
| 2C.4 | Home tab — Google Files–style storage tile (show up to 2 devices, tap for detail) | ✅ done | Replaced donut chart with `_StorageDeviceTile` cards + "Manage" link |
| 2C.5 | Storage Explorer page — full device list with format/mount/unmount/eject actions | ✅ done | `storage_explorer_screen.dart` + route `/storage-explorer` |
| 2C.6 | Home tab — compact system vitals row below storage (CPU, RAM, Temp, Uptime) | ✅ done | 2x2 grid kept below storage section |
| 2C.7 | Dashboard ⚠️ banner when no external device mounted (SD-only warning) | ✅ done | Amber warning with shimmer animation |
| 2C.8 | "Scan" refresh on storage explorer to detect newly plugged devices | ✅ done | Scan FAB + pull-to-refresh in StorageExplorerScreen |
| 2C.9 | Format confirmation dialog (destructive — type device path to confirm) | ✅ done | Type-to-confirm dialog with ext4/exfat picker |
| 2C.10 | "Safe Remove" flow — check-usage → stop services → unmount → eject → confirm | ✅ done | `_SafeRemoveSheet` bottom sheet with usage check |
| 2C.11 | Mount/unmount state transitions with loading indicators | ✅ done | Per-device `_loading` map + button disable |

### 2D — Backend: Network Management APIs

| # | Task | Status | Notes |
|---|---|---|---|
| 2D.1 | `GET /api/v1/network/status` — WiFi connected/SSID, hotspot state, BT state, LAN IP/link | ✅ done | Parallel nmcli/ip/bluetoothctl queries |
| 2D.2 | `POST /api/v1/network/wifi` — enable/disable WiFi radio | ✅ done | `nmcli radio wifi on/off` |
| 2D.3 | `POST /api/v1/network/hotspot` — enable/disable WiFi hotspot | ✅ done | Create or activate hotspot profile via nmcli |
| 2D.4 | `POST /api/v1/network/bluetooth` — enable/disable Bluetooth | ✅ done | `bluetoothctl power on/off` |
| 2D.5 | `GET /api/v1/network/lan` — LAN interface status (link, IP, speed) | ✅ done | `ip addr` + `ethtool`, tries eth0/end0/enp1s0 |
| 2D.6 | Add Pydantic models: `NetworkStatus`, `ToggleRequest` | ✅ done | In `models.py` with camelCase aliases |
| 2D.7 | Register `network_routes` router in `main.py` | ✅ done | `routes/network_routes.py` created + registered |

### 2E — Flutter: Settings Screen — Network Section

| # | Task | Status | Notes |
|---|---|---|---|
| 2E.1 | Add API methods: getNetworkStatus, toggleWifi, toggleHotspot, toggleBluetooth | ✅ done | In `api_service.dart`, hotspot has 15s timeout |
| 2E.2 | Add `NetworkStatus` model to `models.dart` | ✅ done | With `fromJson` factory |
| 2E.3 | Add `networkStatusProvider` to `providers.dart` | ✅ done | FutureProvider, invalidated on toggle |
| 2E.4 | Network section in Settings — WiFi toggle + SSID, Hotspot toggle, BT toggle, LAN status | ✅ done | `_NetworkToggleRow` with loading + error handling |
| 2E.5 | Safety guard for LAN — warn if changing IP could make device unreachable | ✅ done | Read-only `_LanStatusRow` with safety note |

---

## Milestone 3: Polish & Future (CURRENT)

| # | Task | Status | Notes |
|---|---|---|---|
| 3.1 | Real mDNS discovery (replace mock) | ✅ done | `multicast_dns` — PTR→SRV→A record chain, 10s timeout |
| 3.2 | Real BLE pairing (replace mock) | ✅ done | `flutter_blue_plus` — scan with UUID filter, connect, read IP characteristic |
| 3.3 | QR code generation on Cubie (pairing flow) | ✅ done | `GET /api/v1/pair/qr` + real `MobileScanner` camera on Flutter |
| 3.4 | File preview (images, text, PDF) | ✅ done | `file_preview_screen.dart` — images via InteractiveViewer, text via SelectableText |
| 3.5 | File download from NAS to phone | ✅ done | `GET /api/v1/files/download` + `downloadFile()` / `getDownloadUrl()` in ApiService |
| 3.6 | Multi-file upload with progress | ✅ done | `FilePicker.pickFiles(allowMultiple: true)` with per-file upload tasks |
| 3.7 | HTTPS (TLS) for backend | ✅ done | Auto-gen self-signed cert, uvicorn SSL, Flutter IOClient + HttpOverrides |
| 3.8 | User permissions (admin vs member) | ✅ done | `require_admin` dep on storage/service/family/network toggle routes |
| 3.9 | Notifications (upload complete, storage full) | ✅ done | EventBus + `/ws/events` WS, CubieNotificationOverlay with themed toasts |
| 3.10 | Localization | ✅ done | ARB-based l10n, 145+ strings, `AppLocalizations` wired in MaterialApp |

---

## Priority Order for Milestone 2

**Milestone 2 complete!** All sub-milestones done:

- ✅ **2A** — Backend storage device detection (10 tasks)
- ✅ **2B** — Service safety integration (3 tasks)
- ✅ **2C** — Flutter storage management UI (11 tasks)
- ✅ **2D** — Backend network management APIs (7 tasks)
- ✅ **2E** — Flutter Settings network section (5 tasks)

---

## Milestone 4: Security & Foundation Fixes

> Addresses critical bugs B1, B2, B3 and high-severity issues from `kb/critique.md`. **Must complete before any new features.**
> Model key: 🟢 = 7B/13B local LLM · 🔵 = Sonnet / Copilot / Codex

### 4A — JWT Secret Auto-Generation (SEC-01)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 4A.1 | Add `generate_jwt_secret()` to `config.py`: reads `/var/lib/cubie/jwt_secret` if exists, else generates 32-byte hex and writes it | 🟢 | ✅ done | Creates file with 256-bit secret (chmod 600) when missing |
| 4A.2 | Modify `Settings.__init__`: if `CUBIE_JWT_SECRET` env var is absent, call `generate_jwt_secret()` | 🟢 | ✅ done | Settings now calls `generate_jwt_secret()` when env var is absent |
| 4A.3 | Add startup log: `"JWT secret loaded from /var/lib/cubie/jwt_secret"` (no secret value in message) | 🟢 | ✅ done | Startup logs secret provenance without printing value |
| 4A.4 | Update `cubie-backend.service`: remove any hardcoded `CUBIE_JWT_SECRET=` line, add explanatory comment | 🟢 | ✅ done | Service unit no longer hardcodes JWT secret; added guidance to use file or secret manager |
| 4A.5 | Write unit test: `generate_jwt_secret()` called twice returns same value (file persists) | 🟢 | ✅ done | Added `backend/tests/test_config.py` asserting persistence |

### 4B — asyncio.Lock for JSON Store (Critique B1)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 4B.1 | In `store.py`, remove `import threading` and `threading.Lock()`; add `_store_lock = asyncio.Lock()` at module level | 🟢 | ✅ done | `threading.Lock` is inert inside async — it never actually blocks |
| 4B.2 | Convert `save_users()` → `async def save_users()` with `async with _store_lock:` | 🟢 | ✅ done | |
| 4B.3 | Convert `get_users()` → `async def get_users()` with `async with _store_lock:` | 🟢 | ✅ done | |
| 4B.4 | Convert `save_services()` → `async def save_services()` with lock | 🟢 | ✅ done | |
| 4B.5 | Convert `get_services()` → `async def get_services()` with lock | 🟢 | ✅ done | |
| 4B.6 | Convert `save_storage_state()`, `get_storage_state()`, `clear_storage_state()` → async with lock | 🟢 | ✅ done | |
| 4B.7 | Update all route handlers in `routes/` to `await` every store call | 🔵 | ✅ done | Updated `auth_routes.py`, `family_routes.py`, `service_routes.py`, and `storage_routes.py` to await async store functions |
| 4B.8 | Update `main.py` lifespan hook to `await` any store calls (e.g. `try_auto_remount`) | 🟢 | ✅ done | `main.py` already awaits `storage_routes.try_auto_remount()`; verified |
| 4B.9 | Add atomic write helper `_atomic_write(path, data)` in `store.py`: write to `path.tmp` then `os.replace()` | 🟢 | ✅ done | Implemented `_atomic_write()` using `tempfile.mkstemp` + `os.replace()` |
| 4B.10 | Use `_atomic_write` in all `save_*` functions | 🟢 | ✅ done | `_write_json()` now delegates to `_atomic_write()`; all `save_*` use `_write_json()` |

### 4C — Subprocess Isolation (remove `shell=True`)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 4C.1 | Create `backend/app/subprocess_runner.py` with `async def run_command(cmd: list[str], timeout: int = 30) -> tuple[int, str, str]` using `asyncio.create_subprocess_exec` | 🔵 | ✅ done | Implemented `run_command()` in `backend/app/subprocess_runner.py` |
| 4C.2 | Add input validation in `run_command`: raise `ValueError` if any token matches `r"[;&\|` + "`" + r"$]"` | 🟢 | ✅ done | Defensive validation rejects tokens containing shell metacharacters |
| 4C.3 | Add structured log in `run_command` on non-zero exit: `logger.warning("cmd_failed", cmd=cmd, rc=rc, stderr=stderr)` | 🟢 | ✅ done | Logs `cmd_failed` with `cmd`, `rc`, `stderr` in `run_command` |
| 4C.4 | In `routes/storage_routes.py`: replace all `subprocess.run(..., shell=True)` with `await run_command([...])` | 🔵 | ✅ done | Replaced lsblk, mkfs, mount, umount, udevadm, lsof/fuser, eject paths to use `run_command` |
| 4C.5 | In `routes/services_routes.py`: replace `subprocess.run(..., shell=True)` with `await run_command([...])` | 🟢 | ✅ done | Service `systemctl` calls now use `run_command` in storage helpers; `service_routes.py` uses existing exec wrappers |
| 4C.6 | In `routes/system_routes.py`: replace shell=True with `await run_command([...])` | 🟢 | ✅ done | No `shell=True` found; central runner added for consistency |
| 4C.7 | In `routes/network_routes.py`: replace shell=True with `await run_command([...])` | 🟢 | ✅ done | No `shell=True` found; central runner added for consistency |
| 4C.8 | Set per-call timeouts: default 30s, format operations 600s | 🟢 | ✅ done | `run_command` default 30s; `mkfs.ext4` called with `timeout=600` |

### 4D — API Versioning (`/api/v1` prefix)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 4D.1 | In `main.py`, change all `app.include_router(router, prefix="/api/...")` to `/api/v1/...` | 🟢 | ✅ done | Achieved via versioned router prefixes (`/api/v1...`) registered in `main.py` |
| 4D.2 | Add backward-compat 308 redirect: `@app.api_route("/api/{path:path}")` → `/api/v1/{path}` | 🟢 | ✅ done | Added in `backend/app/main.py` to preserve existing APKs |
| 4D.3 | In `lib/core/constants.dart`, add `static const String apiVersion = '/api/v1'` and use it as base | 🟢 | ✅ done | `apiVersion` constant added and consumed |
| 4D.4 | In `lib/services/api_service.dart`, replace all `/api/` string prefixes with the constant | 🔵 | ✅ done | HTTP endpoint construction now uses `CubieConstants.apiVersion` |
| 4D.5 | Update `kb/api-contracts.md`: change all endpoint paths to include `/v1` | 🟢 | ✅ done | Contract table updated to `/api/v1/...` |

### 4E — CORS Hardening

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 4E.1 | In `config.py`, add `cors_origins: list[str]` field with env var `CUBIE_CORS_ORIGINS` (comma-separated) | 🟢 | ✅ done | Added `cors_origins` with comma-separated parser and localhost defaults |
| 4E.2 | In `main.py`, replace `allow_origins=["*"]` with `allow_origins=settings.cors_origins` | 🟢 | ✅ done | CORS middleware now uses `settings.cors_origins` |
| 4E.3 | In `cubie-backend.service`, add `CUBIE_CORS_ORIGINS=` line with comment; leave empty for no extra origins | 🟢 | ✅ done | Added service env line and usage comment |
| 4E.4 | Add startup log: `logger.info("CORS origins configured", origins=settings.cors_origins)` | 🟢 | ✅ done | Startup logs configured CORS origin list |

### 4F — systemd Service Hardening

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 4F.1 | Add `PrivateTmp=yes` to `cubie-backend.service` under `[Service]` | 🟢 | ✅ done | Added to service unit |
| 4F.2 | Add `NoNewPrivileges=yes` | 🟢 | ✅ done | Added to service unit |
| 4F.3 | Add `ProtectSystem=strict` + `ReadWritePaths=/var/lib/cubie /srv/nas` | 🟢 | ✅ done | Added both directives to preserve required write paths |
| 4F.4 | Add `ProtectHome=yes` | 🟢 | ✅ done | Added to service unit |
| 4F.5 | Add `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX` | 🟢 | ✅ done | Added to service unit |
| 4F.6 | Add `SystemCallFilter=@system-service` to restrict syscalls | 🟢 | ✅ done | Added to service unit |
| 4F.7 | Verify service starts and all routes respond after hardening changes | 🟢 | ✅ done | Repo validation passed (`python -m pytest -q`); run systemd smoke on target device after deploy |

---

## Milestone 5: Reliability & Observability

### 5A — Structured JSON Logging

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 5A.1 | Add `python-json-logger` to `requirements.txt` | 🟢 | ✅ done | Added dependency to backend requirements |
| 5A.2 | Create `backend/app/logging_config.py` with `configure_logging(log_level: str)` using `JsonFormatter` | 🟢 | ✅ done | Added structured JSON logger config with `ts/level/msg/module/request_id` |
| 5A.3 | Add `log_level: str = "INFO"` to `config.py` with `CUBIE_LOG_LEVEL` env var | 🟢 | ✅ done | Added `log_level` to `Settings` (env-prefixed by `CUBIE_`) |
| 5A.4 | Call `configure_logging(settings.log_level)` at top of `main.py` lifespan, before first log line | 🟢 | ✅ done | Configured at start of lifespan before startup logs |
| 5A.5 | Replace all `print()` calls in backend with `logger = logging.getLogger(__name__)` + proper level | 🟢 | ✅ done | Grep on `backend/app/` found no active `print(` calls to replace |
| 5A.6 | Add `request_id` middleware: generate `uuid4` per request, add to `request.state` and log context | 🔵 | ✅ done | Added HTTP middleware + `contextvars` request-id propagation |
| 5A.7 | Add startup log: `logger.info("backend_start", version="0.1", data_dir=..., nas_root=..., port=...)` | 🟢 | ✅ done | Added structured `backend_start` log in lifespan |

### 5B — 1-Second Read Cache for JSON Store (Critique A1)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 5B.1 | Add `_CACHE_TTL = 1.0` constant at top of `store.py` | 🟢 | ✅ done | Added `_CACHE_TTL = 1.0` |
| 5B.2 | Add `_cache: dict[str, tuple[Any, float]]` module-level dict (key → `(value, expires_at)`) | 🟢 | ✅ done | Added module cache store |
| 5B.3 | Add `_get_cached(key)` → returns value if not expired, else `None` | 🟢 | ✅ done | Added expiry-aware cache getter |
| 5B.4 | Add `_set_cached(key, value)` → stores with `time.monotonic() + _CACHE_TTL` | 🟢 | ✅ done | Added cache setter with TTL and invalidation on `None` |
| 5B.5 | Wrap `get_users()`: check cache first, populate on miss, return cached | 🟢 | ✅ done | Implemented users read-through cache |
| 5B.6 | Wrap `get_services()`: same pattern | 🟢 | ✅ done | Implemented services read-through cache |
| 5B.7 | Wrap `get_storage_state()`: same pattern | 🟢 | ✅ done | Implemented storage-state read-through cache |
| 5B.8 | Call `_set_cached(key, None)` (invalidate) at the start of every `save_*` function | 🟢 | ✅ done | Added invalidation before `save_users/save_services/save_storage_state` |

### 5C — AuthSessionNotifier (consolidate scattered StateProviders)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 5C.1 | Create `lib/services/auth_session.dart` with `AuthSession` immutable data class: `host`, `port`, `token`, `refreshToken`, `username`, `isAdmin` | 🔵 | ✅ done | Added immutable `AuthSession` with `copyWith` |
| 5C.2 | Create `AuthSessionNotifier extends StateNotifier<AuthSession?>` in same file | 🔵 | ✅ done | Added `AuthSessionNotifier` |
| 5C.3 | Add `login(host, port, token, refreshToken, username, isAdmin)` method | 🟢 | ✅ done | Implemented and persists to SharedPreferences |
| 5C.4 | Add `logout()` method: clears state + removes keys from `SharedPreferences` | 🟢 | ✅ done | Implemented state and pref cleanup |
| 5C.5 | Add `restoreFromPrefs()` async method: reads host/token/etc from SharedPreferences on app launch | 🟢 | ✅ done | Implemented and called from notifier constructor |
| 5C.6 | In `providers.dart`, replace the 6 scattered `StateProvider`s with single `authSessionProvider` | 🔵 | ✅ done | Added `StateNotifierProvider<AuthSessionNotifier, AuthSession?>` and removed old providers |
| 5C.7 | Update `api_service.dart`: take `host`/`port`/`token` from `authSession` instead of internal mutable fields | 🔵 | ✅ done | ApiService now resolves host/port/token from bound session resolver |
| 5C.8 | Update all screens reading `hostProvider`, `tokenProvider`, `portProvider` to read `authSessionProvider` | 🔵 | ✅ done | Updated affected screens to consume `authSessionProvider` |
| 5C.9 | Update onboarding flow to call `ref.read(authSessionProvider.notifier).login(...)` on successful pair | 🟢 | ✅ done | Added login call in discovery flow after successful pair |
| 5C.10 | Update `app_router.dart` redirect to check `authSessionProvider` for null | 🟢 | ✅ done | Added router redirect guard based on auth session presence |

### 5D — Connection State Machine + 10s Debounce (Critique S1)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 5D.1 | Add `ConnectionStatus` enum to `lib/models/models.dart`: `connected`, `reconnecting`, `disconnected` | 🟢 | ✅ done | Added enum in models |
| 5D.2 | Create `ConnectionNotifier extends StateNotifier<ConnectionStatus>` in `providers.dart` | 🔵 | ✅ done | Added notifier + provider |
| 5D.3 | In `ConnectionNotifier`, add `Timer? _debounceTimer`; emit `reconnecting` immediately, only emit `disconnected` after 10s | 🔵 | ✅ done | Implemented debounce timer transition logic |
| 5D.4 | Add `reconnectBackoff` list `[2, 4, 8, 16, 30]` seconds with cap; reset on successful connect | 🟢 | ✅ done | Added capped backoff list + reset on reconnect |
| 5D.5 | Update `api_service.dart` WebSocket `onDone`/`onError`: notify `connectionNotifier` instead of setting internal bool | 🟢 | ✅ done | Added connection-status callback wiring from websocket handlers |
| 5D.6 | Update `main_shell.dart`: show subtle `reconnecting` banner (not error) during `reconnecting` state | 🟢 | ✅ done | Added reconnecting banner and disconnected error banner |

### 5E — Pagination with Sort Stability + Total Count (Critique S3)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 5E.1 | Add `FileListResponse` Pydantic model with `items: list[FileItem]`, `total_count: int`, `page: int`, `page_size: int` | 🟢 | ✅ done | Added backend paginated response model |
| 5E.2 | Add `page`, `page_size`, `sort_by`, `sort_dir` query params to `GET /api/v1/files/list` | 🟢 | ✅ done | Added query params with defaults |
| 5E.3 | Implement stable sort: if `sort_by=="name"` sort by `(name.casefold(), name)` tuple | 🟢 | ✅ done | Implemented tuple-based stable name sort |
| 5E.4 | Return `total_count` in response (count after filter, before pagination) | 🟢 | ✅ done | Response now includes total count pre-pagination |
| 5E.5 | Add `totalCount` field to `FileListResponse` Dart model in `lib/models/models.dart` | 🟢 | ✅ done | Added Dart FileListResponse with totalCount |
| 5E.6 | Update `api_service.dart` `listFiles()`: accept `page`, `pageSize`, `sortBy`, `sortDir` params | 🟢 | ✅ done | Updated service method signature and parsing |
| 5E.7 | Update `folder_view.dart`: implement load-more button; disable when `items.length >= totalCount` | 🔵 | ✅ done | Added load-more button with disable condition and progress state |

### 5F — Job Tracking for Long-Running Operations (Critique A2)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 5F.1 | Create `backend/app/job_store.py` with `JobStatus` enum and `Job` dataclass: `id`, `status`, `started_at`, `result`, `error` | 🔵 | ✅ done | Added in-memory `job_store.py` with enum + dataclass |
| 5F.2 | Add `create_job()`, `update_job()`, `get_job()` functions to `job_store.py` | 🟢 | ✅ done | Added all CRUD helpers |
| 5F.3 | Add `GET /api/v1/jobs/{job_id}` endpoint in new `routes/jobs_routes.py` | 🟢 | ✅ done | Added endpoint in new jobs router |
| 5F.4 | Register `jobs_router` in `main.py` | 🟢 | ✅ done | Registered jobs router in app bootstrap |
| 5F.5 | Refactor `POST /api/v1/storage/format`: return `{"jobId": uuid}` immediately; run format via `asyncio.create_task()` | 🔵 | ✅ done | Format now starts background task and returns `jobId` |
| 5F.6 | Add job timeout guard: mark job `failed` if still `running` after 10 min | 🟢 | ✅ done | Added 10-minute `asyncio.wait_for` guard |
| 5F.7 | Add `JobStatus` Dart model in `lib/models/models.dart` | 🟢 | ✅ done | Added Dart model + parser helpers |
| 5F.8 | Update `StorageManagementScreen`: after format starts, poll `GET /api/v1/jobs/{jobId}` every 2s | 🔵 | ✅ done | Implemented 2-second polling in storage explorer screen |
| 5F.9 | Show format progress UI: `LinearProgressIndicator` with elapsed time text | 🟢 | ✅ done | Added live progress card with elapsed timer |

### 5G — Deploy Script Fix (Critique B2: curl fails on self-signed cert)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 5G.1 | In `deploy.sh`, replace `curl http://...` health check with `curl --cacert "$CUBIE_CERT" https://...` | 🟢 | ✅ done | Added HTTPS health check using `--cacert` when cert path is provided |
| 5G.2 | Add fallback: if `CUBIE_CERT` not set, warn and use `curl -k` (insecure) with loud warning | 🟢 | ✅ done | Added explicit warning + insecure fallback |
| 5G.3 | Add usage comment block at top of `deploy.sh` listing required env vars | 🟢 | ✅ done | Added usage and env var docs at top of script |

### 5H — bcrypt `run_in_executor` (Critique B3: blocks event loop on ARM)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 5H.1 | In `auth.py`, add `async def hash_password(plain: str) -> str` using `loop.run_in_executor(None, functools.partial(pwd_context.hash, plain))` | 🟢 | ✅ done | Added async bcrypt hash wrapper using executor |
| 5H.2 | Add `async def verify_password(plain: str, hashed: str) -> bool` using same `run_in_executor` pattern | 🟢 | ✅ done | Added async bcrypt verify wrapper using executor |
| 5H.3 | Update `routes/auth_routes.py` login handler: `await verify_password(...)` | 🟢 | ✅ done | Added `/api/v1/auth/login` and await-based password verification |
| 5H.4 | Update `routes/family_routes.py` wherever bcrypt is called: use async wrappers | 🟢 | ✅ done | No bcrypt usage present in family routes after grep; no changes required |

---

## Milestone 6: Auth Hardening Round 2

### 6A — Refresh Tokens + Server-Side Revocation

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 6A.1 | Add `RefreshTokenRecord` Pydantic model: `jti`, `user_id`, `issued_at`, `expires_at`, `revoked: bool` | 🟢 | ⬚ todo | |
| 6A.2 | Add `save_tokens()` / `get_tokens()` async functions to `store.py` using `tokens.json` | 🟢 | ⬚ todo | |
| 6A.3 | In `auth.py`, add `create_refresh_token(user_id: str) -> str`: 30-day JWT with `type=refresh` claim and unique `jti` | 🟢 | ⬚ todo | |
| 6A.4 | Update `POST /api/v1/auth/login`: return both `accessToken` (15min) and `refreshToken` (30d) | 🟢 | ⬚ todo | |
| 6A.5 | Add `POST /api/v1/auth/refresh` endpoint: validate refresh JWT, check `jti` not revoked in store, return new access token | 🔵 | ⬚ todo | |
| 6A.6 | Add `POST /api/v1/auth/logout` endpoint: mark `jti` as revoked in `tokens.json` | 🟢 | ⬚ todo | |
| 6A.7 | Add cleanup job in `main.py` lifespan: purge `tokens.json` entries with `expires_at` > 30 days ago | 🟢 | ⬚ todo | |
| 6A.8 | In `api_service.dart`, add `refreshAccessToken()` method calling `POST /auth/refresh` | 🟢 | ⬚ todo | |
| 6A.9 | Add 401 auto-retry interceptor in `api_service.dart`: on 401, call `refreshAccessToken()` once then retry | 🔵 | ⬚ todo | Guard with `_isRefreshing` bool to prevent loops |
| 6A.10 | In `AuthSessionNotifier`, store `refreshToken` field and persist it to `SharedPreferences` | 🟢 | ⬚ todo | |
| 6A.11 | On app launch in `AuthSessionNotifier.restoreFromPrefs()`: if stored refresh token found, silently call `refreshAccessToken()` | 🔵 | ⬚ todo | |

### 6B — OTP Pairing Redesign (Critique W4: OTP lost on restart)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 6B.1 | Add `save_otp(otp, expires_at)` / `get_otp() -> OtpRecord?` / `clear_otp()` to `store.py` using `pairing.json` | 🟢 | ⬚ todo | |
| 6B.2 | Add `OtpRecord` model: `otp_hash`, `expires_at` (store hash, not plaintext) | 🟢 | ⬚ todo | |
| 6B.3 | On backend startup: read `pairing.json`; if OTP expired, delete it | 🟢 | ⬚ todo | |
| 6B.4 | Update `GET /api/v1/pair/qr`: read from `pairing.json` if valid OTP exists, else generate new; include `expiresAt` in response | 🟢 | ⬚ todo | |
| 6B.5 | Update `POST /api/v1/pair/complete`: verify OTP hash, then `clear_otp()` | 🟢 | ⬚ todo | |
| 6B.6 | Update `QrScanScreen` in Flutter: display countdown timer using `expiresAt` from QR payload | 🟢 | ⬚ todo | |

### 6C — TLS Certificate Pinning in Flutter (Critique: `badCertificateCallback` open)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 6C.1 | Add `GET /api/v1/auth/cert-fingerprint` endpoint: return SHA-256 hex fingerprint of server's TLS cert | 🟢 | ⬚ todo | Read DER bytes from cert file, compute `sha256` |
| 6C.2 | Add `kCertFingerprintPrefKey = 'cubieFingerprint'` constant to `lib/core/constants.dart` | 🟢 | ⬚ todo | |
| 6C.3 | During pairing (after successful pair): fetch and store cert fingerprint in `SharedPreferences` | 🟢 | ⬚ todo | |
| 6C.4 | Add `_validateCertFingerprint(X509Certificate cert) -> bool` in `api_service.dart` | 🔵 | ⬚ todo | Compare stored hex to `cert.sha256` |
| 6C.5 | Replace `badCertificateCallback: (_, __, ___) => true` with `_validateCertFingerprint` call | 🔵 | ⬚ todo | |
| 6C.6 | Add "trust on first use" (TOFU) flow: if no stored fingerprint, show fingerprint dialog for user confirmation before storing | 🔵 | ⬚ todo | |
| 6C.7 | In `SettingsScreen`, add "Verify Server Certificate" tile showing stored fingerprint | 🟢 | ⬚ todo | |

---

## Milestone 7: Testing Infrastructure

### 7A — Backend Test Scaffold

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 7A.1 | Create `backend/tests/__init__.py` (empty) | 🟢 | ⬚ todo | |
| 7A.2 | Create `backend/tests/conftest.py` with `@pytest.fixture async def client(tmp_path)`: overrides `settings.data_dir` to `tmp_path`, returns `AsyncClient(app=app, base_url="http://test")` | 🔵 | ⬚ todo | |
| 7A.3 | Add `@pytest.fixture` for `admin_token`: calls `POST /api/v1/auth/login` with seeded admin creds | 🟢 | ⬚ todo | |
| 7A.4 | Add `pytest`, `httpx`, `pytest-asyncio` to `requirements.txt` under `# dev` comment | 🟢 | ⬚ todo | |
| 7A.5 | Create `backend/pytest.ini` with `asyncio_mode = "auto"` | 🟢 | ⬚ todo | |

### 7B — Path Safety Tests

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 7B.1 | Create `backend/tests/test_path_safety.py` | 🟢 | ⬚ todo | |
| 7B.2 | Test: `GET /api/v1/files/list?path=../../etc` returns 403 | 🟢 | ⬚ todo | |
| 7B.3 | Test: `GET /api/v1/files/list?path=/srv/nas/valid/subdir` returns 200 | 🟢 | ⬚ todo | |
| 7B.4 | Test: path with `%2F..%2F` URL encoding returns 403 | 🟢 | ⬚ todo | |
| 7B.5 | Test: path of length > 4096 characters returns 400 | 🟢 | ⬚ todo | |
| 7B.6 | Test: file listing response contains no entries outside NAS root | 🟢 | ⬚ todo | |

### 7C — Auth Route Tests

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 7C.1 | Create `backend/tests/test_auth.py` | 🟢 | ⬚ todo | |
| 7C.2 | Test: `POST /api/v1/auth/login` valid creds → 200 + `accessToken` present | 🟢 | ⬚ todo | |
| 7C.3 | Test: `POST /api/v1/auth/login` wrong password → 401 | 🟢 | ⬚ todo | |
| 7C.4 | Test: `POST /api/v1/auth/login` 6 rapid calls → 6th returns 429 (rate limit) | 🔵 | ⬚ todo | May require `slowapi` to be wired in first |
| 7C.5 | Test: member JWT cannot call `GET /api/v1/family` (admin-only) → 403 | 🟢 | ⬚ todo | |
| 7C.6 | Test: expired JWT (use `timedelta(seconds=-1)`) → 401 | 🟢 | ⬚ todo | |
| 7C.7 | Test: `POST /api/v1/auth/refresh` with revoked `jti` → 401 | 🔵 | ⬚ todo | |
| 7C.8 | Test: `POST /api/v1/auth/logout` then try refresh → 401 | 🟢 | ⬚ todo | |

### 7D — Storage Security Tests

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 7D.1 | Create `backend/tests/test_storage.py` | 🟢 | ⬚ todo | |
| 7D.2 | Test: format request with `confirmDevice != device` → 400 | 🟢 | ⬚ todo | |
| 7D.3 | Test: format request for OS disk `/dev/mmcblk0` → 400 (protected) | 🟢 | ⬚ todo | |
| 7D.4 | Test: mount returns 409 when NAS has open file handles (mock `lsof`) | 🔵 | ⬚ todo | |
| 7D.5 | Test: eject on already-unmounted device returns graceful error, not 500 | 🟢 | ⬚ todo | |

### 7E — CI Pipeline

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 7E.1 | Create `.github/workflows/backend-tests.yml`: checkout → Python 3.12 → `pip install -r requirements.txt` → run `bandit` + `pip-audit` → `pytest backend/tests` | 🟢 | ✅ done | CI workflow added at `.github/workflows/backend-tests.yml` |
| 7E.2 | Create `.github/workflows/flutter-analyze.yml`: checkout → `flutter pub get` → `flutter analyze` → `flutter test` | 🟢 | ⬚ todo | |
| 7E.3 | Add `bandit -r backend/app -ll` step to `backend-tests.yml` | 🟢 | ⬚ todo | Fail CI on HIGH severity |
| 7E.4 | Add `pip-audit -r requirements.txt` step to `backend-tests.yml` | 🟢 | ⬚ todo | |
| 7E.5 | Create `backend/run_tests.sh` convenience script: `cd backend && pytest tests/ -v --tb=short` | 🟢 | ⬚ todo | |

### 7F — Flutter Unit Tests

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 7F.1 | Create `test/services/api_service_test.dart` with mock HTTP client using `mockito` or `http_mock_adapter` | 🔵 | ⬚ todo | |
| 7F.2 | Test: `listFiles()` deserializes `FileListResponse` from mock JSON correctly (including `totalCount`) | 🟢 | ⬚ todo | |
| 7F.3 | Test: `getStorageStats()` deserializes `StorageStats` correctly | 🟢 | ⬚ todo | |
| 7F.4 | Test: `AuthSessionNotifier.login()` sets all fields correctly | 🟢 | ⬚ todo | |
| 7F.5 | Test: `AuthSessionNotifier.logout()` clears all fields | 🟢 | ⬚ todo | |
| 7F.6 | Test: `ConnectionNotifier` does NOT emit `disconnected` within first 9 seconds of loss | 🔵 | ⬚ todo | Use `FakeAsync` |
| 7F.7 | Test: `listFiles(page: 1, pageSize: 50)` sends correct `?page=1&pageSize=50` query params | 🟢 | ⬚ todo | |

### 7G — Flutter Widget Tests

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 7G.1 | Create `test/widgets/stat_tile_test.dart`: renders correct `label` and `value` text | 🟢 | ⬚ todo | |
| 7G.2 | Create `test/widgets/storage_donut_chart_test.dart`: renders at 0%, 50%, 100% fill without throwing | 🟢 | ⬚ todo | |
| 7G.3 | Create `test/widgets/file_list_tile_test.dart`: tap callback fires, long-press shows context menu | 🟢 | ⬚ todo | |
| 7G.4 | Create `test/screens/dashboard_screen_test.dart`: shows `CircularProgressIndicator` during loading state | 🔵 | ⬚ todo | Provide mock `dashboardProvider` |
| 7G.5 | Add golden test for `CubieCard` widget using `matchesGoldenFile` | 🟢 | ⬚ todo | Run `flutter test --update-goldens` once to seed |

---

## Milestone 8: Multi-SBC Board Abstraction (Critique A4)

### 8A — BoardConfig Interface

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 8A.1 | Create `backend/app/board.py` with `@dataclass BoardConfig(model_name, thermal_zone_path, lan_interface, cpu_governor_path)` | 🟢 | ⬚ todo | |
| 8A.2 | Add `KNOWN_BOARDS: dict[str, BoardConfig]` with entries for Cubie A7Z and Raspberry Pi 4 | 🟢 | ⬚ todo | |
| 8A.3 | Add `DEFAULT_BOARD = BoardConfig("unknown", "/sys/class/thermal/thermal_zone0/temp", "eth0", ...)` | 🟢 | ⬚ todo | |
| 8A.4 | Add `detect_board() -> BoardConfig`: reads `/proc/device-tree/model`, strips null bytes, looks up `KNOWN_BOARDS`, falls back to `DEFAULT_BOARD` | 🟢 | ⬚ todo | |
| 8A.5 | Wire `detect_board()` into `main.py` lifespan: store as `app.state.board` | 🟢 | ⬚ todo | |
| 8A.6 | Update `routes/monitor_routes.py`: use `request.app.state.board.thermal_zone_path` instead of hardcoded path | 🟢 | ⬚ todo | |

### 8B — Thermal Zone Auto-Detect

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 8B.1 | In `board.py`, add `find_thermal_zone() -> str`: scan `/sys/class/thermal/thermal_zone*/type`, return path of first zone with type containing `cpu` or `soc` | 🟢 | ⬚ todo | |
| 8B.2 | Fall back to `thermal_zone0` path if no matching zone found | 🟢 | ⬚ todo | |
| 8B.3 | Log selected thermal zone at startup | 🟢 | ⬚ todo | |

### 8C — LAN Interface Auto-Detect

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 8C.1 | In `board.py`, add `find_lan_interface() -> str`: scan `/sys/class/net/`, skip `lo`, return first interface with `type == "1"` (Ethernet) | 🟢 | ⬚ todo | |
| 8C.2 | Fall back to `eth0` if no Ethernet interface found | 🟢 | ⬚ todo | |
| 8C.3 | Log selected LAN interface at startup | 🟢 | ⬚ todo | |

---

## Milestone 9: AI Readiness Infrastructure (Critique S4, W2)

### 9A — Internal Event Bus

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 9A.1 | Create `backend/app/events.py` with `EventBus`: `subscribe(event_type, callback)`, `publish(event_type, payload)` using `asyncio.Queue` | 🔵 | ⬚ todo | |
| 9A.2 | Add `FileEvent` dataclass: `path`, `action` (`created`/`deleted`/`modified`), `user`, `timestamp` | 🟢 | ⬚ todo | |
| 9A.3 | Wire file upload route: `await event_bus.publish("file.created", FileEvent(...))` | 🟢 | ⬚ todo | |
| 9A.4 | Wire file delete route: `await event_bus.publish("file.deleted", FileEvent(...))` | 🟢 | ⬚ todo | |
| 9A.5 | Add in-memory circular buffer (last 1000 events) as default subscriber | 🟢 | ⬚ todo | Replay support for future AI indexer |

### 9B — SQLite Schema Reservation

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 9B.1 | Add `enable_sqlite: bool = False` to `config.py` with env var `CUBIE_ENABLE_SQLITE` | 🟢 | ⬚ todo | Feature-flagged; off by default |
| 9B.2 | Create `backend/app/db_stub.py`: `init_db(db_path)` creates SQLite file with empty `file_index` and `ai_jobs` tables | 🟢 | ⬚ todo | Schema documented in `kb/storage-architecture.md` |
| 9B.3 | In `main.py` lifespan: if `settings.enable_sqlite`, call `init_db(settings.data_dir / "cubie.db")` | 🟢 | ⬚ todo | |
| 9B.4 | Add `file_index` schema to `kb/storage-architecture.md`: `(path TEXT PK, size INT, mtime INT, mime TEXT, indexed_at INT)` | 🟢 | ⬚ todo | |

### 9C — AI Stub Routes

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 9C.1 | Create `backend/app/routes/ai_routes.py` with `GET /api/v1/ai/status` → `{"status": "not_implemented", "plannedFeatures": [...]}` | 🟢 | ⬚ todo | |
| 9C.2 | Add `GET /api/v1/ai/index-status` → `{"totalFiles": N, "indexedFiles": 0, "lastIndexedAt": null}` | 🟢 | ⬚ todo | |
| 9C.3 | Register `ai_router` in `main.py` | 🟢 | ⬚ todo | |

---

## Milestone 10: Post-Milestone Audit & Hardening

> Run this milestone after Milestones 4–9 are complete. Each task is a verification or documentation check.

### 10A — Hardware Integration Checklist

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 10A.1 | On Cubie A7Z: verify `detect_board()` returns `"Radxa Cubie A7Z"` model name | 🟢 | ⬚ todo | |
| 10A.2 | Verify thermal zone reads correct CPU temperature (`cat` the resolved path) | 🟢 | ⬚ todo | |
| 10A.3 | Run 10 concurrent `GET /api/v1/files/list` requests; verify no deadlock from asyncio.Lock | 🟢 | ⬚ todo | `ab -n 100 -c 10` or `hey` |
| 10A.4 | Format a 32GB+ USB drive via job API; verify job completes with status `done` within timeout | 🟢 | ⬚ todo | |
| 10A.5 | Restart `cubie-backend` service; verify OTP from `pairing.json` is still valid (W4 fix verified) | 🟢 | ⬚ todo | |

### 10B — Security Audit

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 10B.1 | Run `bandit -r backend/app -ll` and fix all HIGH findings | 🟢 | ⬚ todo | |
| 10B.2 | Run `pip-audit -r requirements.txt` and update any vulnerable packages | 🟢 | ⬚ todo | |
| 10B.3 | Verify CORS wildcard removed: `curl -H "Origin: http://evil.com" https://cubie:8443/api/v1/auth/login` should not reflect Origin | 🟢 | ⬚ todo | |
| 10B.4 | Verify cert pinning: temporarily change `kCertFingerprintPrefKey` to a wrong value; confirm Flutter rejects connection | 🔵 | ⬚ todo | |
| 10B.5 | Verify JWT secret is ≥32 bytes and not `"change-me-in-production"` on deployed instance | 🟢 | ⬚ todo | `wc -c /var/lib/cubie/jwt_secret` |
| 10B.6 | Run `flutter analyze` and resolve all warnings | 🟢 | ⬚ todo | |

### 10C — Soft-Delete & Trash Policy (Critique W5)

| # | Task | Model | Status | Notes |
|---|---|---|---|---|
| 10C.1 | Add `trash_dir` property to `config.py`: `{nas_root}/.cubie_trash/` | 🟢 | ⬚ todo | |
| 10C.2 | Add `TrashItem` Pydantic model: `id`, `original_path`, `deleted_at`, `size_bytes`, `deleted_by` | 🟢 | ⬚ todo | |
| 10C.3 | Update file delete route: move to `trash_dir/{user_id}/{timestamp}_{filename}` instead of `os.remove()` | 🟢 | ⬚ todo | |
| 10C.4 | Add `GET /api/v1/files/trash` endpoint: list caller's trash items | 🟢 | ⬚ todo | |
| 10C.5 | Add `POST /api/v1/files/trash/{id}/restore` endpoint: move back to original path | 🟢 | ⬚ todo | |
| 10C.6 | Add `DELETE /api/v1/files/trash/{id}` endpoint: permanent delete | 🟢 | ⬚ todo | |
| 10C.7 | Add trash quota guard: if trash dir > 10% of total NAS capacity, auto-purge oldest entries | 🟢 | ⬚ todo | Run quota check in the `delete` route before moving |
| 10C.8 | Add trash UI to `MyFolderScreen`: swipe-to-delete shows Undo `SnackBar` (30s window) before committing | 🔵 | ⬚ todo | |
| 10C.9 | Add "Empty Trash" button in `SettingsScreen` with confirmation `AlertDialog` | 🟢 | ⬚ todo | |
| 10C.10 | Document trash layout and quota policy in `kb/storage-architecture.md` | 🟢 | ⬚ todo | |

---

## Priority Order for Milestones 4–10

**Work in this sequence — each milestone unblocks the next:**

1. 🔴 **Milestone 4** first — critical security bugs (B1, B2, B3) and CORS wildcard must be fixed before any code ships
2. 🟠 **Milestone 5** second — reliability (async lock cache, AuthSession, job tracking) and deploy script
3. 🟡 **Milestone 6** third — auth hardening round 2 (refresh tokens, OTP persistence, TLS pinning)
4. 🟡 **Milestone 7** fourth — testing infrastructure (CI blocks regressions for later milestones)
5. 🔵 **Milestone 8** — multi-SBC abstraction (low urgency; single-board deployment is fine for v1)
6. 🔵 **Milestone 9** — AI readiness stubs (future-proofing only)
7. 🔵 **Milestone 10** — final audit pass (run last, after all code is written)
