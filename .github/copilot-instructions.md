# Copilot Instructions — AiHomeCloud

> Single source of truth for AI-assisted development.
> Last updated: 2026-03-13
> **If you change source code, update the relevant kb/ file before committing.**

---

## How to Orient Yourself

1. **Read `TASKS.md`** — current priorities, in-progress work, backlog
2. **Read `kb/changelog.md`** — recent decisions and session summaries
3. **Browse `kb/`** — deep architecture docs (see KB Index below)
4. **Validate before finishing:** `cd backend && python -m pytest tests/ -q` and `flutter analyze && flutter test`
5. **One task per session** — finish it, update docs, then stop

---

## Architecture Quick Reference

### Backend (Python / FastAPI)

| Layer | Path | Purpose |
|---|---|---|
| Entry point | `backend/app/main.py` | FastAPI app, CORS, 13 router registrations, lifespan hook |
| Config | `backend/app/config.py` | `Settings` via pydantic-settings, env prefix `AHC_` |
| Auth | `backend/app/auth.py` | JWT create/decode, bcrypt hash/verify via `run_in_executor`, `get_current_user` / `require_admin` dependencies |
| Persistence | `backend/app/store.py` | JSON-file storage with `asyncio.Lock`, TTL cache, atomic writes |
| Models | `backend/app/models.py` | Pydantic v2 models with `Field(alias="camelCase")` |
| Board detect | `backend/app/board.py` | Auto-detect SBC model (sun60iw2 / Rockchip / RPi4), thermal zone, LAN interface |
| Subprocess | `backend/app/subprocess_runner.py` | `run_command(cmd, timeout=30)` → `Tuple[int, str, str]` (rc, stdout, stderr) |
| TLS | `backend/app/tls.py` | Self-signed cert generation, fingerprint extraction |
| Job tracking | `backend/app/job_store.py` | Long-running op status (format jobs) |
| Logging | `backend/app/logging_config.py` | JSON structured logging, request_id middleware |
| Rate limiter | `backend/app/limiter.py` | SlowAPI rate limiting |
| Telegram bot | `backend/app/telegram_bot.py` | Telegram bot with auth linking, file receive, trash warnings |
| Document index | `backend/app/document_index.py` | FTS5 document search indexing |
| File sorter | `backend/app/file_sorter.py` | Auto file organization by type |
| WiFi manager | `backend/app/wifi_manager.py` | Auto-disable WiFi when Ethernet active |

**Route files (14+1 helper):**

| File | Prefix | Endpoints | Purpose |
|---|---|---|---|
| `auth_routes.py` | `/api/v1` | 14 | Pairing, user CRUD, login/logout, refresh, PIN, profile |
| `system_routes.py` | `/api/v1/system` | 6 | Info, firmware, OTA update, rename, shutdown, reboot |
| `monitor_routes.py` | `/ws` | 1 WS | Real-time system stats stream (`/ws/monitor`) |
| `file_routes.py` | `/api/v1/files` | 14 | List, mkdir, delete, trash CRUD, rename, upload, download, search, sort, roots |
| `family_routes.py` | `/api/v1/users/family` | 4 | List, add, remove, set role |
| `service_routes.py` | `/api/v1/services` | 2 | List services, toggle on/off |
| `storage_routes.py` | `/api/v1/storage` | 9 | Devices, scan, SMART, usage, format, mount, unmount, eject, stats |
| `storage_helpers.py` | (internal) | 0 | Helper functions for storage_routes |
| `network_routes.py` | `/api/v1/network` | 3 | Status, Wi-Fi get/set |
| `telegram_routes.py` | `/api/v1/telegram` | 6 | Config get/set, unlink, pending list/approve/deny |
| `telegram_upload_routes.py` | `/telegram-upload` | 2 | HTML upload form (GET), file upload (POST) — token auth |
| `jobs_routes.py` | `/api/v1/jobs` | 1 | Job status polling |
| `event_routes.py` | `/ws` | 1 WS | Real-time event stream (`/ws/events`) |

**Key config:** env prefix = `AHC_`, data dir = `/var/lib/aihomecloud`, NAS root = `/srv/nas`, port = `8443`.

