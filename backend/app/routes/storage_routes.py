"""
Storage routes Ã¢â‚¬â€ endpoint handlers for device listing, scan, format, mount,
unmount, eject, stats, and auto-remount.

Helper functions (lsblk parsing, device classification, mount/unmount logic)
are in storage_helpers.py.
"""

import asyncio
import logging
from datetime import datetime, timezone
from pathlib import Path
from shutil import disk_usage
from typing import List

from fastapi import APIRouter, Depends, HTTPException

from ..auth import get_current_user, require_admin
from ..config import settings
from ..models import (
    EjectRequest,
    FormatRequest,
    MountRequest,
    SmartActivateRequest,
    StorageDevice,
    StorageStats,
)
from ..job_store import JobStatus, create_job, update_job
from .. import store
from ..subprocess_runner import run_command
from .event_routes import emit_device_mounted, emit_device_ejected
from .storage_helpers import (
    _display_name,
    _find_best_partition,
    _partition_path,
    build_device_list,
    check_open_handles,
    classify_transport,
    do_unmount,
    find_partition,
    is_os_partition,
    list_block_devices,
    start_nas_services,
)

logger = logging.getLogger("aihomecloud.storage")

router = APIRouter(prefix="/api/v1/storage", tags=["storage"])


@router.get("/devices", response_model=List[StorageDevice])
async def list_devices(user: dict = Depends(get_current_user)):
    """List all physical drives on the system (one entry per disk)."""
    raw_devices = await list_block_devices()
    return build_device_list(raw_devices)


# Ã¢â€â‚¬Ã¢â€â‚¬ 2A.2  Scan Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

@router.get("/scan", response_model=List[StorageDevice])
async def scan_devices(user: dict = Depends(get_current_user)):
    """
    Re-scan for newly connected block devices.
    Triggers udev to re-detect, waits for settle, then returns fresh list.
    """
    try:
        await run_command(["sudo", "udevadm", "trigger", "--subsystem-match=block"])
        await run_command(["sudo", "udevadm", "settle", "--timeout=3"])
    except Exception as e:
        logger.warning("udevadm not available: %s", e)

    # Return fresh device list (reuse existing logic)
    raw_devices = await list_block_devices()
    return build_device_list(raw_devices)


# â”€â”€ Smart-activate helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

async def _post_mount_setup(partition_path: str, disk: dict, display_name: str) -> None:
    """After a successful mount: create dirs, persist storage state, start services."""
    nas_root = str(settings.nas_root)
    settings.personal_path.mkdir(parents=True, exist_ok=True)
    settings.family_path.mkdir(parents=True, exist_ok=True)
    settings.entertainment_path.mkdir(parents=True, exist_ok=True)
    await store.save_storage_state({
        "activeDevice": partition_path,
        "mountedAt": nas_root,
        "displayName": display_name,
        "transport": classify_transport(disk),
        "model": (disk.get("model") or "").strip(),
        "mountedSince": datetime.now(timezone.utc).isoformat(),
    })
    await start_nas_services()


async def _smart_format_and_mount(job_id: str, disk_name: str, display_name: str) -> None:
    """Async job: wipe disk â†’ GPT partition â†’ mkfs.ext4 â†’ mount â†’ post-setup.

    Uses run_command() â€” never shell=True.
    Uses settings.nas_root â€” never a hardcoded path.
    """
    disk_path = f"/dev/{disk_name}"
    partition_path = _partition_path(disk_name)
    try:
        nas_root = str(settings.nas_root)

        # Step 1a: Wipe existing GPT/MBR signatures (non-fatal if it fails)
        logger.warning("SMART-ACTIVATE: wiping signatures on %s", disk_path)
        await run_command(["sudo", "sgdisk", "-Z", disk_path], timeout=30)

        # Step 1b: Create new GPT with one Linux-data partition spanning the whole disk
        rc, _, stderr = await run_command(
            ["sudo", "sgdisk", "-n", "1:0:0", "-t", "1:8300", disk_path],
            timeout=30,
        )
        if rc != 0:
            update_job(job_id, status=JobStatus.failed, error=f"Partitioning failed: {stderr}")
            return

        # Step 2: Let udev create the new partition device node
        await asyncio.sleep(2)
        await run_command(["sudo", "udevadm", "settle", "--timeout=5"])

        # Step 3: Format as ext4
        logger.warning("SMART-ACTIVATE: formatting %s as ext4", partition_path)
        rc, _, stderr = await run_command(
            ["sudo", "mkfs.ext4", "-F", "-L", "AiHomeCloud", partition_path],
            timeout=600,
        )
        if rc != 0:
            update_job(job_id, status=JobStatus.failed, error=f"Format failed: {stderr}")
            return

        # Step 4: Mount
        settings.nas_root.mkdir(parents=True, exist_ok=True)
        rc, _, stderr = await run_command(
            ["sudo", "mount", partition_path, nas_root],
            timeout=30,
        )
        if rc != 0:
            update_job(job_id, status=JobStatus.failed, error=f"Mount failed: {stderr}")
            return

        # Step 5: Post-mount setup (dirs, state, services, event)
        disk_stub = {"name": disk_name, "tran": "", "model": ""}
        await _post_mount_setup(partition_path, disk_stub, display_name)
        await emit_device_mounted(partition_path, nas_root)

        update_job(
            job_id,
            status=JobStatus.completed,
            result={"action": "formatted_and_mounted", "device": partition_path},
        )
        logger.info("SMART-ACTIVATE: %s ready at %s", partition_path, nas_root)
    except Exception as e:
        update_job(job_id, status=JobStatus.failed, error=str(e))
        logger.exception("SMART-ACTIVATE job failed: %s", e)


