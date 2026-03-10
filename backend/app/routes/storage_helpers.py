"""
Storage helper functions — device classification, lsblk parsing, mount/unmount logic.

Split from storage_routes.py for better RAG chunking and code navigation.
Used internally by storage_routes.py endpoint handlers.
"""

import json
import logging
from pathlib import Path
from typing import List, Optional

from fastapi import HTTPException

from ..config import settings
from ..models import StorageDevice
from .. import store
from ..subprocess_runner import run_command

logger = logging.getLogger("cubie.storage")

# ── Size helpers ─────────────────────────────────────────────────────────────

_SIZE_SUFFIXES = ["B", "KB", "MB", "GB", "TB"]


def _human_size(n: int) -> str:
    """Convert bytes to a human-readable string like '64.0 GB'."""
    val = float(n)
    for suffix in _SIZE_SUFFIXES:
        if val < 1024.0:
            return f"{val:.1f} {suffix}"
        val /= 1024.0
    return f"{val:.1f} PB"


# ── Device classification helpers ────────────────────────────────────────────

def classify_transport(device: dict) -> str:
    """Classify a block device into 'usb', 'nvme', or 'sd'."""
    tran = (device.get("tran") or "").lower()
    name = (device.get("name") or "").lower()

    if tran == "usb":
        return "usb"
    if tran == "nvme" or name.startswith("nvme"):
        return "nvme"
    if name.startswith("mmcblk"):
        return "sd"
    if tran:
        return tran
    return "unknown"


# Prefixes of device names that are always internal/OS storage.
# These must never be formatted regardless of mount state.
_OS_NAME_PREFIXES = (
    "mmcblk",   # SD card / eMMC (Cubie A7A OS disk)
    "mtdblock", # SPI/NAND flash (firmware / bootloader storage)
    "zram",     # Compressed RAM — never a real block device to format
    "loop",     # Loop devices — not real hardware
)

# Mount points that indicate a partition is part of the OS.
# Covers standard Linux, Raspberry Pi, and ARM SBC layout variants.
_OS_MOUNT_PREFIXES = (
    "/",
    "/boot",
    "/config",
    "/var",
    "/home",
    "/usr",
    "/opt",
    "/proc",
    "/sys",
)


def is_os_partition(device: dict) -> bool:
    """Return True if this partition must NOT be formatted.

    Blocks:
    - Internal non-hot-pluggable storage by device name prefix (mmcblk, mtd, zram, loop)
    - Any partition mounted at a system path (/, /boot, /boot/efi, /config, ...)
    - OS-partition detection is size-agnostic — external USB/NVMe of any size is formattable
      provided it is not mounted at a system path.
    """
    name = (device.get("name") or "").lower()
    mountpoint = (device.get("mountpoint") or "").rstrip("/")

    # Block all known-internal device types by name prefix
    if any(name.startswith(prefix) for prefix in _OS_NAME_PREFIXES):
        return True

    # Block if this partition is mounted at a system path (None/empty mountpoint = safe)
    if mountpoint and any(
        mountpoint == mp or mountpoint.startswith(mp + "/")
        for mp in _OS_MOUNT_PREFIXES
    ):
        return True

    return False


# ── lsblk helpers ────────────────────────────────────────────────────────────

async def list_block_devices() -> List[dict]:
    """Run lsblk -J -b and return the raw JSON device list."""
    try:
        rc, out, err = await run_command([
            "lsblk", "-J", "-b",
            "-o", "NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,LABEL,MODEL,TRAN,SERIAL",
        ])
        if rc != 0:
            logger.error("lsblk failed: %s", err)
            return []
        data = json.loads(out or "{}")
        return data.get("blockdevices", [])
    except ValueError:
        logger.warning("lsblk validation failed")
        return []
    except Exception as e:
        logger.error("Failed to list block devices: %s", e)
        return []