### Frontend (Flutter / Dart)

| Layer | Path | Purpose |
|---|---|---|
| Entry point | `lib/main.dart` | App bootstrap, SharedPreferences init |
| Constants | `lib/core/constants.dart` | Ports, BLE UUIDs, pref keys, NAS paths, API version |
| Theme | `lib/core/theme.dart` | Dark theme — `AppColors`, `CubieRadii`, `AppTheme` |
| Error utils | `lib/core/error_utils.dart` | `friendlyError()` — converts exceptions to user-readable text |
| Models | `lib/models/` | Domain split: `models.dart` (barrel), `user_models.dart`, `device_models.dart`, `file_models.dart`, `storage_models.dart`, `service_models.dart`, `notification_models.dart` |
| API Service | `lib/services/api_service.dart` | HTTP + WS singleton, 10s timeout, TLS pinning, 6 part files |
| API extensions | `lib/services/api/` | `auth_api.dart`, `family_api.dart`, `files_api.dart`, `system_api.dart`, `storage_api.dart`, `services_network_api.dart` |
| Auth Session | `lib/services/auth_session.dart` | `AuthSession` + `AuthSessionNotifier` — immutable state, persistent refresh, emoji avatar |
| Discovery | `lib/services/discovery_service.dart` | mDNS → BLE fallback device discovery |
| Network scan | `lib/services/network_scanner.dart` | mDNS + subnet sweep for first-time setup |
| Providers | `lib/providers/` | Barrel `lib/providers.dart` re-exports: `core_providers.dart`, `device_providers.dart`, `file_providers.dart`, `data_providers.dart`, `discovery_providers.dart` |
| Router | `lib/navigation/app_router.dart` | GoRouter — 13+ routes, onboarding + main shell |
| Shell | `lib/navigation/main_shell.dart` | Bottom nav — **3 tabs: Home, Files, More** + disconnected banner |
| Localization | `lib/l10n/` | ARB-based, English |

**Screens (15):**

| Screen | File | Route | Tab |
|---|---|---|---|
| Splash | `screens/onboarding/splash_screen.dart` | `/` | — |
| Network Scan | `screens/onboarding/network_scan_screen.dart` | `/scan-network` | — |
| User Picker / PIN | `screens/onboarding/pin_entry_screen.dart` | `/user-picker` | — |
| Profile Creation | `screens/onboarding/profile_creation_screen.dart` | `/profile-creation` | — |
| Dashboard | `screens/main/dashboard_screen.dart` | `/dashboard` | Home |
| Files | `screens/main/files_screen.dart` | `/files` | Files |
| More | `screens/main/more_screen.dart` | `/more` | More |
| Family | `screens/main/family_screen.dart` | `/family` | — |
| Storage Explorer | `screens/main/storage_explorer_screen.dart` | `/storage-explorer` | — |
| Telegram Setup | `screens/main/telegram_setup_screen.dart` | `/telegram-setup` | — |
| File Preview | `screens/main/file_preview_screen.dart` | `/file-preview` | — |
| Folder View | `screens/main/folder_view_screen.dart` | `/folder-view` | — |
| Profile Edit | `screens/main/profile_edit_screen.dart` | `/profile-edit` | — |
| Device Settings | `screens/main/settings/device_settings_screen.dart` | `/settings/device` | — |
| Services Settings | `screens/main/settings/services_settings_screen.dart` | `/settings/services` | — |

**Widgets (8 files in `lib/widgets/`):**

| Widget class | File | Purpose |
|---|---|---|
| `AppCard` | `app_card.dart` | Standard card container |
| `StatTile` | `stat_tile.dart` | Dashboard metric tile |
| `FileListTile` | `file_list_tile.dart` | File/folder row in listings |
| `FolderView` | `folder_view.dart` | File browser with breadcrumbs, upload, sort |
| `StorageDonutChart` | `storage_donut_chart.dart` | Circular storage usage chart |
| `AhcNotificationOverlay` | `notification_listener.dart` | Toast-style notification overlay |
| `EmojiPickerGrid` | `emoji_picker_grid.dart` | 32-emoji avatar picker with custom input |
| `UserAvatar` | `user_avatar.dart` | Circular emoji/initial avatar with color cycling |

