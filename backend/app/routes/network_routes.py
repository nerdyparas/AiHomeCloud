"""
Network routes — WiFi status and user toggle.
"""

import logging

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from ..auth import get_current_user
from ..wifi_manager import get_wifi_status, set_user_wifi_override

logger = logging.getLogger("cubie.network")

router = APIRouter(prefix="/api/v1", tags=["network"])


@router.get("/network/wifi")
async def wifi_status(_user: dict = Depends(get_current_user)):
    """Return WiFi radio state, Ethernet link status, and user override flag."""
    return await get_wifi_status()


class WifiToggleRequest(BaseModel):
    enabled: bool


@router.put("/network/wifi")
async def toggle_wifi(body: WifiToggleRequest, _user: dict = Depends(get_current_user)):
    """Toggle WiFi radio."""
    await set_user_wifi_override(body.enabled)
    return await get_wifi_status()
