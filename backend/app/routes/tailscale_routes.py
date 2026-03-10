"""
Tailscale remote-access routes.
GET  /api/v1/system/tailscale-status  — current Tailscale IP and status
POST /api/v1/system/tailscale-up      — (admin) bring Tailscale up
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import get_current_user, require_admin
from ..subprocess_runner import run_command

logger = logging.getLogger("cubie.tailscale")

router = APIRouter(prefix="/api/v1/system", tags=["tailscale"])


async def _tailscale_ip() -> str | None:
    """Return the Tailscale IP (100.x.x.x), or None if not connected."""
    try:
        rc, stdout, _ = await run_command(["tailscale", "ip", "--4"])
        if rc != 0:
            return None
        ip = stdout.strip()
        return ip if ip else None
    except (OSError, RuntimeError):
        return None


async def _tailscale_status_text() -> str:
    """Return the one-line Tailscale backend state string."""
    try:
        rc, stdout, _ = await run_command(["tailscale", "status", "--json=false"])
        if rc != 0:
            return "not_installed"
        first_line = stdout.strip().splitlines()[:1]
        return first_line[0] if first_line else "unknown"
    except (OSError, RuntimeError):
        return "not_installed"


@router.get("/tailscale-status")
async def tailscale_status(user: dict = Depends(get_current_user)):
    """
    Return Tailscale connectivity state.

    Response:
      {
        "installed": true,
        "connected": true,
        "tailscaleIp": "100.64.0.1"
      }
    """
    ip = await _tailscale_ip()
    installed = ip != "not_installed"
    connected = ip is not None and ip != "not_installed"
    return {
        "installed": installed,
        "connected": connected,
        "tailscaleIp": ip if connected else None,
    }


@router.post("/tailscale-up", status_code=status.HTTP_202_ACCEPTED)
async def tailscale_up(user: dict = Depends(require_admin)):
    """
    Bring Tailscale up (admin only).
    Runs `tailscale up --accept-routes` and returns the assigned IP.
    """
    try:
        rc, _, stderr = await run_command(["tailscale", "up", "--accept-routes"])
        if rc != 0:
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE,
                f"tailscale up failed: {stderr}",
            )
    except (OSError, RuntimeError) as e:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            f"tailscale up failed: {e}",
        ) from e

    ip = await _tailscale_ip()
    return {
        "status": "ok",
        "tailscaleIp": ip,
    }
