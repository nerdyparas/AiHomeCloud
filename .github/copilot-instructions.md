# Copilot Instructions — CubieCloud

> **This is the single source of truth for AI-assisted development.**
> GitHub Copilot loads this file automatically. Keep it accurate.
> Last updated: 2025-07-25

---

## Project Overview

CubieCloud is a **personal home NAS appliance** built on the **Radxa Cubie A7Z** (ARM, 8 GB RAM). It consists of:

- **Flutter app** (`lib/`) — Android mobile client (Dart, Riverpod, GoRouter)
- **FastAPI backend** (`backend/`) — Python server running on the Cubie hardware

The app pairs with the Cubie over the local network, authenticates via JWT, and provides file management, system monitoring, family user management, and NAS service control.

**Current status:** Milestones 1–8 complete. See `tasks.md` for open work.

---

## Quick Start — How to Work on This Project

1. **Read `tasks.md`** — current priorities and in-progress work
2. **Read `logs.md`** — recent decisions, context, timestamps
3. **Browse `kb/`** — deep-dive architecture docs (see index below)
4. **Always edit both backend AND frontend** when adding a new API endpoint
5. **Match model field names** — backend uses camelCase aliases, Flutter expects camelCase
6. **Run validation** before considering any change done:
   - Backend: `cd backend && python -m pytest tests/ -q`
   - Flutter: `flutter analyze && flutter test`
7. **Keep changes focused** — one feature per set of edits, update `tasks.md` after

---

## Architecture Quick Reference

### Backend (Python / FastAPI)

| Layer | Path | Purpose |
|---|---|---|
| Entry point | `backend/app/main.py` | FastAPI app, CORS, router registration, lifespan hook |
| Config | `backend/app/config.py` | `Settings` via pydantic-settings, env vars prefixed `CUBIE_` |
| Auth | `backend/app/auth.py` | JWT create/decode, bcrypt hash/verify (run_in_executor), `get_current_user` dependency |
| Persistence | `backend/app/store.py` | JSON-file-based storage with asyncio.Lock (no database) |
| Models | `backend/app/models.py` | Pydantic v2 models with `Field(alias="camelCase")` |
| Routes | `backend/app/routes/` | One file per domain: auth, system, monitor, files, family, services, storage, network, jobs, events |
| Board detect | `backend/app/board.py` | Auto-detect SBC model, thermal zone, LAN interface |
| Subprocess | `backend/app/subprocess_runner.py` | Centralized `run_command()` — no `shell=True`, input validation |
| TLS | `backend/app/tls.py` | Self-signed cert generation, fingerprint extraction |
| Job tracking | `backend/app/job_store.py` | Long-running op status (format jobs) |
| Logging | `backend/app/logging_config.py` | JSON structured logging, request_id middleware |

**Key config values:** NAS root = `/srv/nas`, data dir = `/var/lib/cubie`, port = `8443`.

### Frontend (Flutter / Dart)

| Layer | Path | Purpose |
|---|---|---|
| Entry point | `lib/main.dart` | App bootstrap, SharedPreferences init |
| Constants | `lib/core/constants.dart` | Ports, BLE UUIDs, pref keys, NAS paths, API version |
| Theme | `lib/core/theme.dart` | Dark theme — `CubieColors` / `CubieTheme` |
| Error utils | `lib/core/error_utils.dart` | `friendlyError()` — converts raw exceptions to user-readable text |
| Models | `lib/models/` | Split by domain: `models.dart`, `device_models.dart`, `file_models.dart`, `storage_models.dart`, `service_models.dart`, `user_models.dart`, `notification_models.dart` |
| API Service | `lib/services/api_service.dart` | HTTP + WebSocket client, singleton, 10s timeout |
| Auth Session | `lib/services/auth_session.dart` | `AuthSessionNotifier` — immutable state, persistent refresh token |
| Discovery | `lib/services/discovery_service.dart` | mDNS + BLE device discovery |
| Network scan | `lib/services/network_scanner.dart` | Local subnet IP scanner for first-time setup |
| Providers | `lib/providers.dart` | Riverpod providers (state, future, stream, notifiers) |
| Router | `lib/navigation/app_router.dart` | GoRouter with onboarding + main shell routes |
| Shell | `lib/navigation/main_shell.dart` | Bottom nav (5 tabs) + disconnected banner |
| Screens | `lib/screens/main/` | Dashboard, MyFolder, SharedFolder, Family, Settings, StorageExplorer, FilePreview, FolderView |
| Screens | `lib/screens/onboarding/` | Splash, Welcome, QrScan, Discovery, NetworkScan, SetupComplete |
| Widgets | `lib/widgets/` | Reusable: `CubieCard`, `StatTile`, `StorageDonutChart`, `FileListTile`, `FolderView`, `NotificationListener` |
| Localization | `lib/l10n/` | ARB-based, 145+ strings, English |

