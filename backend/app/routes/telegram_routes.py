"""
Telegram Bot configuration endpoints -- admin only.

GET    /api/v1/telegram/config               -- return current config (token masked) + bot status
POST   /api/v1/telegram/config               -- save token, restart bot
POST   /api/v1/telegram/setup-local-api      -- background job: build local server from source + activate 2 GB mode
DELETE /api/v1/telegram/linked/{id}          -- unlink a Telegram account
"""

import asyncio
import logging
import os
import platform
import re
import shutil
from pathlib import Path
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
    """Start a background job that builds the local Bot API server from source
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
# Background job -- local API server (build from source)
# ---------------------------------------------------------------------------

_BUILD_DIR = "/tmp/telegram-bot-api-build"  # nosec B108 -- path locked by sudoers entry
_BINARY_PATH = "/usr/local/bin/telegram-bot-api"
_SERVICE_NAME = "telegram-bot-api"
_SERVICE_PORT = 8081
_BUILD_DEPS = ["cmake", "g++", "libssl-dev", "zlib1g-dev", "gperf"]

# Prevents two concurrent invocations from clobbering the shared _BUILD_DIR.
_build_lock = asyncio.Lock()

# Pre-built binaries published as GitHub Release assets.
# The setup job tries downloading before falling back to source compilation.
_GITHUB_RELEASES_BASE = (
    "https://github.com/nerdyparas/AiHomeCloud/releases/latest/download"
)


def _arch_to_release_target() -> str | None:
    """Map the current machine architecture to the release artifact suffix.
    Returns None for unsupported architectures (caller falls back to source build).
    """
    arch = platform.machine().lower()
    mapping = {
        "x86_64": "linux-amd64",
        "aarch64": "linux-arm64",
        "arm64": "linux-arm64",    # macOS/some ARM64 kernels report 'arm64'
        "armv7l": "linux-armv7",
        "armv7": "linux-armv7",
    }
    return mapping.get(arch)


async def _try_download_prebuilt() -> tuple[bool, str]:
    """Attempt to download a pre-built telegram-bot-api binary from GitHub Releases.

    Returns (True, "") on success.
    Returns (False, reason) on failure so the caller can surface the reason to the user.
    """
    target = _arch_to_release_target()
    if target is None:
        msg = f"No pre-built binary for {platform.machine()} — compiling from source…"
        logger.info("prebuilt_skip arch=%s", platform.machine())
        return False, msg

    url = f"{_GITHUB_RELEASES_BASE}/telegram-bot-api-{target}"
    tmp_path = f"/tmp/telegram-bot-api-download-{target}"  # nosec B108

    logger.info("prebuilt_download_attempt url=%s", url)
    rc, _, err = await run_command(
        [
            "curl", "-fsSL",
            "--max-time", "120",
            "--retry", "1",  # one retry only — 404 should fail fast
            "-o", tmp_path,
            url,
        ],
        timeout=150,
    )
    if rc != 0:
        # curl exit 22 = HTTP 4xx/5xx (i.e. 404 — no release published yet)
        msg = (
            f"No pre-built binary found for {target} — "
            "compiling from source (~20–40 min)…"
        )
        logger.info("prebuilt_download_failed url=%s err=%s", url, err[:200])
        Path(tmp_path).unlink(missing_ok=True)
        return False, msg

    # Sanity check: must be an ELF binary, not an HTML error page.
    rc_file, file_out, _ = await run_command(["file", tmp_path], timeout=10)
    if rc_file != 0 or "ELF" not in file_out:
        msg = f"Downloaded file for {target} is not a valid binary — compiling from source…"
        logger.warning("prebuilt_not_elf url=%s file_output=%s", url, file_out[:200])
        Path(tmp_path).unlink(missing_ok=True)
        return False, msg

    # Install: copy to final path and make executable.
    rc, _, err = await run_command(
        ["sudo", "cp", tmp_path, _BINARY_PATH], timeout=30
    )
    Path(tmp_path).unlink(missing_ok=True)
    if rc != 0:
        msg = "Failed to install pre-built binary — compiling from source…"
        logger.warning("prebuilt_install_failed err=%s", err[:300])
        return False, msg

    rc, _, _ = await run_command(["sudo", "chmod", "755", _BINARY_PATH], timeout=10)
    logger.info("prebuilt_installed target=%s path=%s", target, _BINARY_PATH)
    return True, ""


def _cleanup_build() -> None:
    """Remove build directory."""
    try:
        build = Path(_BUILD_DIR)
        if build.exists():
            shutil.rmtree(build)
    except Exception:
        pass


async def _run_local_api_setup(job_id: str, api_id: int, api_hash: str) -> None:
    """Build telegram-bot-api from source and activate 2 GB file mode."""

    def _progress(msg: str) -> None:
        update_job(job_id, status=_JobStatus.running, result={"message": msg})

    if _build_lock.locked():
        update_job(job_id, status=_JobStatus.failed,
                   error="A build is already in progress. Please wait for it to finish.")
        return

    await _build_lock.acquire()
    try:
        # Step 1 — Check if service is already running.
        _progress("Checking for existing installation\u2026")
        rc, out, _ = await run_command(
            ["systemctl", "is-active", _SERVICE_NAME], timeout=10,
        )
        if out.strip() == "active":
            _progress("Server already running — activating 2 GB mode\u2026")
            await _activate_local_api(api_id, api_hash)
            await _send_2gb_confirmation()
            update_job(job_id, status=_JobStatus.completed,
                       result={"message": "2 GB mode activated!"})
            return

        # Step 2 — Check if binary already exists (previous build).
        binary_exists = Path(_BINARY_PATH).exists()

        if not binary_exists:
            # 2-pre — Try downloading a pre-built binary from GitHub Releases.
            # This takes seconds and avoids a 20-40 min on-device compilation.
            _progress("Checking for pre-built binary\u2026")
            downloaded, fallback_reason = await _try_download_prebuilt()
            if downloaded:
                binary_exists = True
                _progress("Pre-built binary downloaded \u2014 skipping compilation\u2026")
            else:
                _progress(fallback_reason)

        if not binary_exists:
            # 2a — Verify build dependencies are installed.
            _progress("Checking build tools\u2026")
            missing = []
            for pkg in _BUILD_DEPS:
                rc, _, _ = await run_command(["dpkg", "-s", pkg], timeout=10)
                if rc != 0:
                    missing.append(pkg)

            if missing:
                _progress(f"Installing build tools: {', '.join(missing)}\u2026")
                rc, _, err = await run_command(
                    ["sudo", "apt-get", "install", "-y", "--no-install-recommends"]
                    + missing,
                    timeout=300,
                )
                if rc != 0:
                    update_job(job_id, status=_JobStatus.failed, error=(
                        f"Could not install build tools ({', '.join(missing)}).\n\n"
                        "Run the installer to fix permissions:\n"
                        "  sudo ./install.sh\n\n"
                        f"{err[:300]}"
                    ))
                    return

            # 2b — Clone source code.
            _progress("Downloading source code\u2026")
            _cleanup_build()

            rc, _, err = await run_command(
                ["git", "clone", "--depth", "1", "--recurse-submodules",
                 "--shallow-submodules",
                 "https://github.com/tdlib/telegram-bot-api.git", _BUILD_DIR],
                timeout=600,
            )
            if rc != 0:
                update_job(job_id, status=_JobStatus.failed,
                           error=f"Failed to download source code.\n{err[:400]}")
                return

            # 2c — Configure CMake.
            _progress("Configuring build\u2026")
            build_dir = f"{_BUILD_DIR}/build"
            Path(build_dir).mkdir(parents=True, exist_ok=True)

            rc, _, err = await run_command(
                ["cmake", "-S", _BUILD_DIR, "-B", build_dir,
                 "-DCMAKE_BUILD_TYPE=Release"],
                timeout=120,
            )
            if rc != 0:
                update_job(job_id, status=_JobStatus.failed,
                           error=f"Build configuration failed.\n{err[:400]}")
                _cleanup_build()
                return

            # 2d — Compile (the long step — 20–40 min on ARM).
            _progress("Compiling \u2014 this takes 20\u201340 minutes on your device\u2026")
            rc, _, err = await run_command(
                ["cmake", "--build", build_dir,
                 "--target", "telegram-bot-api", "--parallel", "2"],
                timeout=3600,  # 60 min -- ARM builds of tdlib take 20-40 min
            )
            if rc != 0:
                update_job(job_id, status=_JobStatus.failed,
                           error=f"Compilation failed.\n{err[:400]}")
                _cleanup_build()
                return

            # 2e — Install binary.
            _progress("Installing\u2026")
            built_binary = f"{build_dir}/telegram-bot-api"
            if not Path(built_binary).exists():
                update_job(job_id, status=_JobStatus.failed,
                           error="Build succeeded but binary not found.")
                _cleanup_build()
                return

            rc, _, err = await run_command(
                ["sudo", "cp", built_binary, _BINARY_PATH],
                timeout=30,
            )
            if rc != 0:
                update_job(job_id, status=_JobStatus.failed,
                           error=f"Failed to install binary.\n{err[:300]}")
                _cleanup_build()
                return

            _cleanup_build()

        # Step 3 — Create data directory and systemd service.
        _progress("Setting up system service\u2026")
        data_dir = str(settings.data_dir / "telegram-bot-api")
        Path(data_dir).mkdir(parents=True, exist_ok=True)

        service_user = os.getenv("USER", "aihomecloud")
        service_content = (
            "[Unit]\n"
            "Description=Telegram Local Bot API Server\n"
            "After=network.target\n"
            "\n"
            "[Service]\n"
            f"User={service_user}\n"
            "Restart=always\n"
            "RestartSec=5\n"
            f"ExecStart={_BINARY_PATH}"
            f" --api-id={api_id}"
            f" --api-hash={api_hash}"
            f" --http-port={_SERVICE_PORT}"
            f" --dir={data_dir}"
            " --local\n"
            f"Environment=HOME={data_dir}\n"
            "\n"
            "[Install]\n"
            "WantedBy=multi-user.target\n"
        )

        tmp_service = Path("/tmp/telegram-bot-api.service")  # nosec B108 -- path locked by sudoers entry
        tmp_service.write_text(service_content)

        rc, _, err = await run_command(
            ["sudo", "cp", str(tmp_service),
             f"/etc/systemd/system/{_SERVICE_NAME}.service"],
            timeout=30,
        )
        tmp_service.unlink(missing_ok=True)
        if rc != 0:
            update_job(job_id, status=_JobStatus.failed,
                       error=f"Failed to create system service.\n{err[:300]}")
            return

        # Step 4 — Enable and start service.
        _progress("Starting local API server\u2026")
        await run_command(["sudo", "systemctl", "daemon-reload"], timeout=30)
        rc, _, err = await run_command(
            ["sudo", "systemctl", "enable", "--now", _SERVICE_NAME],
            timeout=30,
        )
        if rc != 0:
            # Fallback: try just starting if enable fails (sudoers might lack enable).
            rc, _, err = await run_command(
                ["sudo", "systemctl", "start", _SERVICE_NAME],
                timeout=30,
            )
            if rc != 0:
                update_job(job_id, status=_JobStatus.failed,
                           error=f"Failed to start local API server.\n{err[:300]}")
                return

        # Step 5 — Health check: up to 2 minutes for server to respond.
        _progress("Waiting for server to respond\u2026")
        healthy = False
        for _ in range(12):
            await asyncio.sleep(10)
            hc_rc, _, _ = await run_command(
                ["curl", "-sf", "--max-time", "5",
                 f"http://127.0.0.1:{_SERVICE_PORT}/"],
                timeout=15,
            )
            if hc_rc == 0:
                healthy = True
                break

        if not healthy:
            update_job(job_id, status=_JobStatus.failed, error=(
                "Local API server did not respond after 2 minutes.\n\n"
                f"Check: sudo systemctl status {_SERVICE_NAME}"
            ))
            return

        # Step 6 — Persist config and restart bot in local mode.
        _progress("Activating 2 GB mode\u2026")
        await _activate_local_api(api_id, api_hash)

        # Step 7 — Send confirmation message through the local API.
        await _send_2gb_confirmation()

        update_job(job_id, status=_JobStatus.completed,
                   result={"message": "2 GB mode activated!"})
        logger.info("local_api_setup_completed api_id=%s method=source_build", api_id)

    except Exception as exc:
        logger.error("local_api_setup_failed: %s", exc)
        update_job(job_id, status=_JobStatus.failed, error=str(exc)[:500])
        _cleanup_build()
    finally:
        _build_lock.release()


async def _send_2gb_confirmation() -> None:
    """Send a confirmation message to all linked Telegram users via the local API."""
    try:
        from .. import telegram_bot as _tb
        if _tb._application is None:
            return
        linked_ids = await _tb._get_linked_ids()
        for chat_id in linked_ids:
            try:
                await _tb._application.bot.send_message(
                    chat_id=int(chat_id),
                    text=(
                        "\u2705 *2 GB file mode is now active!*\n\n"
                        "You can now send and receive files up to 2 GB "
                        "through this bot."
                    ),
                    parse_mode="Markdown",
                )
            except Exception as exc:
                logger.warning("2GB confirmation to %s failed: %s", chat_id, exc)
    except Exception as exc:
        logger.warning("Could not send 2GB confirmation: %s", exc)


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
