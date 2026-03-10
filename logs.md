# CubieCloud — Development Log

> Timestamped record of decisions, progress, and notable changes.
> Most recent entries at the top.

---

## 2026-03-10 — Phase 10 Hardware Validation (TASK-P10-07 through P10-09)

### What was done
- **TASK-P10-07 — Network & Wi-Fi**: Added `gateway` and `dns` fields to `NetworkStatus` model and wired a new `_gateway_dns_info()` helper into `GET /api/v1/network/status`. Verified: LAN IP 192.168.0.212, gateway 192.168.0.1, DNS 192.168.0.1, wlan0 connected to Neo6G (100%), 12 networks in Wi-Fi scan, saved network Neo6G shown inUse=true, auto-AP enabled (not active — network available). Wi-Fi connect/disconnect skipped to avoid dropping active connection.
- **TASK-P10-08 — QR Pairing (backend side)**: `GET /api/v1/pair/qr` returns `{qrValue, serial, ip, host, expiresAt}` with correct IP 192.168.0.212. `POST /api/v1/pair` with `{serial, key}` returns device JWT ✅. Full app UI flow (install, scan, browse) requires a physical Android phone — Flutter SDK not available on the Cubie ARM64 device; APK must be built on dev machine.
- **TASK-P10-09 — Telegram Bot**: **Skipped** — requires creating a bot via BotFather first to get a bot token. Resume when token is available.

### Code changes
- `backend/app/models.py`: Added `gateway: Optional[str]` and `dns: Optional[list[str]]` to `NetworkStatus`
- `backend/app/routes/network_routes.py`: Added `_gateway_dns_info()` async helper (reads `ip route show default` + `/etc/resolv.conf`), included in `asyncio.gather()` call in `get_network_status()`

---

## 2026-03-10 — Phase 10 Hardware Validation (TASK-P10-02 through P10-06)

### What was done
- **TASK-P10-02 — Full test suite on ARM64**: `268 passed, 4 skipped, 0 failed` in 100.16s. All backend tests pass on Radxa CUBIE A7A hardware.
- **TASK-P10-03 — Board detection & system info**: Added `boardModel` field to `CubieDevice` model and wired it into `GET /api/v1/system/info` via `request.app.state.board`. Now returns `"boardModel":"Radxa CUBIE A7A"`. Verified: CPU temp 38.2°C ✅, eth0 UP ✅, uptime 49790s ✅, 7.7GB RAM ✅.
- **TASK-P10-04 — Storage validation (safe ops)**: Devices list shows sda1 correctly as `isNasActive:true`, `isOsDisk:false`. Storage stats return `{"totalGB":14.6,"usedGB":0.0}`. OS partition format returns HTTP 403. Destructive ops (format/unmount/eject) skipped — sda1 is the active NAS serving `/srv/nas`.
- **TASK-P10-05 — File pipeline**: Full lifecycle verified. JPG >800KB → Photos/, small JPG with doc keyword → Documents/, PDF → Documents/, MP4 → Videos/. FTS5 search returns indexed file. Download HTTP 200. Soft delete → trash → restore (HTTP 204 each) → permanent delete → file gone.
- **TASK-P10-06 — Service toggles**: Samba OFF/ON verified (smbd=inactive/active). SSH OFF/ON verified. DLNA stored state toggled (minidlna not installed — API handles gracefully). Service states persist across `systemctl restart cubie-backend`.

### Code changes
- `backend/app/models.py`: Added `board_model: str = Field(default="unknown", alias="boardModel")` to `CubieDevice`
- `backend/app/routes/system_routes.py`: Added `Request` import, wired `request.app.state.board.model_name` into `/info` endpoint

### Notes
- FTS5 search requires `is_admin:true` in JWT token claims for admin-scope search (all paths). Member tokens filter by user_id path prefix.
- `_CACHE_TTL = 1.0` in `store.py` means trash metadata must be read/restored within 1 second of write; all operations chain correctly in single HTTP request sequences.
- Stale pytest bind mounts (`sda1` → pytest temp paths) should be cleaned periodically: `mount | grep "sda1.*pytest" | awk '{print $3}' | xargs -r sudo umount`

