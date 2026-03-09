"""
AdGuard Home proxy routes — authenticated wrappers around AdGuard's local HTTP API.

AdGuard's admin port (3000) is never exposed to users directly. All calls go
through these endpoints, which enforce authentication and authorisation first.

Configuration (via env vars or config.py):
  CUBIE_ADGUARD_ENABLED=true   — must be True for any endpoint to work
  CUBIE_ADGUARD_PASSWORD=<pw>  — AdGuard admin password (username = "admin")

AdGuard base URL: http://localhost:3000/control/
"""

import logging
from typing import Optional

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ..auth import get_current_user, require_admin
from ..config import settings

logger = logging.getLogger("cubie.adguard")

router = APIRouter(prefix="/api/v1/adguard", tags=["adguard"])

_ADGUARD_BASE = "http://localhost:3000/control"
_TIMEOUT = 5.0  # seconds


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _require_enabled() -> None:
    """Raise 503 when AdGuard integration is disabled in config."""
    if not settings.adguard_enabled:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "AdGuard Home integration is not enabled on this device.",
        )


def _auth() -> Optional[tuple[str, str]]:
    """Return Basic-auth credentials tuple if a password is configured."""
    if settings.adguard_password:
        return ("admin", settings.adguard_password)
    return None


async def _adguard_get(path: str) -> dict:
    """Proxy a GET request to AdGuard and return the JSON body."""
    url = f"{_ADGUARD_BASE}{path}"
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.get(url, auth=_auth())
        resp.raise_for_status()
        return resp.json()
    except httpx.ConnectError:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Cannot reach AdGuard Home. Is it running?",
        )
    except httpx.HTTPStatusError as exc:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            f"AdGuard returned {exc.response.status_code}",
        )
    except Exception as exc:
        logger.error("adguard_get_error path=%s error=%s", path, exc)
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "AdGuard request failed")


async def _adguard_post(path: str, payload: dict) -> None:
    """Proxy a POST request to AdGuard (no response body expected)."""
    url = f"{_ADGUARD_BASE}{path}"
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.post(url, json=payload, auth=_auth())
        resp.raise_for_status()
    except httpx.ConnectError:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Cannot reach AdGuard Home. Is it running?",
        )
    except httpx.HTTPStatusError as exc:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            f"AdGuard returned {exc.response.status_code}",
        )
    except Exception as exc:
        logger.error("adguard_post_error path=%s error=%s", path, exc)
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "AdGuard request failed")


# ---------------------------------------------------------------------------
# Request / Response Models
# ---------------------------------------------------------------------------

class AdGuardStats(BaseModel):
    dns_queries: int = 0
    blocked_today: int = 0
    blocked_percent: float = 0.0
    top_blocked: list[str] = []


class PauseRequest(BaseModel):
    minutes: int  # expected: 5, 30, or 60


class ToggleRequest(BaseModel):
    enabled: bool


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("/stats", response_model=AdGuardStats)
async def get_stats(user: dict = Depends(get_current_user)):
    """
    Return today's DNS and blocking statistics from AdGuard Home.
    Available to any authenticated user.
    Returns 503 when AdGuard integration is disabled or unreachable.
    """
    _require_enabled()
    raw = await _adguard_get("/stats")

    dns_queries = raw.get("num_dns_queries", 0)
    blocked = raw.get("num_blocked_filtering", 0)
    percent = (blocked / dns_queries * 100.0) if dns_queries > 0 else 0.0

    # top_domains_blocked is a list of {name: str, count: int} dicts
    top_raw = raw.get("top_blocked_domains", [])
    top_blocked = [
        entry["name"] if isinstance(entry, dict) else str(entry)
        for entry in top_raw[:10]
    ]

    return AdGuardStats(
        dns_queries=dns_queries,
        blocked_today=blocked,
        blocked_percent=round(percent, 1),
        top_blocked=top_blocked,
    )


@router.post("/pause", status_code=status.HTTP_204_NO_CONTENT)
async def pause_protection(body: PauseRequest, user: dict = Depends(get_current_user)):
    """
    Pause AdGuard filtering for the requested number of minutes (5, 30, or 60).
    Available to any authenticated user.
    """
    _require_enabled()
    if body.minutes not in (5, 30, 60):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            "minutes must be 5, 30, or 60",
        )
    duration_ms = body.minutes * 60 * 1000
    await _adguard_post("/protection", {"enabled": False, "duration": duration_ms})


@router.post("/toggle", status_code=status.HTTP_204_NO_CONTENT)
async def toggle_protection(
    body: ToggleRequest,
    user: dict = Depends(require_admin),
):
    """
    Enable or disable AdGuard filtering entirely. Admin only.
    """
    _require_enabled()
    await _adguard_post("/protection", {"enabled": body.enabled})
