"""
AiHomeCloud Backend — FastAPI application.
Run with: python -m app.main (auto-configures TLS)
"""

import asyncio
import logging
import tempfile
from contextlib import asynccontextmanager, suppress
from uuid import uuid4

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from .config import settings, JWT_SECRET_FILE
from .limiter import limiter
import os  # noqa: E402 — used for env var check below

# Starlette buffers uploaded files through SpooledTemporaryFile -> tempdir.
# /tmp is a 1.9 GB tmpfs on this device — large files (>1.9 GB) would overflow it
# and produce a misleading "There was an error parsing the body" 422 error.
# Redirect to eMMC /var/tmp which has ~50 GB free.
_AHC_UPLOAD_TMP = "/var/tmp/ahc_uploads"  # nosec B108 — intentional: eMMC path, not world-writable /tmp
os.makedirs(_AHC_UPLOAD_TMP, exist_ok=True)
tempfile.tempdir = _AHC_UPLOAD_TMP
from .logging_config import configure_logging, set_request_id, reset_request_id
from .tls import ensure_tls_cert
from .board import detect_board
from .routes import (
    auth_routes,
    system_routes,
    monitor_routes,
    file_routes,
    trash_routes,
    jobs_routes,
    family_routes,
    service_routes,
    storage_routes,
    event_routes,
    network_routes,
    telegram_routes,
    telegram_upload_routes,
    backup_routes,
    web_upload_routes,
    web_browser_routes,
)

from datetime import datetime, timedelta

logger = logging.getLogger("aihomecloud.main")

_BOT_BACKOFF_SCHEDULE = [5, 10, 30, 60, 60]  # seconds between restart attempts
_BOT_MAX_RESTARTS = 5


async def _run_nightly_duplicate_scan() -> None:
    """Sleep until 4:00 AM then run the duplicate scanner (exact + similar), repeat daily."""
    while True:
        try:
            now = datetime.now()
            target = now.replace(hour=4, minute=0, second=0, microsecond=0)
            if target <= now:
                target += timedelta(days=1)
            await asyncio.sleep((target - now).total_seconds())
            from .duplicate_scanner import get_duplicate_scanner
            await get_duplicate_scanner()._scan_nas_for_duplicates()
            logger.info("Nightly duplicate scan complete (exact + similar)")
        except asyncio.CancelledError:
            break
        except Exception as exc:
            logger.error("Nightly duplicate scan failed: %s", exc)


async def _send_evening_duplicate_report() -> None:
    """Sleep until 6:00 PM then send the Telegram duplicate report, repeat daily."""
    while True:
        try:
            now = datetime.now()
            target = now.replace(hour=18, minute=0, second=0, microsecond=0)
            if target <= now:
                target += timedelta(days=1)
            await asyncio.sleep((target - now).total_seconds())

            from . import store as _store_mod
            exact = await _store_mod.get_value("duplicate_scan_results", default=[])
            similar = await _store_mod.get_value("similar_scan_results", default=[])
            if not exact and not similar:
                continue

            from .duplicate_scanner import get_duplicate_scanner
            msg = get_duplicate_scanner()._format_telegram_report(exact, similar)
            if msg is None:
                continue

            from . import telegram_bot as _tb_mod
            from .telegram.bot_core import _get_linked_ids
            if _tb_mod._application is not None:
                linked = await _get_linked_ids()
                for chat_id in linked:
                    with suppress(Exception):
                        await _tb_mod._application.bot.send_message(
                            chat_id=chat_id, text=msg, parse_mode="HTML"
                        )
            logger.info("Evening duplicate report sent to %d user(s)", len(linked) if _tb_mod._application is not None else 0)
        except asyncio.CancelledError:
            break
        except Exception as exc:
            logger.error("Evening duplicate report failed: %s", exc)


