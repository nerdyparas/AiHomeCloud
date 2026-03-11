"""
Service management routes — list and toggle NAS services.
Uses real systemctl calls to start/stop systemd units on the Cubie.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import get_current_user, require_admin
from ..models import ServiceInfo, ToggleServiceRequest
from .. import store
from .event_routes import emit_service_toggled
from ..subprocess_runner import run_command

logger = logging.getLogger("cubie.services")

router = APIRouter(prefix="/api/v1/services", tags=["services"])

# Map our service IDs → systemd unit names
_SERVICE_UNITS: dict[str, list[str]] = {
    "samba": ["smbd", "nmbd"],
    "nfs": ["nfs-kernel-server"],
    "ssh": ["ssh"],
    "dlna": ["minidlna"],
    "media": ["minidlna", "smbd", "nmbd"],
    "adguard": ["AdGuardHome"],
}


async def _systemctl(action: str, unit: str) -> tuple[bool, str]:
    """Run `systemctl <action> <unit>` via centralized runner."""
    rc, _, stderr = await run_command(["sudo", "systemctl", action, unit], timeout=15)
    return rc == 0, stderr


@router.get("", response_model=list[ServiceInfo])
async def list_services(user: dict = Depends(get_current_user)):
    """List all configurable NAS services."""
    return [ServiceInfo(**svc) for svc in await store.get_services()]


@router.post("/{service_id}/toggle", status_code=status.HTTP_204_NO_CONTENT)
async def toggle(
    service_id: str,
    body: ToggleServiceRequest,
    user: dict = Depends(require_admin),
):
    """Enable or disable a NAS service (persists + runs systemctl)."""
    if not await store.toggle_service(service_id, body.enabled):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Service not found")

    # Run real systemctl start/stop
    units = _SERVICE_UNITS.get(service_id, [])
    action = "start" if body.enabled else "stop"

    errors: list[str] = []
    for unit in units:
        ok, err = await _systemctl(action, unit)
        if not ok:
            logger.warning("systemctl %s %s failed: %s", action, unit, err)
            errors.append(f"{unit}: {err}")

    if errors:
        # Service state was persisted, but systemctl had issues
        logger.error(
            "Service %s toggled to %s but systemctl errors: %s",
            service_id, body.enabled, "; ".join(errors),
        )
        # Don't fail the request — the store state is updated.
        # The service might not be installed yet.

    # Notify connected clients
    await emit_service_toggled(service_id, body.enabled)
