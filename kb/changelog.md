# Changelog

---

## 2026-03-15 — New hardware bring-up: Rock Pi 4A + full backend setup audit

**Hardware:** Radxa ROCK Pi 4A (RK3399, Armbian Ubuntu 24.04 Noble, kernel 6.18-rockchip64).

**Root cause of app-not-finding-backend:** Backend service was never installed (`aihomecloud` system
user and `/opt/aihomecloud` do not exist on a fresh git clone). The backend had been running as an
orphaned process but was not auto-starting. avahi-daemon was installed but the mDNS service definition
file was not deployed to `/etc/avahi/services/`, so mDNS discovery was broken. App was falling back
to slow subnet scan.

**Fixes applied:**

- **`backend/app/main.py`**: Fixed deprecated `asyncio.get_event_loop().run_until_complete()` → `asyncio.run()`
- **`backend/app/routes/storage_helpers.py`**: Added `"-n"` (non-interactive) to all 6 sudo calls
- **`backend/app/routes/storage_routes.py`**: Added `"-n"` to all 13 sudo calls
- **`backend/app/routes/system_routes.py`**: Added `"-n"` to all 3 sudo calls
- **`backend/app/routes/service_routes.py`**: Added `"-n"` to 1 sudo call
- **`backend/app/board.py`**: Added `"Radxa ROCK Pi 4A"` to `KNOWN_BOARDS` and `"rock pi 4"` to `_BOARD_SUBSTRINGS`
- **`backend/tests/test_path_safety.py`**: Fixed `evil_link` test to use `tmp_path/nas` instead of real `/srv/nas` — was leaving a path-traversal symlink artifact in production directory
- **`backend/tests/test_telegram_bot.py`**: Updated `test_handle_auth_links_new_user` to reflect updated `_handle_auth` approval flow (Task 9 changed `/auth` from direct-link to pending-approval)
- **`scripts/dev-setup.sh`**: Full rewrite — now 10-step idempotent script: packages, avahi, venv creation, dirs, credentials, system-level service, conflict resolution, sudoers, artifact cleanup, health check
- **`~/.config/systemd/user/aihomecloud.service`**: Created user-level service (now superseded by system-level)
- **`/etc/avahi/services/aihomecloud.service`**: Deployed mDNS advertisement
- **`/etc/sudoers.d/aihomecloud`**: Installed passwordless sudo rules for storage ops

**Key lesson — sudo -n invariant:** All `run_command(["sudo", ...])` calls MUST include `"-n"`.
Without it, the call blocks for 30 s on a TTY-less daemon process (or on pytest). With `-n`, failure
is immediate (rc=1) and logged. The backend already had sudoers rules for this hardware so all storage
calls succeed in production.

**Key lesson — avahi setup is not automatic:** avahi-daemon may be installed but the mDNS service XML
file must be explicitly deployed to `/etc/avahi/services/`. The Flutter app uses `_aihomecloud-nas._tcp`
for instant discovery. Without it, discover takes 30+ seconds (full subnet scan).

**mDNS status:** Verified working — `avahi-browse -t _aihomecloud-nas._tcp` returns `AiHomeCloud on rockpi-4a` on both IPv4 and IPv6.

**Test results:** 256 passed, 0 failed (excludes `test_hardware_integration.py`).

**Docs updated:** `kb/hardware.md` (Rock Pi 4A added, Cubie-only refs fixed), `kb/setup-instructions.md` (full rewrite for new hardware), `kb/changelog.md` (this entry), `TASKS.md` (done items added).

---

## 2026-03-15 — Task 3+4: Remove AdGuard feature and rename all Cubie branding to AiHomeCloud

**Task 3 — AdGuard/AdBlock removal:**
- Deleted `lib/widgets/adblock_stats_widget.dart`, `backend/app/routes/adguard_routes.py`, `backend/tests/test_adguard.py`, `FIX_ADBLOCKING.md`, `scripts/install-adguard.sh`
- Removed `_AdBlockingCard` from `more_screen.dart`, `adGuardStatsSilentProvider` from `data_providers.dart`, AdGuard widget from `dashboard_screen.dart`, all 4 AdGuard methods from `services_network_api.dart`, `adguard` entry from `service_routes.py`, adguard settings from `config.py`, adguard router from `main.py`