# â”€â”€ Smart-activate endpoint â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@router.post("/smart-activate")
async def smart_activate(
    req: SmartActivateRequest,
    user: dict = Depends(require_admin),
):
    """One-tap drive setup.

    Accepts a whole-disk path (e.g. /dev/sda). Detects the drive state
    and does the right thing automatically:
      A  Has ext4 partition  â†’ mount it, return action=mounted
      B/C No ext4 / bare disk â†’ start format job, return action=formatting + jobId
      D  Already active       â†’ return action=already_active (idempotent)

    Response always includes display_name (no /dev/ paths or tech jargon).
    """
    # â”€â”€ State D: already active â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    storage_state = await store.get_storage_state()
    active_device = storage_state.get("activeDevice", "")
    if active_device and active_device.startswith(req.device):
        # Re-read lsblk for a fresh display_name if possible
        raw = await list_block_devices()
        disk = next((d for d in raw if f"/dev/{d['name']}" == req.device), None)
        display = (
            _display_name(disk) if disk
            else storage_state.get("displayName", req.device)
        )
        return {"action": "already_active", "display_name": display}

    # â”€â”€ Find disk in lsblk â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    raw = await list_block_devices()
    disk = next((d for d in raw if f"/dev/{d['name']}" == req.device), None)
    if disk is None:
        raise HTTPException(404, f"Drive not found: {req.device}")

    # â”€â”€ Security: never touch OS storage â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if is_os_partition(disk):
        raise HTTPException(403, "Cannot use system storage as a data drive")

    display = _display_name(disk)
    disk_name = disk["name"]
    children = disk.get("children", [])

    # â”€â”€ State A: has an ext4 partition ready to mount â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    best = _find_best_partition(children)
    if best and (best.get("fstype") or "") == "ext4":
        partition_dev = f"/dev/{best['name']}"
        nas_root = str(settings.nas_root)
        settings.nas_root.mkdir(parents=True, exist_ok=True)
        rc, _, stderr = await run_command(
            ["sudo", "mount", partition_dev, nas_root], timeout=30
        )
        if rc != 0:
            raise HTTPException(500, f"Could not activate drive: {stderr}")
        await _post_mount_setup(partition_dev, disk, display)
        await emit_device_mounted(partition_dev, nas_root)
        return {"action": "mounted", "display_name": display}

    # â”€â”€ State B/C: needs formatting â€” start async job â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    job = create_job()
    update_job(job.id, status=JobStatus.running)
    asyncio.create_task(_smart_format_and_mount(job.id, disk_name, display))
    return {"action": "formatting", "display_name": display, "jobId": job.id}


# â”€â”€ 2B.2  Pre-unmount check â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    blockers = await check_open_handles()

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


