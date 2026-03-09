"""
System routes — device info, firmware, device name, power management.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import get_current_user, require_admin
from ..config import settings, get_local_ip
from ..models import CubieDevice, FirmwareInfo, UpdateNameRequest
from .. import store
from ..subprocess_runner import run_command

logger = logging.getLogger("cubie.system")

router = APIRouter(prefix="/api/v1/system", tags=["system"])


@router.get("/info", response_model=CubieDevice)
async def device_info(user: dict = Depends(get_current_user)):
    """Return device identity & network info."""
    state = await store.get_device_state()
    return CubieDevice(
        serial=settings.device_serial,
        name=state.get("name", settings.device_name),
        ip=get_local_ip(),
        firmwareVersion=settings.firmware_version,
    )


@router.get("/firmware", response_model=FirmwareInfo)
async def check_firmware(user: dict = Depends(get_current_user)):
    """Check for available firmware updates. OTA not yet implemented."""
    return FirmwareInfo(
        current_version=settings.firmware_version,
        latest_version=settings.firmware_version,
        update_available=False,
        changelog="",
        size_mb=0.0,
    )


@router.post("/update", status_code=status.HTTP_202_ACCEPTED)
async def trigger_update(user: dict = Depends(require_admin)):
    """
    Trigger an OTA firmware update.
    In production this would kick off an async update process.
    """
    # TODO: Implement real OTA update logic
    return {"status": "update_started"}


@router.put("/name", status_code=status.HTTP_204_NO_CONTENT)
async def update_name(body: UpdateNameRequest, user: dict = Depends(require_admin)):
    """Rename the device."""
    if not body.name.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Name cannot be empty")
    await store.update_device_name(body.name)


# Map service IDs to their systemd unit names (mirrors service_routes)
_SERVICE_UNITS: dict[str, list[str]] = {
    "samba": ["smbd", "nmbd"],
    "nfs": ["nfs-kernel-server"],
    "ssh": ["ssh"],
    "dlna": ["minidlnad"],
}


@router.post("/shutdown", status_code=status.HTTP_202_ACCEPTED)
async def shutdown_device(user: dict = Depends(require_admin)):
    """Stop all active NAS services and power off the device."""
    # 1. Stop all enabled services
    services = await store.get_services()
    for svc in services:
        if svc.get("isEnabled"):
            units = _SERVICE_UNITS.get(svc["id"], [])
            for unit in units:
                ok, err = await _systemctl_stop(unit)
                if not ok:
                    logger.warning("Failed to stop %s: %s", unit, err)

    # 2. Power off the device
    logger.info("Shutdown requested by user %s", user.get("sub", "unknown"))
    rc, _, stderr = await run_command(
        ["sudo", "systemctl", "poweroff"], timeout=15
    )
    if rc != 0:
        raise HTTPException(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            f"Shutdown command failed: {stderr}",
        )
    return {"status": "shutting_down"}


async def _systemctl_stop(unit: str) -> tuple[bool, str]:
    """Run `systemctl stop <unit>` via centralized runner."""
    rc, _, stderr = await run_command(["sudo", "systemctl", "stop", unit], timeout=15)
    return rc == 0, stderr
