# Hardware Reference — Supported SBCs

> Verified against `board.py` and `config.py` as of 2026-03-15.
> `board.py` auto-detects the board via `/proc/device-tree/model` and falls back to
> auto-detecting thermal zones and LAN interface if the board isn't in `KNOWN_BOARDS`.

---

## Radxa ROCK Pi 4A — Development / Test Hardware

| Spec | Value |
|------|-------|
| SoC | Rockchip RK3399 (ARM Cortex-A72 + A53, 64-bit) |
| RAM | 4 GB LPDDR4 |
| OS Storage | microSD card |
| Ethernet | Gigabit — interface `end0` |
| Wi-Fi | 802.11 b/g/n/ac |
| Bluetooth | BLE 5.0 |
| USB | USB 3.0 host ports |
| NVMe | M.2 slot (PCIe) |
| GPIO | 40-pin header |
| OS (tested) | Armbian_community 26.2.0 Ubuntu 24.04 Noble |
| Kernel (tested) | 6.18.13-current-rockchip64 |
| Hostname | `rockpi-4a` |
| DTB model string | `Radxa ROCK Pi 4A` |

**board.py** substring match: `"rock pi 4"` → `"Radxa ROCK Pi 4A"`  
**auto-detected**: thermal zone = `/sys/class/thermal/thermal_zone0/temp`, LAN = `end0`

---

## Radxa Cubie A7Z — Production Target

| Spec | Value |
|------|-------|
| SoC | Rockchip (ARM 64-bit) |
| RAM | 8 GB |
| Ethernet | Gigabit |
| Wi-Fi | 802.11ac |
| Bluetooth | BLE 5.0 |
| USB | USB 3.0 host ports |
| NVMe | M.2 slot (PCIe) |
| GPIO | 40-pin header |
| DTB model string | `Radxa CUBIE A7Z` |

**board.py** substring match: `"cubie a7z"` → `"Radxa CUBIE A7Z"`

---

## Radxa Cubie A7A — Alternate Production Target

| Spec | Value |
|------|-------|
| SoC | Allwinner A527 (sun60iw2) |
| DTB model string | `sun60iw2` (SoC ID, not board name) |

**board.py** exact key match: `"sun60iw2"` → `"Radxa CUBIE A7A"`

---

## Other Supported Boards

| Board | DTB substring | Notes |
|-------|--------------|-------|
| Raspberry Pi 4 Model B | `"raspberry pi 4"` | Tested with Raspberry Pi OS |
| Unknown/Generic | any | Falls back to auto-detect; model_name = "unknown" |

> **Adding a new board**: Add an entry to `KNOWN_BOARDS` dict and `_BOARD_SUBSTRINGS` list
> in `backend/app/board.py`. Thermal zone and LAN interface are auto-detected at runtime.

---

## Storage Interfaces

### microSD (OS)
- Device: `/dev/mmcblk0`, partitions: `mmcblk0p1`, `mmcblk0p2`, etc.
- Contains: boot partition + root filesystem
- **Do not use for NAS data** (wear, size, speed)

### USB Storage
- Device: `/dev/sda`, `/dev/sdb`, etc. | Partitions: `sda1`, `sda2`, etc.
- `lsblk` TRAN field: `usb`
- **Hot-pluggable** — must support safe eject
- Typical: USB pen drives (8–256 GB), USB SSDs, USB HDDs

### NVMe SSD
- Device: `/dev/nvme0n1` | Partitions: `nvme0n1p1`, etc.
- `lsblk` TRAN field: `nvme` (or detected via path prefix)
- **Not hot-pluggable** — mounted at boot, stays permanently

---

## Key System Paths

| Path | Purpose |
|------|---------|
| `/srv/nas/` | NAS root — external storage or plain directory in dev |
| `/srv/nas/personal/` | Per-user private folders |
| `/srv/nas/family/` | Family shared folder |
| `/srv/nas/entertainment/` | Entertainment media (Movies, Music, etc.) |
| `/var/lib/aihomecloud/` | Backend config/state JSON files, TLS certs |
| `/etc/systemd/system/aihomecloud.service` | System-level service (installed by dev-setup.sh) |
| `/etc/avahi/services/aihomecloud.service` | mDNS advertisement (deployed by dev-setup.sh) |
| `/etc/sudoers.d/aihomecloud` | NOPASSWD rules for mount/umount/mkfs/systemctl |
| `backend/.venv/` | Python virtual environment (in-repo for dev) |

---

## Linux Commands for Storage Management

```bash
# List block devices with details
lsblk -J -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,TRAN,SERIAL

# Check if a device is mounted
findmnt /dev/sda1

# Mount
sudo mount /dev/sda1 /srv/nas

# Unmount
sudo umount /srv/nas

# Format as ext4
sudo mkfs.ext4 -L NAS /dev/sda1

# Sync before eject
sync

# Power off USB port (safe eject)
echo 1 > /sys/bus/usb/devices/<device>/remove

# Re-scan USB bus
udevadm trigger
```

---

## Network Services

| Service | Port | Systemd Unit | Purpose |
|---------|------|-------------|---------|
| AiHomeCloud API | 8443 | `aihomecloud` | FastAPI HTTPS backend |
| Samba (SMB) | 445 | `smbd` | Windows file sharing |
| NFS | 2049 | `nfs-server` | Linux/Mac network FS |
| SSH | 22 | `sshd` | Remote terminal |
| DLNA | 8200 | `minidlna` | Media streaming |
| Avahi (mDNS) | 5353 | `avahi-daemon` | `_aihomecloud-nas._tcp` — LAN discovery |

---

## Verifying mDNS on the Board

```bash
# Check avahi is running
sudo systemctl status avahi-daemon

# List advertised AiHomeCloud services
avahi-browse -t _aihomecloud-nas._tcp

# Resolve the hostname
avahi-resolve -n $(hostname).local

# What the Flutter app will see (should return the AiHomeCloud identity JSON)
curl -sk https://$(hostname -I | awk '{print $1}'):8443/
```