# Ã¢â€â‚¬Ã¢â€â‚¬ 2A.3  Format Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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
            "Device confirmation does not match Ã¢â‚¬â€ please confirm the device path.",
        )

    target = await find_partition(req.device)

    if not target:
        raise HTTPException(404, f"Device {req.device} not found")
    if is_os_partition(target):
        raise HTTPException(403, "Cannot format an OS partition")
    if target.get("mountpoint"):
        raise HTTPException(409, "Device is currently mounted Ã¢â‚¬â€ unmount first")

    job = create_job()
    update_job(job.id, status=JobStatus.running)

    async def _run_format_job() -> None:
        try:
            logger.warning("FORMATTING %s as ext4 (label=%s)", req.device, req.label)

            rc, _, stderr = await run_command([
                "sudo", "mkfs.ext4", "-F", "-L", req.label, req.device
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


# Ã¢â€â‚¬Ã¢â€â‚¬ 2A.4  Mount Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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

    target = await find_partition(req.device)

    if not target:
        raise HTTPException(404, f"Device {req.device} not found")
    if is_os_partition(target):
        raise HTTPException(403, "Cannot mount an OS partition as NAS storage")
    if not target.get("fstype"):
        raise HTTPException(400, "Device has no filesystem Ã¢â‚¬â€ format it first")

    # Ensure mount point exists
    settings.nas_root.mkdir(parents=True, exist_ok=True)

    # Mount
    rc, _, stderr = await run_command(["sudo", "mount", req.device, nas_root])
    if rc != 0:
        raise HTTPException(500, f"Mount failed: {stderr}")

    # Create standard NAS directories
    settings.personal_path.mkdir(parents=True, exist_ok=True)
    settings.family_path.mkdir(parents=True, exist_ok=True)
    settings.entertainment_path.mkdir(parents=True, exist_ok=True)

    # Persist mount state
    await store.save_storage_state({
        "activeDevice": req.device,
        "mountedAt": nas_root,
        "fstype": target.get("fstype", ""),
        "label": target.get("label", ""),
        "model": (target.get("model") or "").strip(),
        "transport": classify_transport(target),
        "mountedSince": datetime.now(timezone.utc).isoformat(),
    })

    # Start NAS services
    await start_nas_services()

    logger.info("Mounted %s at %s", req.device, nas_root)
    await emit_device_mounted(req.device, nas_root)
    return {"status": "mounted", "device": req.device, "mountPoint": nas_root}


# Ã¢â€â‚¬Ã¢â€â‚¬ 2A.5  Unmount Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

@router.post("/unmount")
async def unmount_device(
    force: bool = False,
    user: dict = Depends(require_admin),
):
    """
    Safely unmount the NAS storage (stop services Ã¢â€ â€™ sync Ã¢â€ â€™ umount).
    Set force=true to skip the open-file-handle check.
    """
    device_path = await do_unmount(force=force)
    return {"status": "unmounted", "device": device_path}


# Ã¢â€â‚¬Ã¢â€â‚¬ 2A.6  Eject Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

@router.post("/eject")
async def eject_device(
    req: EjectRequest,
    user: dict = Depends(require_admin),
):
    """
    Safely eject a USB device: unmount Ã¢â€ â€™ power off USB port.
    Only works for USB-connected storage.
    """
    storage_state = await store.get_storage_state()
    active_device = storage_state.get("activeDevice", "")

    # If the device to eject is currently mounted, unmount first (force=True)
    if active_device == req.device:
        await do_unmount(force=True)

    # Extract parent disk name  (e.g. "/dev/sda1" Ã¢â€ â€™ "sda")
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
                rc, _, stderr = await run_command(["sudo", "udisksctl", "power-off", "-b", f"/dev/{disk_name}"])
                if rc == 0:
                    logger.info("Ejected USB device %s via udisksctl", disk_name)
                else:
                    logger.warning(
                        "Could not power off %s Ã¢â‚¬â€ device may need manual removal: %s",
                        disk_name, stderr,
                    )
        else:
            # Try udisksctl as fallback
            rc, _, stderr = await run_command(["sudo", "udisksctl", "power-off", "-b", f"/dev/{disk_name}"])
            if rc == 0:
                logger.info("Ejected USB device %s via udisksctl", disk_name)
            else:
                logger.warning(
                    "Could not power off %s Ã¢â‚¬â€ device may need manual removal: %s",
                    disk_name, stderr,
                )
    except Exception as e:
        logger.warning("Could not power off USB device: %s", e)

    await emit_device_ejected(req.device)
    return {"status": "ejected", "device": req.device}


# Ã¢â€â‚¬Ã¢â€â‚¬ 2A.7  Stats Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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


# Ã¢â€â‚¬Ã¢â€â‚¬ 2A.10  Auto-remount (called from main.py lifespan) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

async def try_auto_remount():
    """
    On startup, check storage.json for a previously-mounted device.
    If the device is still present and not yet mounted, remount it.
    """
    state = await store.get_storage_state()
    device_path = state.get("activeDevice")

    if not device_path:
        logger.info("No saved storage mount Ã¢â‚¬â€ skipping auto-remount")
        return

    logger.info("Auto-remount: checking saved device %s", device_path)

    # Check the device still exists
    dev_node = Path(device_path)
    if not dev_node.exists():
        logger.warning(
            "Auto-remount: device %s not found Ã¢â‚¬â€ was it removed?", device_path
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

    rc, _, stderr = await run_command(["sudo", "mount", device_path, nas_root], timeout=30)

    if rc == 0:
        logger.info("Auto-remount: successfully mounted %s at %s", device_path, nas_root)
        # Ensure NAS dirs exist
        settings.personal_path.mkdir(parents=True, exist_ok=True)
        settings.family_path.mkdir(parents=True, exist_ok=True)
        settings.entertainment_path.mkdir(parents=True, exist_ok=True)
        # Start NAS services
        await start_nas_services()
    else:
        logger.error(
            "Auto-remount: failed to mount %s Ã¢â‚¬â€ %s", device_path, stderr
        )
        await store.clear_storage_state()
