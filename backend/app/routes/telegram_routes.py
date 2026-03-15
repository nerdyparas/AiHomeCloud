"""
Telegram Bot configuration endpoints â€” admin only.

GET    /api/v1/telegram/config         â€” return current config (token masked) + bot status
POST   /api/v1/telegram/config         â€” save token, restart bot
DELETE /api/v1/telegram/linked/{id}    â€” unlink a Telegram account
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ..auth import require_admin
from ..config import settings
from .. import store as _store

logger = logging.getLogger("aihomecloud.telegram_routes")

router = APIRouter(prefix="/api/v1/telegram", tags=["telegram"])

_STORE_KEY = "telegram_config"


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class TelegramConfigIn(BaseModel):
    bot_token: str = ""
    api_id: int = 0
    api_hash: str = ""
    local_api_enabled: bool = False


class TelegramConfigOut(BaseModel):
    configured: bool         # True if a token is saved
    token_preview: str       # e.g. "1234567:ABâ€¦xyz" (masked middle)
    linked_count: int        # number of Telegram accounts that have sent /auth
    bot_running: bool        # True if the bot process is currently polling
    local_api_enabled: bool  # True when local bot API server is active
    api_id: int              # returned so UI can show it's configured
    max_file_mb: int         # 20 when cloud API, 2000 when local


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _mask_token(token: str) -> str:
    """Show first 10 and last 5 chars, mask the middle."""
    if len(token) <= 15:
        return token[:3] + "â€¦" + token[-3:]
    return token[:10] + "â€¦" + token[-5:]


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
    linked_ids = await _store.get_value("telegram_linked_ids", default=[])
    local_enabled = bool(saved.get("local_api_enabled", settings.telegram_local_api_enabled))
    api_id = int(saved.get("api_id", settings.telegram_api_id) or 0)

    return TelegramConfigOut(
        configured=bool(token),
        token_preview=_mask_token(token) if token else "",
        linked_count=len(linked_ids),
        bot_running=_bot_is_running(),
        local_api_enabled=local_enabled,
        api_id=api_id,
        max_file_mb=2000 if local_enabled else 20,
    )


@router.post("/config", status_code=status.HTTP_204_NO_CONTENT)
async def save_config(body: TelegramConfigIn, user: dict = Depends(require_admin)):
    """Save token, then restart the bot."""
    token = body.bot_token.strip()
    if not token:
        saved: dict = await _store.get_value(_STORE_KEY, default={})
        token = (saved.get("bot_token", "") or settings.telegram_bot_token).strip()

    if not token:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "bot_token must not be empty",
        )

    await _store.set_value(_STORE_KEY, {
        "bot_token": token,
        "api_id": body.api_id,
        "api_hash": body.api_hash,
        "local_api_enabled": body.local_api_enabled,
    })

    # Update runtime settings so the bot picks up the new values immediately
    settings.telegram_bot_token = token                                # type: ignore[misc]
    settings.telegram_api_id = body.api_id                             # type: ignore[misc]
    settings.telegram_api_hash = body.api_hash                         # type: ignore[misc]
    settings.telegram_local_api_enabled = body.local_api_enabled       # type: ignore[misc]

    # Restart bot
    try:
        from ..telegram_bot import stop_bot, start_bot
        await stop_bot()
        await start_bot()
        logger.info("Telegram bot restarted â€” local_api=%s", body.local_api_enabled)
    except Exception as exc:
        logger.warning("Telegram bot restart failed: %s", exc)


@router.delete("/linked/{chat_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unlink_account(chat_id: int, user: dict = Depends(require_admin)):
    """Unlink a Telegram account (admin only)."""
    ids = await _store.get_value("telegram_linked_ids", default=[])
    ids = [i for i in ids if int(i) != chat_id]
    await _store.set_value("telegram_linked_ids", ids)


@router.get("/pending")
async def get_pending_approvals(user: dict = Depends(require_admin)):
    """Return list of pending Telegram auth requests (admin only)."""
    return await _store.get_value("telegram_pending_approvals", default=[])


@router.post("/pending/{chat_id}/approve", status_code=status.HTTP_204_NO_CONTENT)
async def approve_telegram_request(chat_id: int, user: dict = Depends(require_admin)):
    """Approve a pending Telegram auth request (admin only)."""
    try:
        from ..telegram_bot import _add_linked_id, _remove_pending_approval, _resolve_personal_owner, _set_chat_folder_owner, _get_pending_approvals, _application  # type: ignore[attr-defined]
        pendings   = await _get_pending_approvals()
        info       = next((p for p in pendings if p["chat_id"] == chat_id), {})
        first_name = info.get("first_name", "User")
        await _add_linked_id(chat_id)
        owner = await _resolve_personal_owner(chat_id, first_name)
        await _set_chat_folder_owner(chat_id, owner)
        await _remove_pending_approval(chat_id)
        if _application is not None:
            from contextlib import suppress
            with suppress(Exception):
                await _application.bot.send_message(
                    chat_id=chat_id,
                    text=(
                        f"\u2705 <b>Access approved! Welcome, {first_name}.</b>\n\n"
                        f"\U0001f464 Personal folder: <b>{owner}</b>\n\n"
                        "/help to see available commands."
                    ),
                    parse_mode="HTML",
                )
    except ImportError:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Telegram bot not available")


@router.post("/pending/{chat_id}/deny", status_code=status.HTTP_204_NO_CONTENT)
async def deny_telegram_request(chat_id: int, user: dict = Depends(require_admin)):
    """Deny a pending Telegram auth request (admin only)."""
    try:
        from ..telegram_bot import _remove_pending_approval, _application  # type: ignore[attr-defined]
        await _remove_pending_approval(chat_id)
        if _application is not None:
            from contextlib import suppress
            with suppress(Exception):
                await _application.bot.send_message(
                    chat_id=chat_id,
                    text="\u274c <b>Access denied.</b>\n\nContact the device owner to request access.",
                    parse_mode="HTML",
                )
    except ImportError:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Telegram bot not available")