---

## Knowledge Base Index (`kb/`)

| File | Topic |
|---|---|
| `kb/api-contracts.md` | **Authoritative API reference** — every endpoint, method, auth, request/response schema |
| `kb/engineering-blueprint.md` | Architecture prescriptions — concurrency, security, error handling, observability |
| `kb/critique.md` | Self-audit of blueprint — known bugs, hidden assumptions, scalability risks |
| `kb/devops-testing-strategy.md` | Test pyramid, CI/CD pipeline design, test scaffold |
| `kb/hardware.md` | Radxa Cubie A7Z specs, device paths, Linux commands |
| `kb/storage-architecture.md` | Storage design — mount points, auto-remount, persistence |
| `kb/setup-instructions.md` | Step-by-step Cubie setup: SSH, deps, venv, systemd, QR pairing |

---

## Coding Conventions

### Dart / Flutter

- **State management:** Riverpod (`StateProvider`, `FutureProvider`, `StreamProvider`, `StateNotifier`)
- **Routing:** GoRouter with `ShellRoute` for bottom nav
- **Fonts:** Google Fonts — Sora (headings), DM Sans (body)
- **Theme:** Custom dark theme in `CubieColors` / `CubieTheme`
- **API calls:** All go through `ApiService` singleton with `.timeout(_timeout)`
- **File naming:** `snake_case` for files, `PascalCase` for classes
- **Widget pattern:** Prefer `ConsumerWidget` / `ConsumerStatefulWidget`
- **Error display:** Always pass errors through `friendlyError(e)` from `lib/core/error_utils.dart` — never show raw `$e` or `e.toString()` to the user
- **Models:** Split by domain in `lib/models/` — one file per domain, re-exported from `models.dart`

### Python / FastAPI

- **Config:** pydantic-settings with `CUBIE_` env prefix
- **Auth:** JWT via python-jose, `get_current_user` as `Depends()`
- **Models:** Pydantic v2 with `Field(alias="camelCase")` to match Flutter
- **Storage:** JSON files in `/var/lib/cubie/` — no database
- **Path safety:** All file ops go through `_safe_resolve()` to sandbox under NAS root
- **Subprocess:** Always use `subprocess_runner.run_command()` — never `shell=True`, never raw `subprocess.run()`
- **Concurrency:** Use `asyncio.Lock` (not `threading.Lock`) for shared state
- **Password hashing:** `loop.run_in_executor()` for bcrypt — never block the event loop

---

## Common Patterns

### Adding a new API endpoint
1. Add Pydantic model to `backend/app/models.py` (with `alias="camelCase"`)
2. Add route in `backend/app/routes/<domain>_routes.py`
3. Register router in `backend/app/main.py` if new file
4. Add method to `lib/services/api_service.dart` (with `.timeout(_timeout)`)
5. Add Dart model to `lib/models/<domain>_models.dart` if needed
6. Add Riverpod provider to `lib/providers.dart`
7. Wire into screen UI
8. Add backend test in `backend/tests/test_<domain>.py`

### Adding a new screen
1. Create `lib/screens/main/<name>_screen.dart`
2. Add GoRoute in `lib/navigation/app_router.dart`
3. If it's a tab, add to `ShellRoute` + bottom nav in `main_shell.dart`

### Error handling in UI
1. In `.when(error: (e, _) => ...)` or `catch (e)` blocks, always use:
   ```dart
   Text(friendlyError(e))
   ```
2. For snackbars: `_showSnack('Action failed: ${friendlyError(e)}')`
3. **Never** show raw `$e` or `e.toString()` to the user
4. If you encounter a new exception type, add it to `lib/core/error_utils.dart`

---

## File Structure Rules

### Splitting thresholds
- **Dart files:** Split when a file exceeds ~400 lines or contains 3+ unrelated concerns
- **Python files:** Split route files when they exceed ~300 lines
- **Models:** Keep domain models in separate files (`device_models.dart`, `file_models.dart`, etc.)

