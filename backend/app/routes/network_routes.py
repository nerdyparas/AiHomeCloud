"""
Network routes — WiFi status and user toggle.
"""

import logging

from fastapi import APIRouter, Depends

from ..auth import get_current_user
from ..wifi_manager import get_wifi_status, set_user_wifi_override

logger = logging.getLogger("cubie.network")

router = APIRouter(prefix="/api/v1", tags=["network"])


@router.get("/network/wifi")
async def wifi_status(_user: dict = Depends(get_current_user)):
    """Return WiFi radio state, Ethernet link status, and user override flag."""
    return await get_wifi_status()


@router.put("/network/wifi")
async def toggle_wifi(body: dict, _user: dict = Depends(get_current_user)):
    """Toggle WiFi radio. Body: {"enabled": true/false}."""
    enabled = body.get("enabled")
    if not isinstance(enabled, bool):
        from fastapi import HTTPException, status
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "'enabled' must be a boolean")
    await set_user_wifi_override(enabled)
    return await get_wifi_status()