async def _supervise_telegram_bot() -> None:
    """Watch the Telegram bot task and restart on crash with exponential backoff."""
    from .telegram_bot import start_bot as _start_bot
    from .config import settings as _settings

    if not _settings.telegram_bot_token:
        return  # bot not configured, nothing to supervise

    attempt = 0
    while True:
        await asyncio.sleep(10)  # flat health-check poll interval

        from . import telegram_bot as _tb_mod
        if _tb_mod._application is not None:
            # Bot is healthy — reset counter and continue polling
            attempt = 0
            continue

        # Bot is down — apply backoff before attempting restart
        attempt += 1
        if attempt > _BOT_MAX_RESTARTS:
            logger.error(
                "Telegram bot supervisor giving up after %d restart attempts",
                _BOT_MAX_RESTARTS,
            )
            return

        delay = _BOT_BACKOFF_SCHEDULE[min(attempt - 1, len(_BOT_BACKOFF_SCHEDULE) - 1)]
        logger.warning(
            "Telegram bot down — restart attempt %d/%d, waiting %ds",
            attempt, _BOT_MAX_RESTARTS, delay,
        )
        await asyncio.sleep(delay)

        try:
            await _start_bot()
            if _tb_mod._application is not None:
                logger.info("Telegram bot recovered after %d attempt(s)", attempt)
                attempt = 0
        except Exception as exc:
            logger.error("Telegram bot restart failed: %s", exc)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: ensure dirs exist, generate TLS cert, detect board, auto-remount saved storage device."""
    # Configure logging before any startup log lines.
    configure_logging(settings.log_level)

    logger.info(
        "backend_start",
        extra={
            "version": "0.1",
            "data_dir": str(settings.data_dir),
            "nas_root": str(settings.nas_root),
            "port": settings.port,
        },
    )

    # Detect board configuration and store in app state
    app.state.board = detect_board()

    settings.data_dir.mkdir(parents=True, exist_ok=True)
    settings.personal_path.mkdir(parents=True, exist_ok=True)
    settings.family_path.mkdir(parents=True, exist_ok=True)
    settings.entertainment_path.mkdir(parents=True, exist_ok=True)
    # Ensure family .inbox/ exists for auto-sorting of shared-folder uploads
    (settings.family_path / ".inbox").mkdir(exist_ok=True)

    # One-time migration: shared/ → family/ and entertainment/
    import shutil as _shutil
    old_shared = settings.nas_root / "shared"
    new_family = settings.family_path
    old_entertainment = old_shared / "Entertainment"
    new_entertainment = settings.entertainment_path

    if old_shared.exists() and not new_family.exists():
        logger.info("Migrating shared/ → family/ and entertainment/")
        try:
            if old_entertainment.exists():
                new_entertainment.mkdir(parents=True, exist_ok=True)
                for item in old_entertainment.iterdir():
                    _shutil.move(str(item), str(new_entertainment / item.name))
                old_entertainment.rmdir()
            _shutil.move(str(old_shared), str(new_family))
            logger.info("Migration complete: shared/ → family/")
        except (OSError, _shutil.Error) as e:
            logger.error("Migration failed: %s", e)

    # Auto-generate self-signed TLS cert if needed
    if settings.tls_enabled:
        try:
            cert, key = await ensure_tls_cert()
            logger.info("TLS enabled — cert=%s key=%s", cert, key)
        except (OSError, RuntimeError, ValueError) as e:
            logger.warning("TLS cert generation failed, running without TLS: %s", e)
            settings.tls_enabled = False

    logger.info("AiHomeCloud backend starting on %s:%s", settings.host, settings.port)
    logger.info("  NAS root : %s", settings.nas_root)
    logger.info("  Data dir : %s", settings.data_dir)
    logger.info("  TLS      : %s", 'enabled' if settings.tls_enabled else 'disabled')
    logger.info("CORS origins configured: %s", settings.cors_origins)

    # Log JWT secret provenance without revealing the secret value
    try:
        if JWT_SECRET_FILE.exists():
            logger.info("JWT secret loaded from %s", JWT_SECRET_FILE)
        elif os.getenv("AHC_JWT_SECRET"):
            logger.info("JWT secret provided via environment variable")
        else:
            logger.info("JWT secret: using default placeholder (insecure)")
    except OSError:
        logger.debug("Unable to check JWT secret file existence")

    # Auto-remount previously-mounted storage device
    try:
        await storage_routes.try_auto_remount()
    except (OSError, RuntimeError, ValueError) as e:
        logger.error("Auto-remount failed: %s", e)

    # Ensure DLNA is on by default at backend startup (if service is installed).
    try:
        from .routes.storage_helpers import ensure_dlna_started_and_enabled

        await ensure_dlna_started_and_enabled()
    except (OSError, RuntimeError, ValueError) as e:
        logger.warning("DLNA startup ensure failed: %s", e)

    # Purge old refresh tokens (cleanup tokens.json) older than 30 days past expiry
    try:
        from . import store as _store_module
        from datetime import datetime, timedelta, timezone

        cutoff = int((datetime.now(timezone.utc) - timedelta(days=30)).timestamp())
        removed = await _store_module.purge_expired_tokens(cutoff)
        if removed:
            logger.info("Purged %d expired refresh tokens", removed)
    except (OSError, ValueError):
        logger.debug("Token purge skipped or failed")

    # Clear expired pairing OTPs on startup
    try:
        from . import store as _store_module
        from datetime import datetime, timezone

        otp = await _store_module.get_otp()
        if otp and otp.get("expires_at"):
            if int(otp.get("expires_at", 0)) < int(datetime.now(timezone.utc).timestamp()):
                await _store_module.clear_otp()
                logger.info("Cleared expired pairing OTP on startup")
    except (OSError, ValueError):
        logger.debug("Pairing OTP cleanup skipped or failed")

    # Initialise document search index (FTS5)
    try:
        from .document_index import init_db as _init_doc_db
        await _init_doc_db()
    except (OSError, RuntimeError, ValueError) as e:
        logger.error("document_index init failed: %s", e)

    # Startup hygiene: remove known backend test artifacts from user storage/index.
    try:
        from .hygiene import cleanup_startup_artifacts as _cleanup_startup_artifacts

        stats = await _cleanup_startup_artifacts()
        if any(stats.values()):
            logger.info("Startup hygiene cleanup completed: %s", stats)
    except (OSError, RuntimeError, ValueError) as e:
        logger.warning("Startup hygiene cleanup failed: %s", e)

    # Start InboxWatcher for auto-sorting uploaded files (opt-in via AHC_AUTO_SORT_ENABLED)
    if settings.auto_sort_enabled:
        try:
            from .file_sorter import get_watcher as _get_watcher
            _get_watcher().start()
        except (OSError, RuntimeError, ValueError) as e:
            logger.error("InboxWatcher startup failed: %s", e)
    else:
        logger.info("InboxWatcher disabled — set AHC_AUTO_SORT_ENABLED=true to enable")

    # Start document index watcher for out-of-band file changes.
    try:
        from .index_watcher import get_index_watcher as _get_index_watcher
        _get_index_watcher().start()
    except (OSError, RuntimeError, ValueError) as e:
        logger.error("DocumentIndexWatcher startup failed: %s", e)

    # Start Telegram bot (optional — skipped if token not set)
    try:
        # Restore Telegram runtime settings from persisted config.
        saved_tg = await _store_module.get_value("telegram_config", default={})
        if isinstance(saved_tg, dict) and saved_tg:
            token = str(saved_tg.get("bot_token", "") or "").strip()
            if token:
                settings.telegram_bot_token = token  # type: ignore[misc]

            api_id = int(saved_tg.get("api_id", 0) or 0)
            api_hash = str(saved_tg.get("api_hash", "") or "")
            local_enabled = bool(saved_tg.get("local_api_enabled", False))

            settings.telegram_api_id = api_id  # type: ignore[misc]
            settings.telegram_api_hash = api_hash  # type: ignore[misc]
            settings.telegram_local_api_enabled = local_enabled  # type: ignore[misc]

        from .telegram_bot import start_bot as _start_bot
        await _start_bot()
    except (OSError, RuntimeError, ValueError) as e:
        logger.error("Telegram bot startup failed: %s", e)

    # Launch Telegram bot supervisor (restarts on crash with exponential backoff)
    app.state.bot_supervisor_task = asyncio.create_task(
        _supervise_telegram_bot(), name="telegram_bot_supervisor"
    )

    # Nightly duplicate scan at 2:00 AM + evening Telegram report at 6:00 PM
    app.state.dup_scan_task = asyncio.create_task(
        _run_nightly_duplicate_scan(), name="duplicate_scan_nightly"
    )
    app.state.dup_report_task = asyncio.create_task(
        _send_evening_duplicate_report(), name="duplicate_report_evening"
    )

    # Auto-disable WiFi if Ethernet is active, then start periodic re-check
    try:
        from .wifi_manager import auto_disable_wifi_if_ethernet, start_wifi_monitor
        await auto_disable_wifi_if_ethernet()
        start_wifi_monitor()
    except (OSError, RuntimeError, ValueError) as e:
        logger.warning("WiFi auto-disable check failed: %s", e)

    yield

    # Cancel scheduled tasks
    for task_attr in ("bot_supervisor_task", "dup_scan_task", "dup_report_task"):
        task = getattr(app.state, task_attr, None)
        if task and not task.done():
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task

    # Stop Telegram bot
    try:
        from .telegram_bot import stop_bot as _stop_bot
        await _stop_bot()
    except (OSError, RuntimeError, ValueError):
        logger.debug("Telegram bot shutdown skipped")

    # Stop InboxWatcher (only if it was started)
    if settings.auto_sort_enabled:
        try:
            from .file_sorter import get_watcher as _get_watcher
            await _get_watcher().stop()
        except (OSError, RuntimeError, ValueError):
            logger.debug("InboxWatcher shutdown skipped")

    # Stop document index watcher
    try:
        from .index_watcher import get_index_watcher as _get_index_watcher
        await _get_index_watcher().stop()
    except (OSError, RuntimeError, ValueError):
        logger.debug("DocumentIndexWatcher shutdown skipped")

    # Stop WiFi monitor
    try:
        from .wifi_manager import stop_wifi_monitor
        await stop_wifi_monitor()
    except (OSError, RuntimeError, ValueError):
        logger.debug("WiFi monitor stop skipped")

    # Close document index connection pool
    try:
        from .document_index import close_db as _close_doc_db
        await _close_doc_db()
    except (OSError, RuntimeError, ValueError):
        logger.debug("Document index pool close skipped")


app = FastAPI(
    title="AiHomeCloud API",
    version="0.1.0",
    description="Backend API for the AiHomeCloud home NAS",
    lifespan=lifespan,
)

# Rate limiting (slowapi)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Restrict CORS to configured origins.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
)

# Security response headers middleware
@app.middleware("http")
async def security_headers_middleware(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "0"
    if settings.tls_enabled:
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    # Prevent caching of auth responses
    if request.url.path.startswith("/api/v1/auth") or request.url.path.startswith("/api/v1/login"):
        response.headers["Cache-Control"] = "no-store"
    return response

# Paths called very frequently — skip per-request logging to reduce overhead.
_QUIET_PATHS = frozenset({
    "/api/v1/files/list",
    "/api/v1/files/download",
    "/api/v1/files/upload",
    "/api/v1/monitor/ws",
    "/api/health",
})


@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    request_id = uuid4().hex
    request.state.request_id = request_id
    token = set_request_id(request_id)

    path = request.url.path
    verbose = path not in _QUIET_PATHS

    if verbose:
        logger.info(
            "request_start",
            extra={"method": request.method, "path": path},
        )
    try:
        response = await call_next(request)
        if verbose or response.status_code >= 400:
            logger.info(
                "request_end",
                extra={
                    "method": request.method,
                    "path": path,
                    "status_code": response.status_code,
                },
            )
        return response
    finally:
        reset_request_id(token)

# Register all routers
app.include_router(auth_routes.router)
app.include_router(system_routes.router)
app.include_router(monitor_routes.router)
app.include_router(file_routes.router)
app.include_router(trash_routes.router)
app.include_router(jobs_routes.router)
app.include_router(family_routes.router)
app.include_router(service_routes.router)
app.include_router(storage_routes.router)
app.include_router(event_routes.router)
app.include_router(network_routes.router)
app.include_router(telegram_routes.router)
app.include_router(telegram_upload_routes.router)
app.include_router(backup_routes.router)
app.include_router(web_upload_routes.router)
app.include_router(web_browser_routes.router)


@app.get("/api/health")
async def health():
    """Health check — unversioned, always available."""
    return {"status": "ok"}


@app.get("/")
async def root():
    return {
        "service": "AiHomeCloud",
        "version": "0.1.0",
        "deviceName": settings.device_name,
        "serial": settings.device_serial,
    }


# Backward-compatible redirect: /api/... -> /api/v1/...
@app.api_route("/api/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"])
async def redirect_api(path: str, request: Request):
    target = f"/api/v1/{path}"
    # Preserve method semantics with 308 Permanent Redirect
    return RedirectResponse(url=target, status_code=308)


# ── Entry point for python -m app.main ──────────────────────────────────────

if __name__ == "__main__":
    kwargs = {
        "app": "app.main:app",
        "host": settings.host,
        "port": settings.port,
        "log_level": "info",
    }
    if settings.tls_enabled:
        try:
            cert, key = asyncio.run(ensure_tls_cert())
            kwargs["ssl_certfile"] = str(cert)
            kwargs["ssl_keyfile"] = str(key)
        except (OSError, RuntimeError, ValueError):
            logger.warning("Starting without TLS")
    uvicorn.run(**kwargs)
