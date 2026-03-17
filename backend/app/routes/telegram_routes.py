"""
Telegram Bot configuration endpoints -- admin only.

GET    /api/v1/telegram/config               -- return current config (token masked) + bot status
POST   /api/v1/telegram/config               -- save token, restart bot
POST   /api/v1/telegram/setup-local-api      -- background job: install Docker local server + activate 2 GB mode
DELETE /api/v1/telegram/linked/{id}          -- unlink a Telegram account
"""

import asyncio
import logging
import re
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ..auth import require_admin
from ..config import settings
from .. import store as _store
from ..job_store import create_job, update_job, JobStatus as _JobStatus
from ..subprocess_runner import run_command

logger = logging.getLogger("aihomecloud.telegram_routes")

router = APIRouter(prefix="/api/v1/telegram", tags=["telegram"])

_STORE_KEY = "telegram_config"


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class TelegramConfigIn(BaseModel):
    bot_token: str = ""
    api_id: Optional[int] = None        # None = preserve existing
    api_hash: Optional[str] = None      # None = preserve existing
    local_api_enabled: Optional[bool] = None  # None = preserve existing


class TelegramConfigOut(BaseModel):
    configured: bool         # True if a token is saved
    token_preview: str       # e.g. "1234567:AB...xyz" (masked middle)
    linked_count: int        # number of Telegram accounts that have sent /auth
    bot_running: bool        # True if the bot process is currently polling
    local_api_enabled: bool  # True when local bot API server is active
    api_id: int              # returned so UI can show it's configured
    max_file_mb: int         # 20 when cloud API, 2000 when local


class SetupLocalApiIn(BaseModel):
    api_id: int
    api_hash: str
    bot_token: str = ""   # optional -- save/update token at same time


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _mask_token(token: str) -> str:
    """Show first 10 and last 5 chars, mask the middle."""
    if len(token) <= 15:
        return token[:3] + "\u2026" + token[-3:]
    return token[:10] + "\u2026" + token[-5:]


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
    """Save token (and optionally other fields), then restart the bot.
    Fields set to None are preserved from the existing stored config."""
    saved: dict = await _store.get_value(_STORE_KEY, default={})

    token = body.bot_token.strip()
    if not token:
        token = (saved.get("bot_token", "") or settings.telegram_bot_token).strip()
    if not token:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "bot_token must not be empty",
        )

    # Preserve existing values when caller omits a field (sends None).
    new_config = {
        "bot_token": token,
        "api_id": body.api_id if body.api_id is not None else saved.get("api_id", 0),
        "api_hash": body.api_hash if body.api_hash is not None else saved.get("api_hash", ""),
        "local_api_enabled": (
            body.local_api_enabled if body.local_api_enabled is not None
            else saved.get("local_api_enabled", False)
        ),
    }
    await _store.set_value(_STORE_KEY, new_config)

    settings.telegram_bot_token = token  # type: ignore[misc]
    if body.api_id is not None:
        settings.telegram_api_id = body.api_id  # type: ignore[misc]
    if body.api_hash is not None:
        settings.telegram_api_hash = body.api_hash  # type: ignore[misc]
    if body.local_api_enabled is not None:
        settings.telegram_local_api_enabled = body.local_api_enabled  # type: ignore[misc]

    try:
        from ..telegram_bot import stop_bot, start_bot
        await stop_bot()
        await start_bot()
        logger.info("Telegram bot restarted -- local_api=%s", new_config["local_api_enabled"])
    except Exception as exc:
        logger.warning("Telegram bot restart failed: %s", exc)


@router.post("/setup-local-api", status_code=status.HTTP_202_ACCEPTED)
async def setup_local_api(body: SetupLocalApiIn, user: dict = Depends(require_admin)):
    """Start a background job that installs the Docker-based local Bot API server
    and activates 2 GB file transfer mode.  Returns {job_id} for polling."""
    if body.api_id <= 0:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "api_id must be a positive integer",
        )
    if not re.fullmatch(r"[0-9a-fA-F]{16,64}", body.api_hash):
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "api_hash must be a hex string (16-64 characters)",
        )

    # Persist credentials immediately so they survive even if the job fails.
    saved: dict = await _store.get_value(_STORE_KEY, default={})
    token = body.bot_token.strip() or saved.get("bot_token", "") or settings.telegram_bot_token
    await _store.set_value(_STORE_KEY, {
        **saved,
        "bot_token": token,
        "api_id": body.api_id,
        "api_hash": body.api_hash,
    })
    if token:
        settings.telegram_bot_token = token  # type: ignore[misc]
    settings.telegram_api_id = body.api_id  # type: ignore[misc]
    settings.telegram_api_hash = body.api_hash  # type: ignore[misc]

    job = create_job(user_id=user.get("sub", ""))
    asyncio.create_task(
        _run_local_api_setup(job.id, body.api_id, body.api_hash),
        name=f"tg_local_api_setup_{job.id[:8]}",
    )
    return {"job_id": job.id}


# ---------------------------------------------------------------------------
# Background job -- local API server setup
# ---------------------------------------------------------------------------