**Task 4 — Cubie branding renamed to AiHomeCloud:**
- Android package: `com.cubiecloud.cubie_cloud` → `com.aihomecloud.app`; `MainActivity.kt` moved to new path; deep-link scheme `cubie://` → `aihomecloud://`
- Flutter package name: `cubie_cloud` → `aihomecloud` (pubspec.yaml + all 13 import files)
- `CubieDevice` → `AhcDevice` (models, routes, providers, tests, backend models)
- `CubieNotificationOverlay` → `AhcNotificationOverlay`; `isCubie` → `isAhc` in `DiscoveredHost`
- Backend env prefix: `CUBIE_` → `AHC_` across all Python files
- Logger names: `cubie.*` → `aihomecloud.*` in 23 Python files
- Paths: `/var/lib/cubie` → `/var/lib/aihomecloud`, `/opt/cubie` → `/opt/aihomecloud`
- Trash folder: `.cubie_trash` → `.ahc_trash`; serial format: `CUBIE-{mac}` → `AHC-{mac}`
- mDNS type: `_cubie-nas._tcp` → `_aihomecloud-nas._tcp`; QR scheme: `cubie://pair` → `aihomecloud://pair`
- Renamed `cubie-backend.service` → `aihomecloud.service`, `50-cubie-network.rules` → `50-aihomecloud-network.rules`
- Updated `deploy.sh`, `scripts/first-boot-setup.sh`, `backend/README.md`

**Docs updated:** `copilot-instructions.md`, `kb/architecture.md`, `kb/api-contracts.md`, `kb/changelog.md` — AdGuard entries removed, `CubieDevice`/`CubieNotificationOverlay` renamed, env prefix and path references corrected.

**Verified:** `dart analyze` 0 errors; `pytest` 251 passed, 3 pre-existing Windows failures.

**Known exception:** `backend/app/board.py` retains `"Radxa CUBIE A7A"` / `"Radxa CUBIE A7Z"` / `"cubie a7z"` — these are manufacturer hardware model strings read from `/proc/device-tree/model` and must not be changed.

---

## 2026-03-13 — Telegram bot polish: HTML messages, inline keyboard, 4 new commands

**Changes:** Full rewrite of `backend/app/telegram_bot.py` for improved UX.

**Behaviour changes:**
- All bot messages now use `parse_mode="HTML"` with bold/italic/code formatting
- File upload destination prompt replaced with inline keyboard (4 buttons: My Folder, Family Shared, Entertainment, Cancel) — keyboard is removed after tap
- Typing indicator (`send_chat_action`) added to `/list` and search handlers
- File type emojis shown in upload messages (📄/🖼️/🎬/🎵/🎤)
- Single success edit (status message edited in-place, no duplicate reply)
- Brand fix: "CubieCloud" → "AiHomeCloud" in all messages

**New commands:**
- `/status` — device health (CPU, RAM, temp, uptime, storage bar)
- `/cancel` — discard a pending file upload
- `/whoami` — show linked profile, Telegram handle, and personal folder
- `/unlink` — remove this Telegram account from AiHomeCloud

**`_handle_auth`:** Shows current personal folder name; allows switching folder with `/auth <name>`
**`_handle_help`:** Lists all 7 commands with HTML formatting

**Tests updated:** `backend/tests/test_telegram_bot.py` — 36 tests, all passing. Updated `_make_context()` to include `AsyncMock` for `bot.send_chat_action` and `bot.send_message`; replaced deprecated `_handle_pending_upload_choice` references with `_process_upload_choice`.

---

## 2026-03-13 — Ad Blocking state-machine fix

**Changes:** Implemented AdGuard setup/runtime state probing and rewired the More-screen Ad Blocking card to handle installation, app-enabled, service-running, and active-stats states explicitly.

**Backend changes:** Added `GET /api/v1/adguard/status` in `adguard_routes.py` returning `{installed, service_running, app_enabled}` without requiring `adguard_enabled=true`. Added test file `backend/tests/test_adguard.py` (4 tests passing).

