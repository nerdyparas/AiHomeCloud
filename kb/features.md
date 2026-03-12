# Feature Inventory — AiHomeCloud

> Last updated: 2025-07-25

---

## Implemented Features

### Authentication & Users
- **QR pairing** — Scan QR code from Cubie to pair app (OTP + serial + key)
- **TLS TOFU** — Trust-on-first-use certificate fingerprint pinning
- **JWT auth** — Access + refresh token flow with persistent refresh
- **Multi-user** — Multiple family members, first user is admin
- **Netflix-style user picker** — Avatar circles on PIN entry screen
- **Optional PIN** — Users can set/change/remove PIN
- **Emoji avatars** — 32-emoji picker + custom emoji input
- **Profile edit** — Change name and emoji avatar

### File Management
- **File browser** — Paginated listing with sort (name, size, date, direction)
- **Two-folder explorer** — Personal + Shared folders as entry points
- **Upload** — Chunked upload (4 MB chunks, 2 MB write buffer) with progress tracking
- **Download** — Stream file download
- **Create folder** — mkdir with path safety
- **Rename** — File and folder rename
- **Delete → Trash** — Soft-delete to `.cubie_trash/` per-user
- **Trash management** — View, restore, permanent delete, empty all
- **Auto-delete toggle** — 30-day auto-purge (user-controlled, off by default)
- **File preview** — Image/text file preview screen
- **FTS5 search** — Full-text document search via SQLite FTS5
- **Auto-sort** — Sort files into subfolders by type (Documents, Images, etc.)
- **Storage roots** — List available mount points with device info

### System Monitoring
- **Dashboard** — Real-time CPU, RAM, temperature, uptime, network speed
- **Storage chart** — Donut chart showing total/used/free space
- **WebSocket monitor** — `/ws/monitor` streams stats every ~2s
- **Notification stream** — `/ws/events` pushes real-time events (storage, service changes)
- **Toast notifications** — Overlay toast for incoming events

### Storage Management
- **Device listing** — Show connected USB/NVMe devices (friendly names, no `/dev/` paths)
- **Smart activate** — Auto-detect: mount if formatted, format if not
- **Format** — ext4 format with long-running job tracking
- **Mount/Unmount** — Safe mount with service coordination
- **Eject** — Safe unmount + USB power off
- **Usage check** — Pre-unmount blocker detection (open files, services)

### Network & Services
- **Network status** — Wi-Fi, LAN, hotspot, Bluetooth status view
- **Wi-Fi toggle** — Enable/disable Wi-Fi
- **Service management** — Toggle SSH, NFS, media (DLNA + Samba)
- **Unified media service** — Single "TV & Computer Sharing" toggle for smbd + nmbd + minidlna
- **AdGuard stats** — DNS queries, blocked count, protection status
- **AdGuard pause** — Temporary pause (5/30/60 min)
- **Tailscale VPN** — Status view and bring-up

### Telegram Integration
- **Bot setup** — Token configuration screen
- **Auth linking** — `/auth` command auto-links Telegram chat
- **File receive** — Bot receives files → saves to `/srv/nas/shared/Inbox/`
- **Trash warning** — Weekly Saturday notification if trash > 10 GB
- **Browser upload** — Token-based HTML upload form via Telegram link
- **Local API support** — Config fields for Telegram Local Bot API (up to 2 GB files)

### Family Management
- **Family list** — View members with folder sizes and avatars
- **Add member** — Admin creates new family user
- **Remove member** — Admin deletes family member

### Device Settings
- **Device info** — Serial, IP, firmware version, board model
- **Rename device** — Change Cubie display name
- **Shutdown/Reboot** — Admin system control

### Discovery & Onboarding
- **mDNS discovery** — Find Cubie via `_cubie-nas._tcp` service
- **BLE fallback** — Bluetooth LE discovery when mDNS fails
- **Network scan** — Subnet sweep for first-time setup
- **Splash routing** — Auto-route to onboarding or dashboard based on auth state

---

## Planned / In Progress

- **Telegram large files** — Full Task 13 implementation: local Bot API server, Docker setup script, 2 GB file receive (see `tasks.md`)
- **OTA firmware update** — `POST /system/update` exists but has TODO stub
- **Auto AP fallback** — `auto_ap.py` exists for access-point mode when no network (partially implemented)

---

## Deferred

- **Multi-SBC support** — No HAL abstraction yet; device paths hardcoded to Cubie A7Z (critique A4)
- **Incremental document indexing** — Current FTS5 re-scan is O(library size) on startup (critique S4)
- **Cursor-based pagination** — Current offset pagination lacks sort stability guarantees (critique S3)
- **AI file categorization** — RAM budget on ARM is too tight for on-device ML (blueprint constraint: ≤256 MB)
- **iOS app** — Flutter supports iOS but no testing/signing done
- **Multi-device management** — Managing multiple Cubies from one app