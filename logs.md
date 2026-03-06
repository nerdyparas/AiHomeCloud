# CubieCloud — Development Log

> Timestamped record of decisions, progress, and notable changes.
> Most recent entries at the top.

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