**Frontend changes:** Added `getAdGuardStatus()` to `lib/services/api/services_network_api.dart`. Reworked `_AdBlockingCardState` in `lib/screens/main/more_screen.dart` to two-step load (`/status` then `/stats`), setup-instructions dialog, visible snackbar errors, service-stopped retry state, and refresh action in active stats card.

**Documentation updated:** Updated endpoint counts and AdGuard route docs in `kb/api-contracts.md`, `kb/architecture.md`, and `.github/copilot-instructions.md`.

---

## 2026-03-12 — Dashboard premium UI refactor

**Features completed:** Refactored `dashboard_screen.dart` UI layout to premium card-based structure while preserving existing Riverpod providers, API calls, and dark theme palette. Added reusable `AdBlockStatsWidget` and moved ad-block statistics into the Network card.

**Key decisions:**
- Kept state/data architecture unchanged (`deviceInfoProvider`, `systemStatsStreamProvider`, `storageDevicesProvider`, `networkStatusProvider`, `adGuardStatsSilentProvider`)
- Replaced compact system text row with a 4-ring metrics card (CPU, RAM, TEMP, UPTIME) using lightweight `CustomPainter`
- Simplified top status card to overall health messaging only (no hardware metric line)
- Embedded AdGuard stats under upload/download rows for clearer network context

---

## 2025-07-25 — Repository audit and KB rebuild

**Changes:** `copilot-instructions.md` rewritten from scratch. All `kb/` files verified against source code and updated. Created `kb/architecture.md`, `kb/features.md`, `kb/flutter-patterns.md`, `kb/backend-patterns.md`, `kb/changelog.md`. Rebuilt `kb/api-contracts.md` from 78 lines to full 62-endpoint reference. Created `tasks.md`. Removed stale root-level prompt artifacts.

**Key decisions:**
- `kb/changelog.md` replaces `logs.md` as the permanent record
- `tasks.md` replaces the non-existent `TASKSv2.md` reference
- Hardware doc corrected from "A7A" to "A7Z"
- Hardcoded IP `192.168.0.212` removed from documentation

**Inaccuracies corrected:**
- api-contracts.md had only 15 of 62 endpoints documented
- hardware.md title said "A7A" but board is Radxa Cubie A7Z
- copilot-instructions.md referenced non-existent `TASKSv2.md`
- copilot-instructions.md listed wrong onboarding screen names
- copilot-instructions.md missing 4 route files (adguard, tailscale, telegram, telegram_upload)
- critique.md bugs B1 (threading.Lock) and B3 (bcrypt blocking) already fixed in code

---

## 2025-07-25 — Trash overhaul

**Features completed:** Moved Trash from More tab to Files tab. Added auto-delete toggle (30-day limit, off by default). Added Telegram weekly trash warning (Saturday 10AM, >10 GB threshold).

**Key decisions:**
- Trash lives in Files tab, not More
- Auto-delete is opt-in, not default
- Quota-overflow purge always runs regardless of auto-delete setting

**Backend changes:** `file_routes.py` added `GET/PUT /api/v1/files/trash/prefs`. `telegram_bot.py` added `_trash_warning_loop()`.

**Frontend changes:** `files_screen.dart` got Trash card + `_TrashScreen`. `more_screen.dart` lost Trash section.

---

## 2025-07-25 — v5 Sprint (Tasks 0–7 + DLNA/SMB merge)

**Features completed:**
- `GET /network/status` endpoint
- StatTile overflow fix (aspect ratio 1.45→1.25)
- Family folder size fix (ensure personal folders exist before computing)
- Upload speed boost (chunk 1→4 MB, write buffer 256 KB→2 MB)
- Family tab moved into More screen, bottom nav reduced to 3 tabs
- Files tabs replaced with 2-folder explorer (Personal + Shared)
- Netflix-style avatar user picker on PIN entry screen
- DLNA + SMB merged into unified "TV & Computer Sharing" toggle

**Key decisions:**
- 3-tab nav: Home, Files, More (Family moved into More)
- Merged `samba` + `dlna` service toggles into single `media` service
- PIN entry uses avatar circles, not dropdown
- Files screen uses 2 folder cards, not 3-segment tab bar

**Commits:** `2fd4d7d`, `9640204`, `af399cb`, `9f0c835`, `fe674ee`, `22109d3`, `e3e139d`, `141d727`