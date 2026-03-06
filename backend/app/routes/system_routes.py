"""
System routes — device info, firmware, device name.
"""

from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import get_current_user
from ..config import settings, get_local_ip
from ..models import CubieDevice, FirmwareInfo, UpdateNameRequest
from .. import store

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
    """Check for available firmware updates."""
    # In production, this would query an update server.
    return FirmwareInfo(
        current_version=settings.firmware_version,
        latest_version="2.2.0",
        update_available=True,
        changelog=(
            "Bug fixes and performance improvements.\n"
            "Added SMB3 support.\n"
            "Improved thermal management."
        ),
        size_mb=156.2,
    )


@router.post("/update", status_code=status.HTTP_202_ACCEPTED)
async def trigger_update(user: dict = Depends(get_current_user)):
    """
    Trigger an OTA firmware update.
    In production this would kick off an async update process.
    """
    # TODO: Implement real OTA update logic
    return {"status": "update_started"}


@router.put("/name", status_code=status.HTTP_204_NO_CONTENT)
async def update_name(body: UpdateNameRequest, user: dict = Depends(get_current_user)):
    """Rename the device."""
    if not body.name.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Name cannot be empty")
    await store.update_device_name(body.name)