def flatten_devices(devices: list, parent: Optional[dict] = None) -> list:
    """Flatten nested lsblk tree into a list of partitions."""
    result = []
    for dev in devices:
        dev_type = (dev.get("type") or "").lower()
        children = dev.get("children", [])

        if parent:
            if not dev.get("model"):
                dev["model"] = parent.get("model")
            if not dev.get("tran"):
                dev["tran"] = parent.get("tran")
            if not dev.get("serial"):
                dev["serial"] = parent.get("serial")

        if dev_type == "part":
            result.append(dev)
        elif dev_type == "disk" and not children:
            result.append(dev)

        if children:
            result.extend(flatten_devices(children, parent=dev))

    return result


async def find_partition(device_path: str) -> Optional[dict]:
    """Look up a specific device by path (e.g. '/dev/sda1')."""
    raw_devices = await list_block_devices()
    partitions = flatten_devices(raw_devices)
    return next(
        (p for p in partitions if f"/dev/{p['name']}" == device_path),
        None,
    )


def _partition_path(disk_name: str) -> str:
    """Derive the first partition device path from a disk name.

    sda     → /dev/sda1       (traditional SCSI/SATA disk)
    nvme0n1 → /dev/nvme0n1p1  (NVMe — name ends with a digit)
    mmcblk0 → /dev/mmcblk0p1  (eMMC — same rule)
    """
    if disk_name and disk_name[-1].isdigit():
        return f"/dev/{disk_name}p1"
    return f"/dev/{disk_name}1"


def _display_name(disk: dict) -> str:
    """Return a human-friendly drive name. No /dev/ paths or technical terms."""
    model = (disk.get("model") or "").strip()
    tran = classify_transport(disk)
    size_bytes = int(disk.get("size") or 0)
    size_str = _human_size(size_bytes)
    transport_label = {"usb": "USB Drive", "nvme": "NVMe Drive"}.get(tran, "Drive")
    if model:
        return f"{model} ({size_str})"
    return f"{size_str} {transport_label}"


def _find_best_partition(children: list) -> Optional[dict]:
    """Find the best usable partition for mounting/activating.

    Priority:
    1. Largest ext4 partition that is not an OS partition
    2. Largest non-OS partition of any filesystem
    Returns None if all partitions are OS partitions or none exist.
    """
    usable = [p for p in children if not is_os_partition(p)]
    if not usable:
        return None
    # Prefer ext4 — ready to mount without formatting
    ext4_parts = [p for p in usable if (p.get("fstype") or "") == "ext4"]
    if ext4_parts:
        return max(ext4_parts, key=lambda p: int(p.get("size") or 0))
    # Fall back to largest usable partition of any type
    return max(usable, key=lambda p: int(p.get("size") or 0))


def build_device_list(raw_devices: list) -> list[StorageDevice]:
    """Convert raw lsblk disk-level devices to StorageDevice models.

    Returns ONE entry per physical disk (not per partition).
    OS disks and unsupported transports are filtered out.
    Call with the output of list_block_devices() directly — no need to
    flatten first.  flatten_devices() is still available for other uses
    (e.g. find_partition).
    """
    nas_root_str = str(settings.nas_root)
    result: list[StorageDevice] = []

    for disk in raw_devices:
        dev_type = (disk.get("type") or "").lower()
        if dev_type != "disk":
            continue

        # Filter by transport — only external hot-plug storage
        transport = classify_transport(disk)
        if transport not in ("usb", "nvme"):
            continue

        # Skip OS disks (mmcblk, zram, loop, system-mount prefixes)
        if is_os_partition(disk):
            continue

        children = disk.get("children", [])
        best = _find_best_partition(children)
        best_partition_path: Optional[str] = (
            f"/dev/{best['name']}" if best else None
        )

        # Determine mount / NAS-active state across all partitions
        # (an unpartitioned disk can itself be mounted directly)
        candidates = children if children else [disk]
        active_candidate = next(
            (c for c in candidates if c.get("mountpoint") == nas_root_str),
            None,
        )
        any_mounted_candidate = next(
            (c for c in candidates if c.get("mountpoint")),
            None,
        )
        mount_point: Optional[str] = (
            (active_candidate or any_mounted_candidate or {}).get("mountpoint")
        )

        name = disk.get("name", "")
        size_bytes = int(disk.get("size") or 0)

        result.append(StorageDevice(
            name=name,
            path=f"/dev/{name}",
            sizeBytes=size_bytes,
            sizeDisplay=_human_size(size_bytes),
            fstype=best.get("fstype") if best else None,
            label=best.get("label") if best else None,
            model=(disk.get("model") or "").strip() or None,
            transport=transport,
            mounted=bool(any_mounted_candidate),
            mountPoint=mount_point,
            isNasActive=bool(active_candidate),
            isOsDisk=False,
            displayName=_display_name(disk),
            bestPartition=best_partition_path,
        ))

    return result


