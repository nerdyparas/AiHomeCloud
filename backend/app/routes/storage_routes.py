"""
Storage routes — device listing, scan, format, mount, unmount, eject, stats.
"""

import asyncio
import json
import logging
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from shutil import disk_usage
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException

from ..auth import get_current_user, require_admin
from ..config import settings
from ..models import (
    EjectRequest,
    FormatRequest,
    MountRequest,
    StorageDevice,
    StorageStats,
)
from ..job_store import JobStatus, create_job, update_job
from .. import store
from ..subprocess_runner import run_command
from .event_routes import emit_device_mounted, emit_device_ejected

logger = logging.getLogger("cubie.storage")

router = APIRouter(prefix="/api/v1/storage", tags=["storage"])

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

def _classify_transport(device: dict) -> str:
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


def _is_os_partition(device: dict) -> bool:
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

async def _list_block_devices() -> List[dict]:
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
        # Validation error from run_command
        logger.warning("lsblk validation failed")
        return []
    except Exception as e:
        logger.error("Failed to list block devices: %s", e)
        return []


def _flatten_devices(devices: list, parent: Optional[dict] = None) -> list:
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
            result.extend(_flatten_devices(children, parent=dev))

    return result


async def _find_partition(device_path: str) -> Optional[dict]:
    """Look up a specific device by path (e.g. '/dev/sda1')."""
    raw_devices = await _list_block_devices()
    partitions = _flatten_devices(raw_devices)
    return next(
        (p for p in partitions if f"/dev/{p['name']}" == device_path),
        None,
    )


def _build_device_list(partitions: list) -> list[StorageDevice]:
    """Convert raw lsblk partitions to StorageDevice models."""
    nas_root_str = str(settings.nas_root)
    result: list[StorageDevice] = []

    for part in partitions:
        name = part.get("name", "")
        transport = _classify_transport(part)
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
            isOsDisk=_is_os_partition(part),
        ))

    return result


# ── NAS service helpers ──────────────────────────────────────────────────────

async def _stop_nas_services():
    """Best-effort stop of NAS-related services before unmount."""
    for svc in ("smbd", "nmbd", "nfs-kernel-server", "minidlnad"):
        try:
            await run_command(["systemctl", "stop", svc])
        except Exception:
            pass  # service may not be installed


async def _start_nas_services():
    """Best-effort start of NAS services after mount."""
    for svc in ("smbd", "nmbd"):
        try:
            await run_command(["systemctl", "start", svc])
        except Exception:
            pass


# ── Open file handle check ───────────────────────────────────────────────────

async def _check_open_handles() -> list[dict]:
    """
    Check for processes with open file handles on the NAS root.
    Returns a list of {pid, user, command, path} dicts.
    """
    nas_root = str(settings.nas_root)
    blockers: list[dict] = []

    # Try lsof first (more detail)
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

    # Fallback to fuser
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

async def _do_unmount(force: bool = False) -> str:
    """
    Perform the full unmount sequence: stop services → sync → umount.
    Returns the device path that was unmounted.
    Raises HTTPException on failure.
    """
    storage_state = await store.get_storage_state()

    if not storage_state.get("activeDevice"):
        raise HTTPException(400, "No device is currently mounted")

    device_path = storage_state["activeDevice"]
    nas_root = str(settings.nas_root)

    # 0. Check for open file handles (unless force=True)
    if not force:
        blockers = await _check_open_handles()
        # Filter out known NAS service processes (we're about to stop them)
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

    # 1. Stop NAS services
    await _stop_nas_services()

    # 2. Sync filesystem
    try:
        await run_command(["sync"])
    except Exception:
        pass

    # 3. Unmount
    rc, _, stderr = await run_command(["umount", nas_root])
    if rc != 0:
        # Fallback: lazy unmount
        logger.warning("Normal unmount failed, trying lazy unmount: %s", stderr)
        rc2, _, stderr2 = await run_command(["umount", "-l", nas_root])
        if rc2 != 0:
            raise HTTPException(
                500,
                f"Unmount failed (files may be in use): {stderr2}",
            )

    # 4. Clear persisted state
    await store.clear_storage_state()

    logger.info("Unmounted %s from %s", device_path, nas_root)
    return device_path


# ══════════════════════════════════════════════════════════════════════════════
# ENDPOINTS
# ══════════════════════════════════════════════════════════════════════════════


@router.get("/devices", response_model=List[StorageDevice])
async def list_devices(user: dict = Depends(get_current_user)):
    """List all block-device partitions on the system."""
    raw_devices = await _list_block_devices()
    partitions = _flatten_devices(raw_devices)
    return _build_device_list(partitions)


# ── 2A.2  Scan ───────────────────────────────────────────────────────────────

