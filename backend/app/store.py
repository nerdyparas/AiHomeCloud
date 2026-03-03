"""
JSON-file-based persistence for users, services config, and device state.
Designed for simplicity on a single-device NAS — no database needed.
"""

from __future__ import annotations

import json
import uuid
from pathlib import Path
import asyncio
from typing import Any, Dict, List, Optional
import os
import tempfile

from .config import settings


# Async lock to protect concurrent access to JSON files from async handlers
_store_lock = asyncio.Lock()


def _read_json(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default if default is not None else {}
    return json.loads(path.read_text())


def _atomic_write(path: Path, data: Any) -> None:
    """Write JSON to `path` atomically by writing to a temp file then moving it.

    This prevents partially-written JSON files on crash/power-loss.
    """
    path.parent.mkdir(parents=True, exist_ok=True)

    # Use the same directory to ensure os.replace is atomic on the same filesystem.
    fd, tmp_path = tempfile.mkstemp(prefix=path.name, dir=str(path.parent))
    try:
        # Write bytes to fd, flush and fsync to ensure durability.
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(json.dumps(data, indent=2))
            f.flush()
            os.fsync(f.fileno())

        # Atomically replace target
        os.replace(tmp_path, str(path))
    except Exception:
        # Best-effort cleanup on error
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
        raise


def _write_json(path: Path, data: Any) -> None:
    _atomic_write(path, data)


# ─── Users ────────────────────────────────────────────────────────────────────

async def get_users() -> List[dict]:
    """Return the list of users, protected by the store lock."""
    async with _store_lock:
        return _read_json(settings.users_file, [])


async def save_users(users: List[dict]) -> None:
    """Persist users to disk using an async lock to prevent concurrent writes."""
    async with _store_lock:
        _write_json(settings.users_file, users)


async def find_user(user_id: str) -> Optional[dict]:
    users = await get_users()
    return next((u for u in users if u["id"] == user_id), None)


async def add_user(name: str, pin: Optional[str] = None, is_admin: bool = False) -> dict:
    users = await get_users()
    user = {
        "id": f"user_{uuid.uuid4().hex[:8]}",
        "name": name,
        "pin": pin,
        "is_admin": is_admin,
    }
    users.append(user)
    await save_users(users)

    # Create personal folder
    personal = settings.personal_path / name
    personal.mkdir(parents=True, exist_ok=True)

    return user


async def remove_user(user_id: str) -> bool:
    users = await get_users()
    filtered = [u for u in users if u["id"] != user_id]
    if len(filtered) == len(users):
        return False
    await save_users(filtered)
    return True


async def update_user_pin(user_id: str, new_pin: str) -> bool:
    users = await get_users()
    for u in users:
        if u["id"] == user_id:
            u["pin"] = new_pin
            await save_users(users)
            return True
    return False


# ─── Services ─────────────────────────────────────────────────────────────────

_DEFAULT_SERVICES = [
    {
        "id": "samba",
        "name": "Samba (SMB)",
        "description": "Windows file sharing",
        "isEnabled": True,
    },
    {
        "id": "nfs",
        "name": "NFS",
        "description": "Linux / Mac network filesystem",
        "isEnabled": False,
    },
    {
        "id": "ssh",
        "name": "SSH",
        "description": "Secure remote terminal",
        "isEnabled": True,
    },
    {
        "id": "dlna",
        "name": "DLNA",
        "description": "Media streaming to smart TVs",
        "isEnabled": True,
    },
]


async def get_services() -> List[dict]:
    """Return services list, creating defaults if missing."""
    async with _store_lock:
        services = _read_json(settings.services_file, None)
        if services is None:
            _write_json(settings.services_file, _DEFAULT_SERVICES)
            return _DEFAULT_SERVICES
        return services


async def save_services(services: List[dict]) -> None:
    """Persist services list to disk under lock."""
    async with _store_lock:
        _write_json(settings.services_file, services)


async def toggle_service(service_id: str, enabled: bool) -> bool:
    services = await get_services()
    for svc in services:
        if svc["id"] == service_id:
            svc["isEnabled"] = enabled
            await save_services(services)
            return True
    return False


# ─── Device state ─────────────────────────────────────────────────────────────

_device_state_file = settings.data_dir / "device.json"


def get_device_state() -> dict:
    return _read_json(
        _device_state_file,
        {"name": settings.device_name},
    )


def update_device_name(name: str) -> None:
    state = get_device_state()
    state["name"] = name
    _write_json(_device_state_file, state)


# ─── Storage state ────────────────────────────────────────────────────────────

async def get_storage_state() -> dict:
    """Read persisted storage mount info (activeDevice, mountedAt, etc.)."""
    async with _store_lock:
        return _read_json(settings.storage_file, {})


async def save_storage_state(state: dict) -> None:
    """Persist storage mount info to disk."""
    async with _store_lock:
        _write_json(settings.storage_file, state)


async def clear_storage_state() -> None:
    """Clear persisted storage state (after unmount)."""
    async with _store_lock:
        _write_json(settings.storage_file, {})