---

## Critical Invariants

These rules are non-negotiable. Every session must follow them.

- `run_command()` returns `(rc, stdout, stderr)` — always unpack all three
- `friendlyError(e)` is the only error surface shown to users — never `$e` or `e.toString()`
- `settings.nas_root` and `settings.data_dir` are the only path references — never hardcode
- `store.py` is the only JSON persistence layer — no direct file reads elsewhere
- All HTTP calls need `.timeout(ApiService._timeout)` — no raw client calls
- Never `shell=True` in subprocess — always use `run_command()`
- Never show `/dev/` paths, partition names, or filesystem types to users
- All file ops go through `_safe_resolve()` to sandbox under NAS root
- JWT `sub` claim = `user_id` — use `user.get("sub")` in all backend handlers
- **Dashboard System Tile is LOCKED (V1 design)** — do NOT modify `_SystemCompactCard`, `_SystemMetricIndicator`, or `_SystemMetricDivider` without explicit user confirmation. The current design uses small 44px circular progress rings with a chip icon and single labels (CPU, RAM, TEMP, UPTIME).

---

## Common Patterns

### Adding a new API endpoint
1. Add Pydantic model to `backend/app/models.py` (with `alias="camelCase"`)
2. Add route in `backend/app/routes/<domain>_routes.py`
3. Register router in `backend/app/main.py` if new file
4. Add method to the appropriate `lib/services/api/<domain>_api.dart` extension (with `.timeout(_timeout)`)
5. Add Dart model to `lib/models/<domain>_models.dart` if needed
6. Add Riverpod provider to `lib/providers/<domain>_providers.dart`
7. Wire into screen UI
8. Add backend test in `backend/tests/test_<domain>.py`
9. Update `kb/api-contracts.md` with the new endpoint

### Adding a new screen
1. Create `lib/screens/main/<name>_screen.dart`
2. Add GoRoute in `lib/navigation/app_router.dart`
3. If it's a tab, add to `ShellRoute` + bottom nav in `main_shell.dart`
4. Update `kb/architecture.md` screen inventory table

### Adding a new widget
1. Create `lib/widgets/<name>.dart`
2. Use `AppCard` as container if it's a card-style component
3. Use `AppColors` for all colours — no hex literals
4. Update `kb/architecture.md` widget inventory table

### Error handling in UI
1. In `.when(error: (e, _) => ...)` or `catch (e)` blocks, always use:
   ```dart
   Text(friendlyError(e))
   ```
2. For snackbars: `_showSnack('Action failed: ${friendlyError(e)}')`
3. **Never** show raw `$e` or `e.toString()` to the user

---

## Coding Conventions

### Dart / Flutter
- **State management:** Riverpod (`StateProvider`, `FutureProvider`, `StreamProvider`, `StateNotifierProvider`)
- **Routing:** GoRouter with `ShellRoute` for bottom nav
- **Fonts:** Google Fonts — Sora (headings), DM Sans (body)
- **Theme:** `AppColors` (colours), `CubieRadii` (border radii), `AppTheme` (ThemeData)
- **API calls:** All through `ApiService` singleton + part files in `lib/services/api/`, with `.timeout(_timeout)`
- **File naming:** `snake_case.dart` files, `PascalCase` classes
- **Widget pattern:** `ConsumerWidget` / `ConsumerStatefulWidget`
- **Error display:** Always `friendlyError(e)` from `lib/core/error_utils.dart`
- **Models:** Domain files in `lib/models/`, barrel re-exported from `models.dart`

### Python / FastAPI
- **Config:** pydantic-settings with `AHC_` env prefix
- **Auth:** JWT via python-jose, `get_current_user` / `require_admin` as `Depends()`
- **Models:** Pydantic v2 with `Field(alias="camelCase")` to match Flutter
- **Storage:** JSON files in `/var/lib/aihomecloud/` — no database
- **Path safety:** All file ops through `_safe_resolve()` sandboxing under NAS root
- **Subprocess:** Always `subprocess_runner.run_command()` — never `shell=True`
- **Concurrency:** `asyncio.Lock` (not `threading.Lock`) for shared state
- **Password hashing:** `loop.run_in_executor()` for bcrypt — never block the event loop