@router.get("/scan", response_model=List[StorageDevice])
async def scan_devices(user: dict = Depends(get_current_user)):
    """
    Re-scan for newly connected block devices.
    Triggers udev to re-detect, waits for settle, then returns fresh list.
    """
    try:
        await run_command(["udevadm", "trigger", "--subsystem-match=block"])
        await run_command(["udevadm", "settle", "--timeout=3"])
    except Exception as e:
        logger.warning("udevadm not available: %s", e)

    # Return fresh device list (reuse existing logic)
    raw_devices = await _list_block_devices()
    partitions = _flatten_devices(raw_devices)
    return _build_device_list(partitions)


# ── 2B.2  Pre-unmount check ──────────────────────────────────────────────────

@router.get("/check-usage")
async def check_usage(user: dict = Depends(get_current_user)):
    """
    Check for processes with open file handles on the NAS mount.
    Call before unmount to show the user what's blocking.
    Returns {blockers: [...], safe: bool}.
    """
    storage_state = await store.get_storage_state()
    if not storage_state.get("activeDevice"):
        return {"blockers": [], "safe": True, "message": "No device mounted"}

    blockers = await _check_open_handles()

    # Filter out NAS service processes (will be stopped during unmount)
    nas_service_cmds = {"smbd", "nmbd", "nfsd", "rpc.mountd", "minidlnad"}
    user_blockers = [
        b for b in blockers if b["command"] not in nas_service_cmds
    ]
    service_blockers = [
        b for b in blockers if b["command"] in nas_service_cmds
    ]

    return {
        "blockers": user_blockers,
        "serviceBlockers": service_blockers,
        "safe": len(user_blockers) == 0,
        "message": (
            "Safe to unmount"
            if len(user_blockers) == 0
            else f"{len(user_blockers)} process(es) have open files"
        ),
    }


# ── 2A.3  Format ─────────────────────────────────────────────────────────────

@router.post("/format")
async def format_device(
    req: FormatRequest,
    user: dict = Depends(require_admin),
):
    """
    Format a device as ext4.
    Safety: confirmDevice must match device path (like GitHub repo-delete).
    """
    if req.confirm_device != req.device:
        raise HTTPException(
            400,
            "Device confirmation does not match — please confirm the device path.",
        )

    target = await _find_partition(req.device)

    if not target:
        raise HTTPException(404, f"Device {req.device} not found")
    if _is_os_partition(target):
        raise HTTPException(403, "Cannot format an OS partition")
    if target.get("mountpoint"):
        raise HTTPException(409, "Device is currently mounted — unmount first")

    job = create_job()
    update_job(job.id, status=JobStatus.running)

    async def _run_format_job() -> None:
        try:
            logger.warning("FORMATTING %s as ext4 (label=%s)", req.device, req.label)

            rc, _, stderr = await run_command([
                "mkfs.ext4", "-F", "-L", req.label, req.device
            ], timeout=600)

            if rc != 0:
                update_job(job.id, status=JobStatus.failed, error=f"Format failed: {stderr}")
                return

            update_job(
                job.id,
                status=JobStatus.completed,
                result={
                    "status": "formatted",
                    "device": req.device,
                    "fstype": "ext4",
                    "label": req.label,
                },
            )
            logger.info("Formatted %s successfully", req.device)
        except Exception as e:
            update_job(job.id, status=JobStatus.failed, error=str(e))

    async def _run_with_timeout() -> None:
        try:
            await asyncio.wait_for(_run_format_job(), timeout=600)
        except asyncio.TimeoutError:
            update_job(job.id, status=JobStatus.failed, error="Format job timed out after 10 minutes")

    asyncio.create_task(_run_with_timeout())
    return {"jobId": job.id}


# ── 2A.4  Mount ──────────────────────────────────────────────────────────────

@router.post("/mount")
async def mount_device(
    req: MountRequest,
    user: dict = Depends(require_admin),
):
    """Mount a device at the NAS root (/srv/nas)."""
    nas_root = str(settings.nas_root)

    # Check if something is already active
    storage_state = await store.get_storage_state()
    if storage_state.get("activeDevice"):
        raise HTTPException(
            409,
            f"Device {storage_state['activeDevice']} is already mounted at {nas_root}",
        )

    target = await _find_partition(req.device)

    if not target:
        raise HTTPException(404, f"Device {req.device} not found")
    if _is_os_partition(target):
        raise HTTPException(403, "Cannot mount an OS partition as NAS storage")
    if not target.get("fstype"):
        raise HTTPException(400, "Device has no filesystem — format it first")

    # Ensure mount point exists
    settings.nas_root.mkdir(parents=True, exist_ok=True)

    # Mount
    rc, _, stderr = await run_command(["mount", req.device, nas_root])
    if rc != 0:
        raise HTTPException(500, f"Mount failed: {stderr}")

    # Create standard NAS directories
    settings.personal_path.mkdir(parents=True, exist_ok=True)
    settings.shared_path.mkdir(parents=True, exist_ok=True)

    # Persist mount state
    await store.save_storage_state({
        "activeDevice": req.device,
        "mountedAt": nas_root,
        "fstype": target.get("fstype", ""),
        "label": target.get("label", ""),
        "model": (target.get("model") or "").strip(),
        "transport": _classify_transport(target),
        "mountedSince": datetime.now(timezone.utc).isoformat(),
    })

    # Start NAS services
    await _start_nas_services()

    logger.info("Mounted %s at %s", req.device, nas_root)
    await emit_device_mounted(req.device, nas_root)
    return {"status": "mounted", "device": req.device, "mountPoint": nas_root}


