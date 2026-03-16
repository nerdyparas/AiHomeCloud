"""
JSON-file-based persistence for users, services config, and device state.
Designed for simplicity on a single-device NAS â€” no database needed.
"""

from __future__ import annotations

import json
import logging
import uuid
from pathlib import Path
import asyncio
from typing import Any, Dict, List, Optional
import os
import tempfile
import time

from .config import settings

logger = logging.getLogger("aihomecloud.store")

# Async lock to protect concurrent access to JSON files from async handlers
_store_lock = asyncio.Lock()

# Separate lock serialising the first-user check + create sequence to prevent
# a race where two simultaneous requests both observe 0 users and both try to
# create the admin account.  Must be distinct from _store_lock (which is also
# acquired inside add_user → save_users) to avoid re-entrant deadlocks.
_user_creation_lock = asyncio.Lock()

_CACHE_TTL = 5.0  # seconds â€” longer TTL reduces JSON re-reads during browsing
_cache: dict[str, tuple[Any, float]] = {}

# Sentinel for distinguishing "no default passed" from "default=None"
_UNSET = object()


def _get_cached(key: str) -> Any:
    item = _cache.get(key)
    if item is None:
        return None

    value, expires_at = item
    if time.monotonic() > expires_at:
        _cache.pop(key, None)
        return None
    return value


def _set_cached(key: str, value: Any) -> None:
    if value is None:
        _cache.pop(key, None)
        return
    _cache[key] = (value, time.monotonic() + _CACHE_TTL)


def _read_json(path: Path, default: Any = _UNSET) -> Any:
    if not path.exists():
        return {} if default is _UNSET else default
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, ValueError):
        logger.error("corrupt_json path=%s — attempting recovery", path)
        fallback = {} if default is _UNSET else default

        # Rename corrupt file for forensic inspection
        corrupt_name = path.with_suffix(".json.corrupt")
        try:
            path.rename(corrupt_name)
        except Exception:
            pass

        # Attempt recovery from the .corrupt backup (may be the previous good copy)
        recovered = False
        try:
            if corrupt_name.exists():
                data = json.loads(corrupt_name.read_text())
                logger.info("corrupt_json_recovered path=%s from backup", path)
                # Restore the recovered data back to the original path
                _atomic_write(path, data)
                recovered = True
                fallback = data
        except (json.JSONDecodeError, ValueError, OSError):
            logger.error("corrupt_json_recovery_failed path=%s — data lost", path)

        # Emit data_corruption event for UI notification
        try:
            from .events import file_event_bus, FileEvent
            import asyncio
            loop = asyncio.get_event_loop()
            if loop.is_running():
                loop.create_task(file_event_bus.publish(FileEvent(
                    path=str(path),
                    action="data_corruption" if not recovered else "data_corruption_recovered",
                    user="system",
                )))
        except Exception:
            pass  # event bus may not be ready during early startup

        return fallback


def _atomic_write(path: Path, data: Any) -> None:
    """Write JSON to `path` atomically by writing to a temp file then moving it.

    This prevents partially-written JSON files on crash/power-loss.
    If fsync fails (e.g. disk full), the temp file is cleaned up and the
    original file is left untouched.
    """
    path.parent.mkdir(parents=True, exist_ok=True)

    # Use the same directory to ensure os.replace is atomic on the same filesystem.
    fd, tmp_path = tempfile.mkstemp(prefix=path.name, dir=str(path.parent))
    fsync_ok = False
    try:
        # Write bytes to fd, flush and fsync to ensure durability.
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(json.dumps(data, indent=2))
            f.flush()
            os.fsync(f.fileno())
        fsync_ok = True

        # Atomically replace target — only reached if fsync succeeded.
        os.replace(tmp_path, str(path))
    except Exception as exc:
        # Clean up temp file — original file is untouched.
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
        if not fsync_ok:
            logger.error(
                "atomic_write_fsync_failed path=%s error=%s — temp file cleaned up, original file preserved",
                path, exc,
            )
        raise


def _write_json(path: Path, data: Any) -> None:
    _atomic_write(path, data)


# â”€â”€â”€ Users â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

async def get_users() -> List[dict]:
    """Return the list of users, protected by the store lock."""
    cached = _get_cached("users")
    if cached is not None:
        return cached

    async with _store_lock:
        users = _read_json(settings.users_file, [])
        _set_cached("users", users)
        return users


async def save_users(users: List[dict]) -> None:
    """Persist users to disk using an async lock to prevent concurrent writes."""
    async with _store_lock:
        _write_json(settings.users_file, users)
        _set_cached("users", users)  # update inside lock after write


async def find_user(user_id: str) -> Optional[dict]:
    users = await get_users()
    return next((u for u in users if u["id"] == user_id), None)