---

## File Structure Rules

### Naming conventions
- Dart: `snake_case.dart` files, `PascalCase` classes
- Python: `snake_case.py` files, `snake_case` functions, `PascalCase` classes
- Routes: `<domain>_routes.py` (e.g., `auth_routes.py`)
- Tests: `test_<domain>.py` (e.g., `test_auth.py`)
- Screens: `<name>_screen.dart` (e.g., `dashboard_screen.dart`)

### What goes where
- **Constants, enums, config** → `lib/core/`
- **Data classes / models** → `lib/models/` (split by domain)
- **API + networking** → `lib/services/` and `lib/services/api/`
- **State management** → `lib/providers/` (split by domain, barrel in `lib/providers.dart`)
- **Navigation** → `lib/navigation/`
- **Screens** → `lib/screens/main/` or `lib/screens/onboarding/`
- **Reusable widgets** → `lib/widgets/`
- **Backend routes** → `backend/app/routes/`
- **Backend tests** → `backend/tests/`
- **Architecture docs** → `kb/`

---

## Testing

### Backend
- **Framework:** pytest + httpx + pytest-asyncio
- **Config:** `backend/pytest.ini` — `asyncio_mode = "auto"`
- **Fixtures:** `backend/tests/conftest.py` — sandboxed `tmp_data_dir`, `admin_token`
- **Run:** `cd backend && python -m pytest tests/ -q`
- **CI:** GitHub Actions (`backend-tests.yml`) runs `pytest`, `bandit -ll`, `pip-audit`

### Flutter
- **Framework:** `flutter_test`
- **Run:** `flutter analyze && flutter test`
- **CI:** GitHub Actions (`flutter-analyze.yml`) runs `flutter analyze` + `flutter test`

### Before pushing any change
1. `cd backend && python -m pytest tests/ -q` — all pass
2. `flutter analyze` — 0 errors
3. `flutter test` — all pass

---

## KB Index

| File | Topic |
|---|---|
| `kb/architecture.md` | System map — screens, widgets, providers, routes, API structure |
| `kb/api-contracts.md` | **Authoritative API reference** — every endpoint, method, auth, request/response |
| `kb/engineering-blueprint.md` | Architecture prescriptions — concurrency, security, error handling |
| `kb/critique.md` | Self-audit — known bugs, hidden assumptions, scalability risks |
| `kb/devops-testing-strategy.md` | Test pyramid, CI/CD, observability |
| `kb/hardware.md` | Radxa Cubie A7Z specs, device paths, Linux commands |
| `kb/storage-architecture.md` | Mount points, safe unmount, auto-remount design |
| `kb/setup-instructions.md` | Cubie setup: SSH, deps, venv, systemd, QR pairing |
| `kb/features.md` | Feature inventory — implemented, planned, deferred |
| `kb/flutter-patterns.md` | Flutter widget, animation, error, navigation patterns |
| `kb/backend-patterns.md` | FastAPI route, store, subprocess, auth patterns |
| `kb/changelog.md` | Dated session summaries and key decisions |

---

## Keeping Documentation Current

These rules apply to every AI session working on this repo.
Treat documentation updates as part of the task — not optional.

| When you do this... | Also update this... |
|---|---|
| Add or change an API endpoint | `kb/api-contracts.md` — add/update the endpoint row |
| Add a new screen | `kb/architecture.md` — screen inventory table |
| Add a new widget | `kb/architecture.md` — widget inventory table |
| Add a new provider | `kb/architecture.md` — provider table |
| Add a new route to the router | `kb/architecture.md` — route table |
| Add a new backend route file | This file — backend route table |
| Change a class/file name | This file — update the table row immediately |
| Change coding conventions | This file — update the relevant section |
| Add a new kb/ file | This file — add it to the KB index |
| Complete a significant feature | `kb/changelog.md` — one-line dated entry |
| Change hardware or deployment | `kb/hardware.md` or `kb/setup-instructions.md` |

**Never leave a session with stale documentation.**
If you're short on tokens, update documentation before adding new features.
