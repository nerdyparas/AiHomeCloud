# Storage Architecture

## Current State (v0.1)

Storage is treated as a single monolithic partition at `/srv/nas`. The backend uses `shutil.disk_usage()` on this path, which currently reports the **SD card** partition where the OS resides — not an external data drive.

```
/srv/nas/              ← NAS root (currently on SD card)
├── personal/          ← per-user folders (personal/<username>/)
│   └── paras/
└── shared/            ← shared family folder
```

**Problem:** SD card is small, has OS on it, and is not meant for bulk NAS data.

---

## Target Architecture (v0.2)

### Storage Hierarchy

```
SD Card (microSD):
├── / (OS root)
├── /var/lib/cubie/           ← config/state JSON files (stays on SD)
└── /srv/nas/                 ← mount point for external storage

External Storage (USB or NVMe):
└── mounted at /srv/nas/      ← when plugged in & configured
    ├── personal/
    │   ├── paras/
    │   └── kid1/
    └── shared/
```

### Storage Device Types

| Type | Device Path | Speed | Hot-pluggable | Primary Use |
|---|---|---|---|---|
| microSD | `/dev/mmcblk*` | Slow | No | OS + config only |
| USB pen drive | `/dev/sd*` | Medium | **Yes** | Portable NAS data |
| NVMe SSD | `/dev/nvme*` | Fast | No (hardware) | Permanent NAS data |

### Device Detection

On Linux ARM, storage devices appear in `/sys/block/` and `/dev/`. Detection strategy:

```python
# List block devices
lsblk -J -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,TRAN

# Filter by transport:
#   TRAN=usb   → USB pen drive / external HDD
#   TRAN=nvme  → NVMe SSD
#   TRAN=       → mmcblk (SD card, no TRAN field)
```

### Mount/Unmount Flow

```
User plugs in USB drive
        │
        ▼
App: "Scan for devices" (GET /api/v1/storage/scan)
        │
        ▼
Backend detects /dev/sda1 (USB, ext4, 64GB)
        │
        ▼
App shows: "USB Drive 64GB — ext4 — Not mounted"
        │
        ├── [Format] → POST /api/v1/storage/format {device, fstype}
        │               wipes & creates ext4 filesystem
        │
        └── [Mount as NAS] → POST /api/v1/storage/mount {device}
                              mount /dev/sda1 /srv/nas
                              creates personal/ + shared/ dirs
                              updates config
        │
        ▼
NAS storage active on external drive
        │
        ▼
User wants to unplug USB
        │
        ├── App: "Safe Remove" → POST /api/v1/storage/eject {device}
        │     1. Stop SMB service (if running)
        │     2. Stop DLNA, NFS if using NAS root
        │     3. sync filesystem
        │     4. umount /srv/nas
        │     5. (optional) power-off USB port via sysfs
        │     6. Notify app: "Safe to unplug"
        │
        └── App re-scans and shows: "No NAS storage active"
```

### Safe Removal Sequence (Critical)

Before unmounting, the backend MUST:
1. **Stop SMB/Samba** — `systemctl stop smbd` or toggle service
2. **Stop NFS** — if enabled
3. **Stop DLNA** — if using media from NAS
4. **Flush writes** — `sync`
5. **Unmount** — `umount /srv/nas`
6. **Power off USB port** (optional) — write to `/sys/bus/usb/devices/.../power`

If any service has open file handles, unmount will fail → backend must handle this gracefully.

### SD Card Storage (Fallback)

When no external storage is mounted, the app can still show the SD card's free space as a fallback with a **warning banner**:

> ⚠️ Using SD card for storage. Plug in a USB drive or NVMe SSD for dedicated NAS storage.

SD card personal/shared folders are OK for small amounts of data but the app should discourage large file storage on it.

---

## Backend Implementation Plan

### New Config Fields (`config.py`)
```python
# Default mount point for external NAS storage
nas_mount_point: Path = Path("/srv/nas")
# Fallback: use SD card partition if no external device
nas_fallback_to_sd: bool = True
```

### New Store Fields (`store.py`)
```python
# Track which device is currently mounted as NAS
# Stored in /var/lib/cubie/storage.json
{
  "activeDevice": "/dev/sda1",
  "deviceType": "usb",
  "fstype": "ext4",
  "mountedAt": "/srv/nas",
  "mountedSince": "2026-03-02T10:30:00Z"
}
```

### New Routes (`storage_routes.py` — expanded)
        - `GET /api/v1/storage/devices` — list all block devices via `lsblk`
        - `GET /api/v1/storage/scan` — re-scan (trigger kernel re-probe)
        - `POST /api/v1/storage/format` — format device (DANGEROUS — requires confirmation token)
        - `POST /api/v1/storage/mount` — mount device at NAS root
        - `POST /api/v1/storage/unmount` — safe unmount (stops services first)
        - `POST /api/v1/storage/eject` — unmount + power off USB port
        - `GET /api/v1/storage/stats` — (existing, updated to show correct device)

### New Models (`models.py`)
```python
class StorageDevice(BaseModel):
    name: str           # "sda1", "nvme0n1p1"
    path: str           # "/dev/sda1"
    size_gb: float
    fstype: str | None  # "ext4", None if unformatted
    model: str          # "SanDisk Ultra"
    transport: str      # "usb", "nvme", "sd"
    mounted: bool
    mount_point: str | None
    is_nas_active: bool # True if this is currently the NAS drive

class FormatRequest(BaseModel):
    device: str         # "/dev/sda1"
    fstype: str = "ext4"
    confirm_token: str  # Safety: must match a server-generated token

class MountRequest(BaseModel):
    device: str         # "/dev/sda1"
```

---

## Flutter Implementation Plan

### New Model (`models.dart`)
```dart
class StorageDevice {
  final String name;       // "sda1"
  final String path;       // "/dev/sda1"
  final double sizeGB;
  final String? fstype;
  final String model;      // "SanDisk Ultra"
  final String transport;  // "usb", "nvme", "sd"
  final bool mounted;
  final String? mountPoint;
  final bool isNasActive;
}
```

### UI: Storage Management (in Settings or dedicated screen)
- **Storage card** on Dashboard shows the active NAS device (or SD warning)
- **Settings → Storage** section with:
  - Active device info + usage bar
  - "Scan for devices" refresh button
  - Device list with mount/unmount/format actions
  - "Safe Remove" button (red, prominent) for USB drives
  - SD card fallback warning if no external storage