def _create_personal_dirs(personal: Path) -> None:
    """Synchronously create the user's personal directory hierarchy.
    Runs in a thread executor so it never blocks the event loop."""
    personal.mkdir(parents=True, exist_ok=True)
    for sub in ("Photos", "Videos", "Documents", "Others", ".inbox"):
        (personal / sub).mkdir(exist_ok=True)


async def add_user(
    name: str,
    pin: Optional[str] = None,
    is_admin: bool = False,
    icon_emoji: str = "",
) -> dict:
    users = await get_users()
    user = {
        "id": f"user_{uuid.uuid4().hex[:8]}",
        "name": name,
        "pin": pin,
        "is_admin": is_admin,
        "icon_emoji": icon_emoji,
    }
    users.append(user)
    await save_users(users)

    # Best-effort: create personal folder hierarchy in a thread executor so we
    # never block the event loop on USB I/O and never fail user creation due to
    # storage errors (folders are created on demand when user first uploads).
    safe_name = Path(name).name  # strips any directory components like ../
    personal = settings.personal_path / safe_name
    try:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _create_personal_dirs, personal)
    except Exception as _e:
        logger.warning("Could not pre-create personal dirs for %s: %s", name, _e)

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


async def update_user_profile(
    user_id: str,
    *,
    name: str | None = None,
    icon_emoji: str | None = None,
) -> bool:
    """Update display name and/or icon_emoji for a user. Returns False if not found."""
    users = await get_users()
    for u in users:
        if u["id"] == user_id:
            if name is not None:
                u["name"] = name.strip()
            if icon_emoji is not None:
                u["icon_emoji"] = icon_emoji.strip()
            await save_users(users)
            _set_cached("users", None)  # invalidate cache
            return True
    return False


async def remove_pin(user_id: str) -> bool:
    """Remove PIN from a user (sets to None = no PIN required)."""
    users = await get_users()
    for u in users:
        if u["id"] == user_id:
            u["pin"] = None
            await save_users(users)
            _set_cached("users", None)
            return True
    return False


async def update_user_role(user_id: str, is_admin: bool) -> bool:
    """Set or unset admin flag for a user. Returns False if user not found."""
    users = await get_users()
    for u in users:
        if u["id"] == user_id:
            u["is_admin"] = is_admin
            await save_users(users)
            _set_cached("users", None)
            return True
    return False


# â”€â”€â”€ Services â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

