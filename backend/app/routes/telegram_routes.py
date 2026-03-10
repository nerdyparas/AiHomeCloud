"""
Telegram Bot configuration endpoints — admin only.

GET  /api/v1/telegram/config  — return current config (token masked) + bot status
POST /api/v1/telegram/config  — save token + allowed IDs, restart bot
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ..auth import require_admin
from ..config import settings
from .. import store as _store

logger = logging.getLogger("cubie.telegram_routes")

router = APIRouter(prefix="/api/v1/telegram", tags=["telegram"])

_STORE_KEY = "telegram_config"


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class TelegramConfigIn(BaseModel):
    bot_token: str
    allowed_ids: str = ""   # comma-separated chat IDs; empty = no restriction


class TelegramConfigOut(BaseModel):
    configured: bool         # True if a token is saved
    token_preview: str       # e.g. "1234567:AB…xyz" (masked middle)
    allowed_ids: str
    bot_running: bool        # True if the bot process is currently polling


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _mask_token(token: str) -> str:
    """Show first 10 and last 5 chars, mask the middle."""
    if len(token) <= 15:
        return token[:3] + "…" + token[-3:]
    return token[:10] + "…" + token[-5:]


def _bot_is_running() -> bool:
    try:
        from ..telegram_bot import _application  # type: ignore[attr-defined]
        return _application is not None
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("/config", response_model=TelegramConfigOut)
async def get_config(user: dict = Depends(require_admin)):
    """Return current Telegram bot config (token masked) and running status."""
    saved: dict = await _store.get_value(_STORE_KEY, default={})
    token = saved.get("bot_token", "") or settings.telegram_bot_token
    allowed = saved.get("allowed_ids", "") or settings.telegram_allowed_ids

    return TelegramConfigOut(
        configured=bool(token),
        token_preview=_mask_token(token) if token else "",
        allowed_ids=allowed,
        bot_running=_bot_is_running(),
    )


@router.post("/config", status_code=status.HTTP_204_NO_CONTENT)
async def save_config(body: TelegramConfigIn, user: dict = Depends(require_admin)):
    """Save token + allowed IDs, then restart the bot."""
    token = body.bot_token.strip()
    allowed = body.allowed_ids.strip()

    if not token:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "bot_token must not be empty",
        )

    # Persist to store so it survives restarts
    await _store.set_value(_STORE_KEY, {"bot_token": token, "allowed_ids": allowed})

    # Also update runtime settings so the bot picks up the new values immediately
    settings.telegram_bot_token = token      # type: ignore[misc]
    settings.telegram_allowed_ids = allowed  # type: ignore[misc]

    # Restart bot
    try:
        from ..telegram_bot import stop_bot, start_bot
        await stop_bot()
        await start_bot()
        logger.info("Telegram bot restarted via API config save")
    except Exception as exc:
        logger.warning("Telegram bot restart failed: %s", exc)
        # Don't fail the request — config is saved, user can retry