async def _run_local_api_setup(job_id: str, api_id: int, api_hash: str) -> None:
    """Pull aiogram/telegram-bot-api Docker image and start it as a managed container."""

    def _progress(msg: str) -> None:
        update_job(job_id, status=_JobStatus.running, result={"message": msg})

    try:
        _progress("Checking Docker\u2026")

        # Step 1 -- Docker must be installed.
        rc, _, _ = await run_command(["which", "docker"], timeout=10)
        if rc != 0:
            update_job(job_id, status=_JobStatus.failed, error=(
                "Docker is not installed on this device.\n\n"
                "Install it with:\n"
                "  sudo apt-get install -y docker.io\n"
                "  sudo systemctl enable --now docker\n\n"
                "Then try again."
            ))
            return

        # Step 2 -- Check sudo permission for docker.
        rc2, _, derr = await run_command(
            ["sudo", "docker", "version", "--format", "{{.Server.Version}}"],
            timeout=15,
        )
        if rc2 != 0 and ("not allowed" in derr.lower() or "sudoers" in derr.lower()):
            update_job(job_id, status=_JobStatus.failed, error=(
                "The app user lacks permission to run Docker.\n\n"
                "Re-run the AiHomeCloud installer to update permissions:\n"
                "  sudo ./install.sh"
            ))
            return

        # Step 3 -- Skip pull if container is already healthy.
        _progress("Checking if local API server is already running\u2026")
        rc, out, _ = await run_command(
            ["sudo", "docker", "ps",
             "--filter", "name=telegram-bot-api",
             "--filter", "status=running",
             "--format", "{{.Names}}"],
            timeout=15,
        )
        if "telegram-bot-api" in out:
            _progress("Server already running -- activating 2 GB mode\u2026")
            await _activate_local_api(api_id, api_hash)
            update_job(job_id, status=_JobStatus.completed,
                       result={"message": "2 GB mode activated!"})
            return

        # Step 4 -- Pull image (may take a few minutes on first run).
        _progress("Pulling Docker image -- first time may take a few minutes\u2026")
        rc, _, err = await run_command(
            ["sudo", "docker", "pull", "aiogram/telegram-bot-api:latest"],
            timeout=600,
        )
        if rc != 0:
            update_job(job_id, status=_JobStatus.failed,
                       error=f"Docker image pull failed.\n{err[:400]}")
            return

        # Step 5 -- Remove any old stopped container, start a fresh one.
        _progress("Starting local API server\u2026")
        await run_command(["sudo", "docker", "rm", "-f", "telegram-bot-api"], timeout=20)

        data_dir = str(settings.data_dir / "telegram-bot-api")
        rc, _, err = await run_command(
            [
                "sudo", "docker", "run",
                "--detach",
                "--name", "telegram-bot-api",
                "--restart", "unless-stopped",
                "-p", "8081:8081",
                "-v", f"{data_dir}:/var/lib/telegram-bot-api",
                "-e", f"TELEGRAM_API_ID={api_id}",
                "-e", f"TELEGRAM_API_HASH={api_hash}",
                "aiogram/telegram-bot-api:latest",
                "--local",
            ],
            timeout=60,
        )
        if rc != 0:
            update_job(job_id, status=_JobStatus.failed,
                       error=f"Failed to start container.\n{err[:400]}")
            return

        # Step 6 -- Health check: up to 2 minutes for server to respond.
        _progress("Waiting for server to start\u2026")
        healthy = False
        for _ in range(12):
            await asyncio.sleep(10)
            hc_rc, _, _ = await run_command(
                ["curl", "-sf", "--max-time", "5", "http://127.0.0.1:8081/"],
                timeout=15,
            )
            if hc_rc == 0:
                healthy = True
                break

        if not healthy:
            update_job(job_id, status=_JobStatus.failed, error=(
                "Local API server did not respond after 2 minutes.\n\n"
                "Check logs with:\n  sudo docker logs telegram-bot-api"
            ))
            return

        # Step 7 -- Persist config and restart bot in local mode.
        _progress("Activating 2 GB mode\u2026")
        await _activate_local_api(api_id, api_hash)
        update_job(job_id, status=_JobStatus.completed,
                   result={"message": "2 GB mode activated!"})
        logger.info("local_api_setup_completed api_id=%s", api_id)

    except Exception as exc:
        logger.error("local_api_setup_failed: %s", exc)
        update_job(job_id, status=_JobStatus.failed, error=str(exc)[:500])


async def _activate_local_api(api_id: int, api_hash: str) -> None:
    """Persist local_api_enabled=True and restart the bot in local mode."""
    saved: dict = await _store.get_value(_STORE_KEY, default={})
    await _store.set_value(_STORE_KEY, {
        **saved,
        "api_id": api_id,
        "api_hash": api_hash,
        "local_api_enabled": True,
    })
    settings.telegram_api_id = api_id  # type: ignore[misc]
    settings.telegram_api_hash = api_hash  # type: ignore[misc]
    settings.telegram_local_api_enabled = True  # type: ignore[misc]
    try:
        from ..telegram_bot import stop_bot, start_bot
        await stop_bot()
        await start_bot()
    except Exception as exc:
        logger.warning("Bot restart after local API setup: %s", exc)


# ---------------------------------------------------------------------------
# Linked / pending account management
# ---------------------------------------------------------------------------

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
