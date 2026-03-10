"""
CubieCloud Backend — FastAPI application.
Run with: python -m app.main (auto-configures TLS)
"""

import logging
import ssl
from contextlib import asynccontextmanager
from pathlib import Path
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
from .logging_config import configure_logging, set_request_id, reset_request_id
from .tls import ensure_tls_cert
from .auto_ap import maybe_start_auto_ap, shutdown_auto_ap
from .board import detect_board
from .routes import (
    adguard_routes,
    auth_routes,
    system_routes,
    monitor_routes,
    file_routes,
    jobs_routes,
    family_routes,
    service_routes,
    storage_routes,
    network_routes,
    event_routes,
    telegram_routes,
)

logger = logging.getLogger("cubie.main")


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
    settings.shared_path.mkdir(parents=True, exist_ok=True)
    # Ensure shared .inbox/ exists for auto-sorting of shared-folder uploads
    (settings.shared_path / ".inbox").mkdir(exist_ok=True)

    # Auto-generate self-signed TLS cert if needed
    if settings.tls_enabled:
        try:
            cert, key = await ensure_tls_cert()
            logger.info("TLS enabled — cert=%s key=%s", cert, key)
        except Exception as e:
            logger.warning("TLS cert generation failed, running without TLS: %s", e)
            settings.tls_enabled = False

    logger.info("CubieCloud backend starting on %s:%s", settings.host, settings.port)
    logger.info("  NAS root : %s", settings.nas_root)
    logger.info("  Data dir : %s", settings.data_dir)
    logger.info("  TLS      : %s", 'enabled' if settings.tls_enabled else 'disabled')
    logger.info("CORS origins configured: %s", settings.cors_origins)

    # Log JWT secret provenance without revealing the secret value
    try:
        if JWT_SECRET_FILE.exists():
            logger.info("JWT secret loaded from %s", JWT_SECRET_FILE)
        elif os.getenv("CUBIE_JWT_SECRET"):
            logger.info("JWT secret provided via environment variable")
        else:
            logger.info("JWT secret: using default placeholder (insecure)")
    except Exception:
        logger.debug("Unable to check JWT secret file existence")

    # Auto-remount previously-mounted storage device
    try:
        await storage_routes.try_auto_remount()
    except Exception as e:
        logger.error("Auto-remount failed: %s", e)

    # Purge old refresh tokens (cleanup tokens.json) older than 30 days past expiry
    try:
        from . import store as _store_module
        from datetime import datetime, timedelta

        cutoff = int((datetime.now(timezone.utc) - timedelta(days=30)).timestamp())
        removed = await _store_module.purge_expired_tokens(cutoff)
        if removed:
            logger.info("Purged %d expired refresh tokens", removed)
    except Exception:
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
    except Exception:
        logger.debug("Pairing OTP cleanup skipped or failed")

    # Migrate any plaintext PINs from early development
    try:
        from .auth import migrate_plaintext_pins
        migrated = await migrate_plaintext_pins()
        if migrated:
            logger.info("Startup PIN migration: hashed %d plaintext PIN(s)", migrated)
    except Exception as e:
        logger.error("PIN migration failed: %s", e)

    # Auto-AP: start hotspot if no network is available
    try:
        await maybe_start_auto_ap()
    except Exception as e:
        logger.error("Auto-AP startup failed: %s", e)

    # Initialise document search index (FTS5)
    try:
        from .document_index import init_db as _init_doc_db
        await _init_doc_db()
    except Exception as e:
        logger.error("document_index init failed: %s", e)

    # Start InboxWatcher for auto-sorting uploaded files
    try:
        from .file_sorter import get_watcher as _get_watcher
        _get_watcher().start()
    except Exception as e:
        logger.error("InboxWatcher startup failed: %s", e)

    # Start Telegram bot (optional — skipped if token not set)
    try:
        from .telegram_bot import start_bot as _start_bot
        await _start_bot()
    except Exception as e:
        logger.error("Telegram bot startup failed: %s", e)

    yield

    # Stop Telegram bot
    try:
        from .telegram_bot import stop_bot as _stop_bot
        await _stop_bot()
    except Exception:
        logger.debug("Telegram bot shutdown skipped")

    # Stop InboxWatcher
    try:
        from .file_sorter import get_watcher as _get_watcher
        await _get_watcher().stop()
    except Exception:
        logger.debug("InboxWatcher shutdown skipped")

    # Shutdown: cancel Auto-AP background monitor
    try:
        await shutdown_auto_ap()
    except Exception:
        logger.debug("Auto-AP shutdown cleanup skipped")


app = FastAPI(
    title="CubieCloud API",
    version="0.1.0",
    description="Backend API for the CubieCloud home NAS",
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
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    request_id = uuid4().hex
    request.state.request_id = request_id
    token = set_request_id(request_id)

    logger.info(
        "request_start",
        extra={"method": request.method, "path": request.url.path},
    )
    try:
        response = await call_next(request)
        logger.info(
            "request_end",
            extra={
                "method": request.method,
                "path": request.url.path,
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
app.include_router(jobs_routes.router)
app.include_router(family_routes.router)
app.include_router(service_routes.router)
app.include_router(storage_routes.router)
app.include_router(network_routes.router)
app.include_router(event_routes.router)
app.include_router(adguard_routes.router)
app.include_router(telegram_routes.router)


@app.get("/api/health")
async def health():
    """Health check — unversioned, always available."""
    return {"status": "ok"}


@app.get("/")
async def root():
    return {
        "service": "CubieCloud",
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
        import asyncio
        try:
            cert, key = asyncio.get_event_loop().run_until_complete(ensure_tls_cert())
            kwargs["ssl_certfile"] = str(cert)
            kwargs["ssl_keyfile"] = str(key)
        except Exception:
            logger.warning("Starting without TLS")
    uvicorn.run(**kwargs)
