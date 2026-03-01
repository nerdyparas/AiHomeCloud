# Copilot Instructions — CubieCloud

## Project Overview

CubieCloud is a **personal home NAS appliance** built on the **Radxa Cubie A7Z** (ARM, 8 GB RAM). It consists of:

- **Flutter app** (`lib/`) — Android mobile client (Dart, Riverpod, GoRouter)
- **FastAPI backend** (`backend/`) — Python server running on the Cubie hardware

The app pairs with the Cubie over the local network, authenticates via JWT, and provides file management, system monitoring, family user management, and NAS service control.

---

## Architecture Quick Reference

### Backend (Python / FastAPI)

| Layer | Path | Purpose |
|---|---|---|
| Entry point | `backend/app/main.py` | FastAPI app, CORS, router registration |
| Config | `backend/app/config.py` | `Settings` via pydantic-settings, env vars prefixed `CUBIE_` |
| Auth | `backend/app/auth.py` | JWT create/decode, `get_current_user` dependency |
| Persistence | `backend/app/store.py` | JSON-file-based storage (no database) |
| Models | `backend/app/models.py` | Pydantic models with camelCase aliases |
| Routes | `backend/app/routes/` | One file per domain (auth, system, monitor, files, family, services, storage) |

**Key config values:** NAS root = `/srv/nas`, data dir = `/var/lib/cubie`, port = `8443`.

### Frontend (Flutter / Dart)

| Layer | Path | Purpose |
|---|---|---|
| Entry point | `lib/main.dart` | App bootstrap, dev shortcut, SharedPreferences init |
| Constants | `lib/core/constants.dart` | Ports, BLE UUIDs, pref keys, NAS paths |
| Theme | `lib/core/theme.dart` | Dark theme colours and text styles |
| Models | `lib/models/models.dart` | Dart data classes mirroring backend models |
| API Service | `lib/services/api_service.dart` | HTTP + WebSocket client, singleton |
| Discovery | `lib/services/discovery_service.dart` | mDNS + BLE device discovery |
| Providers | `lib/providers.dart` | Riverpod providers (state, future, stream, notifiers) |
| Router | `lib/navigation/app_router.dart` | GoRouter with onboarding + main shell routes |
| Shell | `lib/navigation/main_shell.dart` | Bottom navigation (5 tabs) |
| Screens | `lib/screens/main/` | Dashboard, MyFolder, SharedFolder, Family, Settings |
| Screens | `lib/screens/onboarding/` | Splash, Welcome, QrScan, Discovery, SetupComplete |
| Widgets | `lib/widgets/` | Reusable UI components |

---

## Coding Conventions

### Dart / Flutter
- **State management:** Riverpod (StateProvider, FutureProvider, StreamProvider, StateNotifier)
- **Routing:** GoRouter with ShellRoute for bottom nav
- **Fonts:** Google Fonts — Sora (headings), DM Sans (body)
- **Theme:** Custom dark theme in `CubieColors` / `CubieTheme`
- **API calls:** All go through `ApiService` singleton with 10s timeout
- **File naming:** snake_case for files, PascalCase for classes
- **Widget pattern:** Prefer `ConsumerWidget` / `ConsumerStatefulWidget`

### Python / FastAPI
- **Config:** pydantic-settings with `CUBIE_` env prefix
- **Auth:** JWT via python-jose, `get_current_user` as FastAPI Depends
- **Models:** Pydantic v2 with `Field(alias="camelCase")` to match Flutter
- **Storage:** JSON files in `/var/lib/cubie/` — no database
- **Path safety:** All file ops go through `_safe_resolve()` to sandbox under NAS root

---

## Hardware Context

- **Board:** Radxa Cubie A7Z — ARM SoC, 8 GB RAM
- **OS storage:** microSD card (boot + OS)
- **NAS storage:** External — USB pen drive or NVMe SSD (user-provided)
- **Connectivity:** Ethernet + Wi-Fi, Bluetooth LE for pairing
- **Default IP in dev:** `192.168.0.212`

---

## How to Work on This Project

1. **Read `tasks.md`** first to understand current priorities and what's in progress
2. **Check `logs.md`** for recent decisions and context
3. **Check `kb/`** folder for detailed architecture docs on specific subsystems
4. **Always edit both backend AND frontend** when adding a new API endpoint
5. **Match model field names** — backend uses camelCase aliases, Flutter expects camelCase
6. **Test with real hardware** — the dev shortcut in `main.dart` auto-pairs with Cubie at `192.168.0.212`
7. **Keep changes focused** — one feature per set of edits, update tasks.md status after

---

## Common Patterns

### Adding a new API endpoint
1. Add Pydantic model to `backend/app/models.py`
2. Add route in `backend/app/routes/<domain>_routes.py`
3. Register router in `backend/app/main.py` if new file
4. Add method to `lib/services/api_service.dart` (with `.timeout(_timeout)`)
5. Add Dart model to `lib/models/models.dart` if needed
6. Add Riverpod provider to `lib/providers.dart`
7. Wire into screen UI

### Adding a new screen
1. Create `lib/screens/main/<name>_screen.dart`
2. Add GoRoute in `lib/navigation/app_router.dart`
3. If it's a tab, add to ShellRoute + bottom nav in `main_shell.dart`

---

## Important Warnings

- **Never** hardcode IPs or secrets in committed code (use env vars / config)
- **Always** sandbox file paths through `_safe_resolve()` on backend
- **Always** add `.timeout(_timeout)` to new HTTP calls in `api_service.dart`
- The backend runs as systemd service `cubie-backend` on the device
- The service file is at `backend/cubie-backend.service` — env vars configured there
