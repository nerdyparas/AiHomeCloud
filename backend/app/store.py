"""
JSON-file-based persistence for users, services config, and device state.
Designed for simplicity on a single-device NAS — no database needed.
"""

from __future__ import annotations

import json
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

from .config import settings


def _read_json(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default if default is not None else {}
    return json.loads(path.read_text())


def _write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2))


# ─── Users ────────────────────────────────────────────────────────────────────

def get_users() -> List[dict]:
    return _read_json(settings.users_file, [])


def save_users(users: List[dict]) -> None:
    _write_json(settings.users_file, users)


def find_user(user_id: str) -> Optional[dict]:
    return next((u for u in get_users() if u["id"] == user_id), None)


def add_user(name: str, pin: Optional[str] = None, is_admin: bool = False) -> dict:
    users = get_users()
    user = {
        "id": f"user_{uuid.uuid4().hex[:8]}",
        "name": name,
        "pin": pin,
        "is_admin": is_admin,
    }
    users.append(user)
    save_users(users)

    # Create personal folder
    personal = settings.personal_path / name
    personal.mkdir(parents=True, exist_ok=True)

    return user


def remove_user(user_id: str) -> bool:
    users = get_users()
    filtered = [u for u in users if u["id"] != user_id]
    if len(filtered) == len(users):
        return False
    save_users(filtered)
    return True


def update_user_pin(user_id: str, new_pin: str) -> bool:
    users = get_users()
    for u in users:
        if u["id"] == user_id:
            u["pin"] = new_pin
            save_users(users)
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


def get_services() -> List[dict]:
    services = _read_json(settings.services_file, None)
    if services is None:
        _write_json(settings.services_file, _DEFAULT_SERVICES)
        return _DEFAULT_SERVICES
    return services


def toggle_service(service_id: str, enabled: bool) -> bool:
    services = get_services()
    for svc in services:
        if svc["id"] == service_id:
            svc["isEnabled"] = enabled
            _write_json(settings.services_file, services)
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
