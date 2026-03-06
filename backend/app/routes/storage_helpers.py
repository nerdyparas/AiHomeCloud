"""
Storage helper functions — device classification, lsblk parsing, mount/unmount logic.

Split from storage_routes.py for better RAG chunking and code navigation.
Used internally by storage_routes.py endpoint handlers.
"""

import json
import logging
import tempfile
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


def is_os_partition(device: dict) -> bool:
    """Heuristic: is this partition part of the OS (SD card or system mount)."""
    name = (device.get("name") or "").lower()
    mountpoint = device.get("mountpoint") or ""

    if name.startswith("mmcblk"):
        return True

    system_mounts = {"/", "/boot", "/boot/firmware", "/var", tempfile.gettempdir(), "/home"}
    if mountpoint in system_mounts:
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


def build_device_list(partitions: list) -> list[StorageDevice]:
    """Convert raw lsblk partitions to StorageDevice models."""
    nas_root_str = str(settings.nas_root)
    result: list[StorageDevice] = []

    for part in partitions:
        name = part.get("name", "")
        transport = classify_transport(part)
        mountpoint = part.get("mountpoint")
        size_bytes = int(part.get("size") or 0)

        result.append(StorageDevice(
            name=name,
            path=f"/dev/{name}",
            sizeBytes=size_bytes,
            sizeDisplay=_human_size(size_bytes),
            fstype=part.get("fstype"),
            label=part.get("label"),
            model=(part.get("model") or "").strip() or None,
            transport=transport,
            mounted=bool(mountpoint),
            mountPoint=mountpoint,
            isNasActive=(mountpoint == nas_root_str),
            isOsDisk=is_os_partition(part),
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
