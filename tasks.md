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
| 2A.1 | `GET /api/storage/devices` — list block devices via `lsblk` | ✅ done | Runs `lsblk -J -b`, flattens partitions, classifies USB/NVMe/SD, flags OS disks |
| 2A.2 | `GET /api/storage/scan` — re-scan for newly connected devices | ✅ done | `udevadm trigger` + `udevadm settle`, then re-list |
| 2A.3 | `POST /api/storage/format` — format device as ext4 | ✅ done | `confirmDevice` must match `device` for safety, runs `mkfs.ext4 -F -L` |
| 2A.4 | `POST /api/storage/mount` — mount device at `/srv/nas` | ✅ done | Creates personal/ + shared/ dirs, persists state, starts NAS services |
| 2A.5 | `POST /api/storage/unmount` — safe unmount | ✅ done | Stops services → sync → umount (lazy fallback), clears state |
| 2A.6 | `POST /api/storage/eject` — safe eject (USB) | ✅ done | Unmount + sysfs power-off or udisksctl fallback |
| 2A.7 | Update `GET /api/storage/stats` to report active device | ✅ done | `disk_usage()` follows mount points — auto-reports external device when mounted |
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
| 2D.1 | `GET /api/network/status` — WiFi connected/SSID, hotspot state, BT state, LAN IP/link | ✅ done | Parallel nmcli/ip/bluetoothctl queries |
| 2D.2 | `POST /api/network/wifi` — enable/disable WiFi radio | ✅ done | `nmcli radio wifi on/off` |
| 2D.3 | `POST /api/network/hotspot` — enable/disable WiFi hotspot | ✅ done | Create or activate hotspot profile via nmcli |
| 2D.4 | `POST /api/network/bluetooth` — enable/disable Bluetooth | ✅ done | `bluetoothctl power on/off` |
| 2D.5 | `GET /api/network/lan` — LAN interface status (link, IP, speed) | ✅ done | `ip addr` + `ethtool`, tries eth0/end0/enp1s0 |
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
| 3.3 | QR code generation on Cubie (pairing flow) | ✅ done | `GET /api/pair/qr` + real `MobileScanner` camera on Flutter |
| 3.4 | File preview (images, text, PDF) | ✅ done | `file_preview_screen.dart` — images via InteractiveViewer, text via SelectableText |
| 3.5 | File download from NAS to phone | ✅ done | `GET /api/files/download` + `downloadFile()` / `getDownloadUrl()` in ApiService |
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