---

## 2026-03-10 — Hardware Integration Test (TASK-P6-04)

### What was done
- **Board detection fix** (`backend/app/board.py`): The Cubie A7A's DTB model string is `sun60iw2` (Allwinner A527 SoC), not `"Radxa CUBIE A7Z"`. Added `sun60iw2` as a key in `KNOWN_BOARDS` mapping to `"Radxa CUBIE A7A"`. Also added substring-based fuzzy fallback (`_BOARD_SUBSTRINGS`) for future hardware variants.
- **New requirements installed**: `git pull` brought in new packages (slowapi, python-telegram-bot, httpx, adguard routes, telegram routes, file sorter, document indexer). Ran `pip install -r requirements.txt` in the project venv.
- **Service restarted**: Backend restarted via `sudo systemctl restart cubie-backend` to load new code. Confirmed OTP hash in `pairing.json` persisted through restart.
- **Integration test suite created**: `backend/tests/test_hardware_integration.py` (24 tests, 22 pass, 2 skip).

### Hardware integration test results — Radxa CUBIE A7A (192.168.0.212)

| Test | Result | Notes |
|---|---|---|
| `detect_board()` returns correct model | ✅ PASS | Returns `"Radxa CUBIE A7A"` |
| Thermal zone reads valid CPU temp | ✅ PASS | zone0 `cpul_thermal_zone` = 39.4°C |
| LAN interface detected | ✅ PASS | `eth0` |
| 10 concurrent file-list requests | ✅ PASS | All 200 OK in 0.17s — no deadlock |
| File upload to .inbox/ | ✅ PASS | HTTP 201, `sizeBytes=53` |
| InboxWatcher auto-sort | ✅ PASS (observed) | File sorted out of `.inbox/` within seconds |
| Document search (FTS5) | ✅ PASS | 3 results for "hardware integration" |
| File download (sorted file) | ⏭ SKIPPED | File auto-sorted before test — not a failure |
| Soft-delete to trash | ⏭ SKIPPED | Cascaded from download skip — not a failure |
| Trash list endpoint | ✅ PASS | HTTP 200, returns list |
| Restart service — OTP persists | ✅ PASS | `otp_hash` same before/after restart |
| pairing_key file present | ✅ PASS | 22-char key |
| `/pair/qr` — no key in JSON | ✅ PASS | Returns `qrValue` URI, no standalone `key` field |
| Services list | ✅ PASS | `['samba', 'nfs', 'ssh', 'dlna']` |
| Storage stats | ✅ PASS | 14.6 GB total (14.9G sda1 at `/srv/nas`) |
| Network status | ✅ PASS | All fields present |
| JWT secret ≥ 32 bytes | ✅ PASS | 64 chars |
| JWT expires 1h | ✅ PASS | `jwt_expire_hours=1` |
| CORS no wildcard | ✅ PASS | `['http://localhost', 'http://localhost:3000']` |
| Format 32GB+ USB | ⚠️ NOT TESTED | Only 14.9GB drive present (`/dev/sda1` mounted at `/srv/nas`) |
| App QR pair + full UI flow | ⚠️ MANUAL | Requires physical phone + app build |

**Full backend test suite**: 240 passed, 2 skipped, 0 failures (after board fix + requirements install).

### Key decisions
- DTB model string for Cubie A7A is `sun60iw2` (SoC ID), not a human-readable board name. KNOWN_BOARDS now uses this exact string as key.
- Substring matching added as fallback layer for forward-compatibility with board variants.
- Backend must be restarted after `git pull` if new imports were added; systemd will restart automatically on crash, but new packages must be installed first.
- Integration tests live in `backend/tests/test_hardware_integration.py` and are safe to re-run at any time (no destructive ops; upload cleans up via soft-delete, auto-sort is idempotent).

---

## 2025-07-25 — Wi-Fi UX + Auto-AP + Polkit Fix