# ── 2A.5  Unmount ────────────────────────────────────────────────────────────

@router.post("/unmount")
async def unmount_device(
    force: bool = False,
    user: dict = Depends(require_admin),
):
    """
    Safely unmount the NAS storage (stop services → sync → umount).
    Set force=true to skip the open-file-handle check.
    """
    device_path = await _do_unmount(force=force)
    return {"status": "unmounted", "device": device_path}


# ── 2A.6  Eject ──────────────────────────────────────────────────────────────

@router.post("/eject")
async def eject_device(
    req: EjectRequest,
    user: dict = Depends(require_admin),
):
    """
    Safely eject a USB device: unmount → power off USB port.
    Only works for USB-connected storage.
    """
    storage_state = await store.get_storage_state()
    active_device = storage_state.get("activeDevice", "")

    # If the device to eject is currently mounted, unmount first (force=True)
    if active_device == req.device:
        await _do_unmount(force=True)

    # Extract parent disk name  (e.g. "/dev/sda1" → "sda")
    dev_name = req.device.split("/")[-1]          # "sda1"
    disk_name = dev_name.rstrip("0123456789")     # "sda"

    # Power off USB device via sysfs
    delete_path = Path(f"/sys/block/{disk_name}/device/delete")
    try:
        if delete_path.exists():
            try:
                delete_path.write_text("1")
                logger.info("Ejected USB device %s via sysfs", disk_name)
            except Exception:
                # Try udisksctl as fallback
                rc, _, stderr = await run_command(["udisksctl", "power-off", "-b", f"/dev/{disk_name}"])
                if rc == 0:
                    logger.info("Ejected USB device %s via udisksctl", disk_name)
                else:
                    logger.warning(
                        "Could not power off %s — device may need manual removal: %s",
                        disk_name, stderr,
                    )
        else:
            # Try udisksctl as fallback
            rc, _, stderr = await run_command(["udisksctl", "power-off", "-b", f"/dev/{disk_name}"])
            if rc == 0:
                logger.info("Ejected USB device %s via udisksctl", disk_name)
            else:
                logger.warning(
                    "Could not power off %s — device may need manual removal: %s",
                    disk_name, stderr,
                )
    except Exception as e:
        logger.warning("Could not power off USB device: %s", e)

    await emit_device_ejected(req.device)
    return {"status": "ejected", "device": req.device}


# ── 2A.7  Stats ──────────────────────────────────────────────────────────────

@router.get("/stats", response_model=StorageStats)
async def storage_stats(user: dict = Depends(get_current_user)):
    """
    Return disk usage for the NAS root.
    When an external device is mounted at /srv/nas, this automatically
    reports that device's capacity (shutil.disk_usage follows mount points).
    """
    try:
        usage = disk_usage(str(settings.nas_root))
        total_gb = round(usage.total / (1024 ** 3), 1)
        used_gb = round(usage.used / (1024 ** 3), 1)
    except Exception:
        total_gb = settings.total_storage_gb
        used_gb = 0.0

    return StorageStats(totalGB=total_gb, usedGB=used_gb)


# ── 2A.10  Auto-remount (called from main.py lifespan) ───────────────────────

async def try_auto_remount():
    """
    On startup, check storage.json for a previously-mounted device.
    If the device is still present and not yet mounted, remount it.
    """
    state = await store.get_storage_state()
    device_path = state.get("activeDevice")

    if not device_path:
        logger.info("No saved storage mount — skipping auto-remount")
        return

    logger.info("Auto-remount: checking saved device %s", device_path)

    # Check the device still exists
    dev_node = Path(device_path)
    if not dev_node.exists():
        logger.warning(
            "Auto-remount: device %s not found — was it removed?", device_path
        )
        await store.clear_storage_state()
        return

    # Check if already mounted at NAS root
    nas_root = str(settings.nas_root)
    try:
        with open("/proc/mounts") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2 and parts[0] == device_path and parts[1] == nas_root:
                    logger.info(
                        "Auto-remount: %s is already mounted at %s", device_path, nas_root
                    )
                    return
    except Exception:
        pass

    # Attempt to mount
    settings.nas_root.mkdir(parents=True, exist_ok=True)

    rc, _, stderr = await run_command(["mount", device_path, nas_root], timeout=30)

    if rc == 0:
        logger.info("Auto-remount: successfully mounted %s at %s", device_path, nas_root)
        # Ensure NAS dirs exist
        settings.personal_path.mkdir(parents=True, exist_ok=True)
        settings.shared_path.mkdir(parents=True, exist_ok=True)
        # Start NAS services
        await _start_nas_services()
    else:
        logger.error(
            "Auto-remount: failed to mount %s — %s", device_path, stderr
        )
        await store.clear_storage_state()
