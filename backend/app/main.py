"""
CubieCloud Backend — FastAPI application.
Run with: uvicorn app.main:app --host 0.0.0.0 --port 8443
"""

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .routes import (
    auth_routes,
    system_routes,
    monitor_routes,
    file_routes,
    family_routes,
    service_routes,
    storage_routes,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: ensure required directories exist."""
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    settings.personal_path.mkdir(parents=True, exist_ok=True)
    settings.shared_path.mkdir(parents=True, exist_ok=True)
    print(f"CubieCloud backend starting on {settings.host}:{settings.port}")
    print(f"  NAS root : {settings.nas_root}")
    print(f"  Data dir : {settings.data_dir}")
    yield


app = FastAPI(
    title="CubieCloud API",
    version="0.1.0",
    description="Backend API for the CubieCloud home NAS",
    lifespan=lifespan,
)

# Allow the Flutter app to connect from any origin during development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register all routers
app.include_router(auth_routes.router)
app.include_router(system_routes.router)
app.include_router(monitor_routes.router)
app.include_router(file_routes.router)
app.include_router(family_routes.router)
app.include_router(service_routes.router)
app.include_router(storage_routes.router)


@app.get("/")
async def root():
    return {"service": "CubieCloud", "version": "0.1.0"}
