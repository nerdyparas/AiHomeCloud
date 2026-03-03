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

from .config import settings, JWT_SECRET_FILE
import os
from .logging_config import configure_logging, set_request_id, reset_request_id
from .tls import ensure_tls_cert
from .routes import (
    auth_routes,
    system_routes,
    monitor_routes,
    file_routes,
    family_routes,
    service_routes,
    storage_routes,
    network_routes,
    event_routes,
)

logger = logging.getLogger("cubie.main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: ensure dirs exist, generate TLS cert, auto-remount saved storage device."""
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

    settings.data_dir.mkdir(parents=True, exist_ok=True)
    settings.personal_path.mkdir(parents=True, exist_ok=True)
    settings.shared_path.mkdir(parents=True, exist_ok=True)

    # Auto-generate self-signed TLS cert if needed
    if settings.tls_enabled:
        try:
            cert, key = ensure_tls_cert()
            logger.info("TLS enabled — cert=%s key=%s", cert, key)
        except Exception as e:
            logger.warning("TLS cert generation failed, will run without TLS: %s", e)

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

    yield


app = FastAPI(
    title="CubieCloud API",
    version="0.1.0",
    description="Backend API for the CubieCloud home NAS",
    lifespan=lifespan,
)

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
app.include_router(family_routes.router)
app.include_router(service_routes.router)
app.include_router(storage_routes.router)
app.include_router(network_routes.router)
app.include_router(event_routes.router)


@app.get("/")
async def root():
    return {"service": "CubieCloud", "version": "0.1.0"}


@app.get("/api/v1/tls/fingerprint")
async def tls_fingerprint():
    """Return the SHA-256 fingerprint of the server certificate.
    Called once by the Flutter app to pin the self-signed cert."""
    import hashlib
    try:
        cert_bytes = settings.tls_cert_path.read_bytes()
        # Parse PEM → DER for fingerprint
        from base64 import b64decode
        lines = cert_bytes.decode().splitlines()
        der_lines = []
        inside = False
        for line in lines:
            if "BEGIN CERTIFICATE" in line:
                inside = True
                continue
            if "END CERTIFICATE" in line:
                break
            if inside:
                der_lines.append(line)
        der = b64decode("".join(der_lines))
        fp = hashlib.sha256(der).hexdigest()
        return {"fingerprint": fp, "algorithm": "sha256"}
    except FileNotFoundError:
        return {"fingerprint": None, "algorithm": "sha256"}


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
            cert, key = ensure_tls_cert()
            kwargs["ssl_certfile"] = str(cert)
            kwargs["ssl_keyfile"] = str(key)
        except Exception:
            logger.warning("Starting without TLS")
    uvicorn.run(**kwargs)