_DEFAULT_SERVICES = [
    {
        "id": "media",
        "name": "TV & Computer Sharing",
        "description": "DLNA streaming + SMB file sharing",
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
]


async def get_services() -> List[dict]:
    """Return services list, creating defaults if missing."""
    cached = _get_cached("services")
    if cached is not None:
        return cached

    async with _store_lock:
        services = _read_json(settings.services_file, None)
        if services is None:
            _write_json(settings.services_file, _DEFAULT_SERVICES)
            _set_cached("services", _DEFAULT_SERVICES)
            return _DEFAULT_SERVICES

        # Migrate: merge old samba + dlna into unified media service
        ids = {s["id"] for s in services}
        if "media" not in ids and ("samba" in ids or "dlna" in ids):
            enabled = any(
                s.get("isEnabled", False)
                for s in services
                if s["id"] in ("samba", "dlna")
            )
            services = [
                s for s in services if s["id"] not in ("samba", "dlna")
            ]
            services.insert(0, {
                "id": "media",
                "name": "TV & Computer Sharing",
                "description": "DLNA streaming + SMB file sharing",
                "isEnabled": enabled,
            })
            _write_json(settings.services_file, services)

        _set_cached("services", services)
        return services


async def save_services(services: List[dict]) -> None:
    """Persist services list to disk under lock."""
    _set_cached("services", None)
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


# â”€â”€â”€ Device state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€


async def get_device_state() -> dict:
    """Read device state (name etc.), protected by the store lock."""
    cached = _get_cached("device_state")
    if cached is not None:
        return cached

    async with _store_lock:
        state = _read_json(
            settings.data_dir / "device.json",
            {"name": settings.device_name},
        )
        _set_cached("device_state", state)
        return state


async def update_device_name(name: str) -> None:
    """Update device display name under lock."""
    _set_cached("device_state", None)
    async with _store_lock:
        dev_file = settings.data_dir / "device.json"
        state = _read_json(dev_file, {"name": settings.device_name})
        state["name"] = name
        _write_json(dev_file, state)


# â”€â”€â”€ Storage state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

async def get_storage_state() -> dict:
    """Read persisted storage mount info (activeDevice, mountedAt, etc.)."""
    cached = _get_cached("storage_state")
    if cached is not None:
        return cached

    async with _store_lock:
        state = _read_json(settings.storage_file, {})
        _set_cached("storage_state", state)
        return state


async def save_storage_state(state: dict) -> None:
    """Persist storage mount info to disk."""
    _set_cached("storage_state", None)
    async with _store_lock:
        _write_json(settings.storage_file, state)


async def clear_storage_state() -> None:
    """Clear persisted storage state (after unmount)."""
    _set_cached("storage_state", None)
    async with _store_lock:
        _write_json(settings.storage_file, {})


# â”€â”€â”€ Tokens (refresh tokens) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

async def get_tokens() -> List[dict]:
    """Return list of refresh token records."""
    cached = _get_cached("tokens")
    if cached is not None:
        return cached

    async with _store_lock:
        tokens = _read_json(settings.tokens_file, [])
        if not isinstance(tokens, list):
            tokens = []
        _set_cached("tokens", tokens)
        return tokens


async def save_tokens(tokens: List[dict]) -> None:
    """Persist tokens list to disk."""
    _set_cached("tokens", None)
    async with _store_lock:
        _write_json(settings.tokens_file, tokens)


async def add_token(record: dict) -> None:
    tokens = await get_tokens()
    tokens.append(record)
    await save_tokens(tokens)


async def get_token(jti: str) -> dict | None:
    tokens = await get_tokens()
    return next((t for t in tokens if t.get("jti") == jti), None)


async def revoke_token(jti: str) -> bool:
    tokens = await get_tokens()
    changed = False
    for t in tokens:
        if t.get("jti") == jti:
            t["revoked"] = True
            changed = True
    if changed:
        await save_tokens(tokens)
    return changed


async def purge_expired_tokens(older_than_ts: int) -> int:
    """Remove tokens whose `expiresAt` is older than `older_than_ts`
    or that have been revoked.  Returns number removed.
    """
    tokens = await get_tokens()
    kept = [
        t for t in tokens
        if t.get("expiresAt", 0) >= older_than_ts and not t.get("revoked", False)
    ]
    removed = len(tokens) - len(kept)
    if removed > 0:
        await save_tokens(kept)
    return removed


# â”€â”€â”€ Pairing / OTP persistence â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€




async def get_otp() -> dict | None:
    """Return the OTP record stored in pairing.json or None if missing/expired.

    The record shape is: {"otp_hash": str, "expires_at": int}
    """
    cached = _get_cached("pairing_otp")
    if cached is not None:
        return cached

    async with _store_lock:
        data = _read_json(settings.data_dir / "pairing.json", None)
        if not data:
            _set_cached("pairing_otp", None)
            return None
        _set_cached("pairing_otp", data)
        return data


async def save_otp(otp_hash: str, expires_at: int) -> None:
    """Persist an OTP record (hash + expiry) to pairing.json under lock."""
    _set_cached("pairing_otp", None)
    async with _store_lock:
        record = {"otp_hash": otp_hash, "expires_at": int(expires_at)}
        _write_json(settings.data_dir / "pairing.json", record)


async def clear_otp() -> None:
    """Clear any stored OTP (remove pairing.json)."""
    _set_cached("pairing_otp", None)
    async with _store_lock:
        # Remove file if it exists; write empty dict for atomicity.
        _write_json(settings.data_dir / "pairing.json", {})


# ---------------------------------------------------------------------------
# Generic key-value store (kv.json) â€” for simple config blobs
# ---------------------------------------------------------------------------

async def get_value(key: str, default: Any = None) -> Any:
    """Read a value from the generic key-value store (kv.json)."""
    cached = _get_cached(f"kv:{key}")
    if cached is not None:
        return cached

    async with _store_lock:
        data: Dict[str, Any] = _read_json(settings.data_dir / "kv.json", {})
        value = data.get(key, default)
        _set_cached(f"kv:{key}", value)
        return value


async def set_value(key: str, value: Any) -> None:
    """Write a value to the generic key-value store (kv.json)."""
    _set_cached(f"kv:{key}", None)
    async with _store_lock:
        data: Dict[str, Any] = _read_json(settings.data_dir / "kv.json", {})
        data[key] = value
        _write_json(settings.data_dir / "kv.json", data)


async def atomic_update(key: str, fn, default=None) -> Any:
    """Read-modify-write a kv.json key under a single lock acquisition.

    ``fn`` receives the current value and must return the new value.
    Returns the new value after writing.
    """
    _set_cached(f"kv:{key}", None)
    async with _store_lock:
        data: Dict[str, Any] = _read_json(settings.data_dir / "kv.json", {})
        current = data.get(key, default)
        updated = fn(current)
        data[key] = updated
        _write_json(settings.data_dir / "kv.json", data)
        _set_cached(f"kv:{key}", updated)
        return updated


# ---------------------------------------------------------------------------
# Trash metadata (trash.json)
# ---------------------------------------------------------------------------

async def get_trash_items() -> List[dict]:
    """Return all trash item metadata records."""
    cached = _get_cached("trash")
    if cached is not None:
        return cached

    async with _store_lock:
        items = _read_json(settings.trash_file, [])
        _set_cached("trash", items)
        return items


async def save_trash_items(items: List[dict]) -> None:
    """Persist the trash metadata list to disk."""
    async with _store_lock:
        _write_json(settings.trash_file, items)
        _set_cached("trash", items)