# ── NAS service helpers ──────────────────────────────────────────────────────

async def stop_nas_services():
    """Best-effort stop of NAS-related services before unmount."""
    for svc in ("smbd", "nmbd", "nfs-kernel-server", "minidlnad"):
        try:
            await run_command(["sudo", "systemctl", "stop", svc])
        except Exception:
            pass


async def start_nas_services():
    """Best-effort start of NAS services after mount."""
    for svc in ("smbd", "nmbd"):
        try:
            await run_command(["sudo", "systemctl", "start", svc])
        except Exception:
            pass


# ── Open file handle check ───────────────────────────────────────────────────

async def check_open_handles() -> list[dict]:
    """
    Check for processes with open file handles on the NAS root.
    Returns a list of {pid, user, command, path} dicts.
    """
    nas_root = str(settings.nas_root)
    blockers: list[dict] = []

    try:
        rc, out, _ = await run_command(["lsof", "+D", nas_root])
        if rc == 0 and out:
            lines = out.strip().split("\n")
            for line in lines[1:]:
                parts = line.split()
                if len(parts) >= 9:
                    blockers.append({
                        "command": parts[0],
                        "pid": parts[1],
                        "user": parts[2],
                        "path": parts[8] if len(parts) > 8 else nas_root,
                    })
        return blockers
    except Exception:
        pass

    try:
        rc, _, stderr = await run_command(["fuser", "-v", "-m", nas_root])
        if stderr:
            lines = stderr.strip().split("\n")
            for line in lines[1:]:
                parts = line.split()
                if len(parts) >= 4:
                    blockers.append({
                        "command": parts[-1] if len(parts) > 4 else "unknown",
                        "pid": parts[1] if len(parts) > 1 else "?",
                        "user": parts[0] if parts else "?",
                        "path": nas_root,
                    })
    except Exception:
        logger.warning("Neither lsof nor fuser available for handle check")

    return blockers


# ── Core unmount logic (shared by unmount + eject) ───────────────────────────

async def do_unmount(force: bool = False) -> str:
    """
    Perform the full unmount sequence: stop services -> sync -> umount.
    Returns the device path that was unmounted.
    Raises HTTPException on failure.
    """
    storage_state = await store.get_storage_state()

    if not storage_state.get("activeDevice"):
        raise HTTPException(400, "No device is currently mounted")

    device_path = storage_state["activeDevice"]
    nas_root = str(settings.nas_root)

    if not force:
        blockers = await check_open_handles()
        nas_service_cmds = {"smbd", "nmbd", "nfsd", "rpc.mountd", "minidlnad"}
        user_blockers = [
            b for b in blockers
            if b["command"] not in nas_service_cmds
        ]
        if user_blockers:
            raise HTTPException(
                409,
                detail={
                    "error": "files_in_use",
                    "message": f"{len(user_blockers)} process(es) have open files on the NAS",
                    "blockers": user_blockers,
                },
            )

    await stop_nas_services()

    try:
        await run_command(["sync"])
    except Exception:
        pass

    rc, _, stderr = await run_command(["sudo", "umount", nas_root])
    if rc != 0:
        logger.warning("Normal unmount failed, trying lazy unmount: %s", stderr)
        rc2, _, stderr2 = await run_command(["sudo", "umount", "-l", nas_root])
        if rc2 != 0:
            raise HTTPException(
                500,
                f"Unmount failed (files may be in use): {stderr2}",
            )

    await store.clear_storage_state()

    logger.info("Unmounted %s from %s", device_path, nas_root)
    return device_path
