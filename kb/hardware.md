# Hardware Reference — Radxa Cubie A7Z

> Verified against `board.py` and `config.py` as of 2025-07-25.

## Board Specs

| Spec | Value |
|---|---|
| SoC | Rockchip (ARM 64-bit) |
| RAM | 8 GB |
| OS Storage | microSD card |
| Ethernet | Gigabit |
| Wi-Fi | 802.11ac |
| Bluetooth | BLE 5.0 |
| USB | USB 3.0 host ports |
| NVMe | M.2 slot (PCIe) |
| GPIO | 40-pin header |

## Storage Interfaces

### microSD (OS)
- Device: `/dev/mmcblk0`, partitions: `mmcblk0p1`, `mmcblk0p2`, etc.
- Contains: boot partition + root filesystem
- **Do not use for NAS data** (wear, size, speed)

### USB Storage
- Device: `/dev/sda`, `/dev/sdb`, etc.
- Partitions: `sda1`, `sda2`, etc.
- `lsblk` TRAN field: `usb`
- **Hot-pluggable** — must support safe eject
- Typical: USB pen drives (8–256 GB), USB SSDs, USB HDDs

### NVMe SSD
- Device: `/dev/nvme0n1`
- Partitions: `nvme0n1p1`, `nvme0n1p2`, etc.
- `lsblk` TRAN field: `nvme` (or detected via path prefix)
- **Not hot-pluggable** — mounted at boot, stays permanently
- Typical: 128 GB – 2 TB M.2 SSDs

## Key System Paths

| Path | Purpose |
|---|---|
| `/srv/nas/` | NAS mount point (external storage mounts here) |
| `/srv/nas/personal/` | Per-user private folders |
| `/srv/nas/family/` | Family shared folder |
| `/srv/nas/entertainment/` | Entertainment media (Music, Videos, etc.) |
| `/var/lib/cubie/` | Backend config/state JSON files |
| `/opt/cubie/backend/` | Backend code + venv |
| `/etc/systemd/system/cubie-backend.service` | Systemd service |

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
sudo mkfs.ext4 -L CubieNAS /dev/sda1

# Sync before eject
sync

# Power off USB port (safe eject)
echo 1 > /sys/bus/usb/devices/<device>/remove

# Re-scan USB bus
echo 1 > /sys/bus/usb/devices/usb1/authorized
# or
udevadm trigger
```

## Network Services on the Cubie

| Service | Port | Systemd Unit | Purpose |
|---|---|---|---|
| CubieCloud API | 8443 | `cubie-backend` | FastAPI backend |
| Samba (SMB) | 445 | `smbd` | Windows file sharing |
| NFS | 2049 | `nfs-server` | Linux/Mac network FS |
| SSH | 22 | `sshd` | Remote terminal |
| DLNA | 8200 | `minidlna` | Media streaming |
| Avahi (mDNS) | 5353 | `avahi-daemon` | `_cubie-nas._tcp` discovery |