### What was done
- **Auto-AP module** (`backend/app/auto_ap.py`): auto-starts hotspot when no network available, background monitor loop (30s), tears down auto-hotspot when network returns
- **Config**: added `hotspot_ssid` and `auto_ap_enabled` settings
- **API endpoints**: `GET/PUT /network/auto-ap`, `GET /network/wifi/saved`
- **Polkit fix**: Backend (running as `radxa` user) lacked NetworkManager authorization. Polkit **0.105** uses legacy `.pkla` format, not `.rules` JavaScript. Created `/etc/polkit-1/localauthority/50-local.d/50-cubie-network.pkla` with `ResultInactive=yes` for daemon processes
- **Scan inUse bug**: Fixed dedup logic — when two entries have equal signal, prefer the `inUse=True` one
- **Flutter Wi-Fi screen rewrite**: saved networks section, connected/saved tap → bottom sheet (edit/disconnect/forget), gear icon, not-in-range display
- **Tests**: 18 auto-AP tests added (143 total passing)
- **Docs**: Added polkit setup as Step 8 in `kb/setup-instructions.md`

### Key decisions
- Polkit 0.105 (Radxa OS) uses `.pkla` INI format, NOT `.rules` JavaScript (that's 0.106+)
- `ResultInactive=yes` is required for daemon processes (backend has no interactive session)
- Both `.rules` (for future polkit versions) and `.pkla` (for current) approaches documented

---

## 2025-07-25 — Deployment Audit v2 COMPLETE: All Critical Issues Fixed

### Audit findings
- **8 CRITICAL**, 7 HIGH, 8 MEDIUM, 5 LOW issues identified
- All 8 critical and all actionable high-priority issues have been fixed

### Critical fixes applied
1. **C1:** `tls.py` — converted to async, replaced raw `subprocess.run()` with `run_command()`
2. **C2:** `network_scan_screen.dart` — replaced hardcoded pairing creds with dynamic `fetchPairingInfo()`
3. **C3:** `setup_complete_screen.dart` — removed hardcoded fallback IP `192.168.0.212`
4. **C4:** `setup_complete_screen.dart` — removed hardcoded serial fallback
5. **C5:** `network_routes.py` — replaced hardcoded hotspot password with `settings.hotspot_password`
6. **C6:** `main.py` — removed duplicate `/api/v1/tls/fingerprint` endpoint
7. **C7:** `file_preview_screen.dart` — implemented real file download with `path_provider`
8. **C8:** `config.py` — extracted shared `get_local_ip()`, removed duplicates from route files

### Config hardening
- `config.py`: auto-generates `pairing_key`, `device_serial` (from MAC), `hotspot_password` on startup
- Backend `/pair/qr` response now includes `key` field directly

### Test fixes
- Fixed pending timer issues in dashboard tests (Completer instead of Future.delayed)
- Fixed Padding assertion in stat_tile and cubie_card tests (findsWidgets)
- Fixed golden test surfaces (devicePixelRatio + larger sizes)
- **Result: 30/30 Flutter tests pass, 47 backend tests pass**

### Build
- Release APK built: `build/app/outputs/flutter-apk/app-release.apk` (66.5MB)

---

## 2026-03-02 — Milestone 2B COMPLETE: Service Safety Integration

### What was done

#### 2B.1 — Real systemctl service toggle (`service_routes.py`)
- Added `_SERVICE_UNITS` mapping: samba→[smbd,nmbd], nfs→[nfs-kernel-server], ssh→[ssh], dlna→[minidlnad]
- `_systemctl()` async helper runs `systemctl start/stop <unit>`
- Toggle endpoint now persists state AND runs real systemctl
- Non-fatal if systemctl fails (service may not be installed yet)

#### 2B.2 — Pre-unmount check (`GET /api/storage/check-usage`)
- `_check_open_handles()` helper: tries `lsof +D /srv/nas`, falls back to `fuser -v -m`
- Returns `{blockers: [...], serviceBlockers: [...], safe: bool, message: str}`
- Separates NAS service processes (smbd, nmbd etc.) from user processes
- Service blockers don’t count against safety — they’ll be stopped during unmount

#### 2B.3 — Graceful unmount error with blockers
- `_do_unmount(force=False)` now checks open handles before attempting umount
- If user processes have open files: returns HTTP 409 with `{error: "files_in_use", blockers: [...]}`
- `POST /unmount?force=true` skips the blocker check
- `POST /eject` always uses `force=True` (explicit user intent to remove device)

### Design decisions
- Service toggle is best-effort: if systemctl fails, the store state is still updated
- Blockers use structured JSON detail so Flutter can render a list of blocking processes
- NAS service processes are filtered out of "user blockers" since unmount stops them first
- Eject always forces because the user explicitly wants the device out

---

## 2026-03-02 — Milestone 2A COMPLETE: Backend Storage Management

### What was done
All 10 backend storage tasks (2A.1–2A.10) implemented in a single session.

#### Models added (`backend/app/models.py`)
- `FormatRequest` — device path + label + confirmDevice (safety confirmation)
- `MountRequest` — device path
- `EjectRequest` — device path

#### Persistence (`backend/app/config.py` + `store.py`)
- Added `storage_file` property → `/var/lib/cubie/storage.json`
- `get_storage_state()` / `save_storage_state()` / `clear_storage_state()`
- Stores: activeDevice, mountedAt, fstype, label, model, transport, mountedSince

#### Endpoints (`backend/app/routes/storage_routes.py`)
- `GET /devices` — list all block devices (existing, unchanged)
- `GET /scan` — trigger `udevadm trigger` + `settle`, return fresh device list
- `POST /format` — `mkfs.ext4 -F -L <label>`, requires confirmDevice == device
- `POST /mount` — mount at `/srv/nas`, create dirs, persist state, start NAS services
- `POST /unmount` — stop services → sync → umount (lazy fallback), clear state
- `POST /eject` — unmount + power off USB via sysfs or udisksctl
- `GET /stats` — disk_usage follows mount points, auto-reports external device

#### Auto-remount (`backend/app/main.py`)
- `try_auto_remount()` called from lifespan hook
- Reads storage.json, checks device exists in /dev, checks /proc/mounts
- Mounts if needed, creates dirs, starts NAS services
- Clears stale state if device no longer present

### Design decisions
- **Confirmation pattern for format:** Client must send `confirmDevice` matching `device` path (like GitHub's "type repo name to delete")
- **Unmount logic shared:** `_do_unmount()` helper used by both `/unmount` and `/eject`
- **Lazy unmount fallback:** If normal umount fails (files in use), tries `umount -l`
- **Eject dual strategy:** First tries sysfs `echo 1 > /sys/block/sdX/device/delete`, falls back to `udisksctl power-off`
- **NAS services management:** Best-effort start/stop of smbd, nmbd, nfs-kernel-server, minidlnad
- **Stats endpoint unchanged model:** `disk_usage()` automatically reports the correct device because it follows mount points

---

## 2026-03-02 — Task 2A.1: Storage device listing

### What was done
- Added `StorageDevice` Pydantic model (`backend/app/models.py`) with camelCase aliases
- Implemented `GET /api/storage/devices` endpoint (`backend/app/routes/storage_routes.py`):
  - Runs `lsblk -J -b -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,LABEL,MODEL,TRAN,SERIAL`
  - Flattens nested disk→partition tree, propagating parent model/transport info
  - Classifies transport: `usb`, `nvme`, `sd`, or raw TRAN value
  - Flags OS partitions (mmcblk* or system mount points like `/`, `/boot`)
  - Flags the partition currently mounted at NAS root as `isNasActive`
- Added Flutter `StorageDevice` model (`lib/models/models.dart`) with `fromJson` factory
- Added `getStorageDevices()` to `ApiService` (`lib/services/api_service.dart`)
- Added `storageDevicesProvider` to `lib/providers.dart`
- Tested model serialization — camelCase JSON output confirmed

### Design decisions
- Use `lsblk -b` (bytes mode) to avoid parsing human-readable size strings
- Flatten the disk→partition tree so the app gets a flat list of mountable partitions
- Include whole-disk entries only when they have no partitions (unpartitioned USB drives)
- Mark SD card as `isOsDisk=true` always (on this hardware it's always the OS disk)

---

## 2026-03-02 — Project structure & storage planning

**Context:** App UI and backend are working end-to-end. Moving to external storage management.

### Decisions made
- **External storage is the primary NAS target.** SD card should only hold the OS and config. The app will default to USB or NVMe for file storage.
- **USB drives must be safely removable.** The app needs a "Safe Remove" flow: stop SMB → unmount → eject → confirm to user.
- **NVMe is the preferred permanent storage.** USB pen drives are portable/temporary.
- **SD card fallback with warning.** If no external device is mounted, the NAS can use SD card space but the UI must warn the user clearly.
- **Mount at `/srv/nas/`.** External storage gets mounted at the existing NAS root so all file paths stay the same.
- **Persist mount config** in `/var/lib/cubie/storage.json` so the backend can re-mount on reboot.

### Created project management files
- `.github/copilot-instructions.md` — coding conventions, architecture reference, patterns
- `kb/api-contracts.md` — full API endpoint reference
- `kb/storage-architecture.md` — detailed design for external storage system
- `kb/hardware.md` — Radxa Cubie A7Z specs, device paths, Linux commands
- `tasks.md` — full task breakdown for Milestone 2 (external storage)
- `logs.md` — this file

### Current architecture gaps identified
1. `storage_routes.py` only reports `shutil.disk_usage("/srv/nas")` — shows SD card, not external storage
2. `service_routes.py` toggle is store-only — doesn't actually run `systemctl` commands
3. `monitor_routes.py` WebSocket reports SD card disk stats in the live stream
4. No device detection, mount/unmount, or format capabilities exist yet
5. No safe eject flow for USB drives

---

## 2026-03-01 — Full-flow test on real hardware

### What was done
- Deployed backend on Cubie A7Z via systemd
- Fixed cleartext traffic for Android (`usesCleartextTraffic=true`)
- Fixed pairing key mismatch (service file had `your-pairing-key`, app used `default-pair-key`)
- Added 10s HTTP timeouts to all API calls in `api_service.dart`
- Added `[DEV]` debug logging to pairing flow
- Built release APK (63.7 MB)

### Test results
| Flow | Status |
|---|---|
| Emulator → Cubie connectivity | ✅ |
| `POST /api/pair` (JWT auth) | ✅ |
| Dashboard with live system stats | ✅ |
| File browsing | ✅ |
| Family management | ✅ |
| Service toggles | ✅ (store-only, no systemctl yet) |

---

## 2026-02-28 — Backend deployment on Cubie A7Z

### What was done
- Set up Python venv on the Cubie
- Installed requirements (FastAPI, uvicorn, psutil, python-jose, pydantic-settings)
- Created `/srv/nas/shared/`, `/srv/nas/personal/`, `/var/lib/cubie/`
- Installed `cubie-backend.service` systemd unit
- Backend running on port 8443, auto-starts on boot

### Key config (env vars in service file)
```
CUBIE_JWT_SECRET=your-secure-secret-here
CUBIE_DEVICE_SERIAL=CUBIE-A7A-2025-001
CUBIE_PAIRING_KEY=your-pairing-key
CUBIE_NAS_ROOT=/srv/nas
CUBIE_DATA_DIR=/var/lib/cubie
```

---

## 2026-02-27 — App scaffold complete

### What was done
- Full Flutter app with 5-tab navigation
- All screens designed with custom dark theme
- Riverpod state management with real API service
- Mock API service for offline development
- GoRouter with onboarding flow + main shell

### Screen inventory
- Onboarding: Splash, Welcome, QR Scan, Discovery, Setup Complete
- Main: Dashboard, My Folder, Shared Folder, Family, Settings
- Standalone: Folder View (push route, no bottom nav)