### Naming conventions
- Dart: `snake_case.dart` files, `PascalCase` classes
- Python: `snake_case.py` files, `snake_case` functions, `PascalCase` classes
- Routes: `<domain>_routes.py` (e.g., `auth_routes.py`, `storage_routes.py`)
- Tests: `test_<domain>.py` (e.g., `test_auth.py`, `test_storage.py`)
- Screens: `<name>_screen.dart` (e.g., `dashboard_screen.dart`)
- Widgets: descriptive name matching the widget class (e.g., `stat_tile.dart` → `StatTile`)

### What goes where
- **Constants, enums, config** → `lib/core/`
- **Data classes / models** → `lib/models/` (split by domain)
- **API + networking** → `lib/services/`
- **State management** → `lib/providers.dart`
- **Navigation** → `lib/navigation/`
- **Screen pages** → `lib/screens/main/` or `lib/screens/onboarding/`
- **Reusable UI components** → `lib/widgets/`
- **Backend routes** → `backend/app/routes/`
- **Backend tests** → `backend/tests/`
- **Architecture docs** → `kb/`

---

## Testing Requirements

### Backend
- **Framework:** pytest + httpx + pytest-asyncio
- **Config:** `backend/pytest.ini` — `asyncio_mode = "auto"`
- **Fixtures:** `backend/tests/conftest.py` — sandboxed `tmp_data_dir`, `admin_token`
- **Run:** `cd backend && python -m pytest tests/ -q`
- **CI:** GitHub Actions runs `pytest`, `bandit -ll`, `pip-audit`
- **Coverage areas:** Auth (login, refresh, roles), path safety (traversal, encoding), storage (OS disk protection, mount conflicts), config

### Flutter
- **Framework:** `flutter_test`
- **Run:** `flutter test`
- **CI:** GitHub Actions runs `flutter analyze` + `flutter test`
- **Coverage areas:** API deserialization, AuthSessionNotifier state, ConnectionNotifier debounce, widget rendering (StatTile, StorageDonutChart, FileListTile)

### Before pushing any change
1. `flutter analyze` — must show 0 errors, 0 warnings
2. `flutter test` — all tests must pass
3. `cd backend && python -m pytest tests/ -q` — all tests must pass

---

## Hardware Context

- **Board:** Radxa Cubie A7Z — ARM SoC (Rockchip), 8 GB RAM
- **OS storage:** microSD card (`/dev/mmcblk0`) — boot + OS
- **NAS storage:** External USB/NVMe (`/dev/sda` typical) — user-provided, mounted at `/srv/nas`
- **Connectivity:** Ethernet + Wi-Fi, Bluetooth LE for initial pairing
- **Thermal:** Auto-detected from `/sys/class/thermal/`
- **LAN interface:** Auto-detected from `/sys/class/net/`
- **Default IP in dev:** `192.168.0.212`
- **Board detection:** Reads `/proc/device-tree/model`, falls back to safe defaults

---

## Security Invariants

- **Never** hardcode IPs, secrets, or credentials in committed code — use env vars / config
- **Always** sandbox file paths through `_safe_resolve()` on backend
- **Always** add `.timeout(_timeout)` to new HTTP calls in `api_service.dart`
- **Never** use `shell=True` in subprocess calls — use `subprocess_runner.run_command()`
- **Never** show raw exception text to users — use `friendlyError()`
- **Always** use `get_current_user` dependency for protected endpoints
- **JWT secret** auto-generated and persisted to `/var/lib/cubie/jwt_secret`
- **TLS:** Self-signed cert with trust-on-first-use (TOFU) pinning
- **CORS:** Configurable via `CUBIE_CORS_ORIGINS` env var
- **systemd hardening:** `PrivateTmp`, `NoNewPrivileges`, `ProtectSystem`, `ProtectHome`, `RestrictAddressFamilies`, `SystemCallFilter`

---

## Deployment

- Backend runs as systemd service `cubie-backend` on the Cubie
- Service file: `backend/cubie-backend.service` (env vars configured there)
- Deploy script: `deploy.sh` — pushes to device, restarts service
- Health check: HTTPS with cert pinning via `--cacert`
- Auto-remount external storage on boot from `storage.json`

---

## Documentation Maintenance

When making significant changes to the codebase:

1. **Update `tasks.md`** — mark completed tasks, add new ones
2. **Append to `logs.md`** — date-stamped entry with what changed and why
3. **Update `kb/api-contracts.md`** — if API endpoints/models change
4. **Update this file** — if architecture, file structure, or conventions change
5. **Keep `kb/` docs accurate** — if subsystem design changes

### This file (`copilot-instructions.md`)
- Must reflect the actual file tree and conventions
- Update the Architecture Quick Reference table when files are added/renamed
- Update Common Patterns when new patterns are established
- Update KB Index when new `kb/` docs are created
