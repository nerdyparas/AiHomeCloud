"""
Auth routes — pairing, user creation, logout, PIN management, QR generation.
"""

from __future__ import annotations

import hmac
import logging
import time
from pathlib import Path
from typing import Dict, Tuple

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ..limiter import limiter

logger = logging.getLogger("aihomecloud.auth")

# In-memory account lockout: IP → (fail_count, lockout_until_timestamp)
_failed_logins: Dict[str, Tuple[int, float]] = {}
_MAX_FAILURES = 10
_LOCKOUT_SECONDS = 900  # 15 minutes


def _prune_failed_logins() -> None:
    """Remove entries whose lockout has expired. Called opportunistically to keep the dict bounded."""
    now = time.time()
    stale = [
        ip for ip, (count, lockout_until) in _failed_logins.items()
        if lockout_until > 0 and lockout_until < now
    ]
    for ip in stale:
        _failed_logins.pop(ip, None)


def _record_failure(ip: str) -> None:
    """Increment failed login counter for an IP; set lockout when threshold reached."""
    record = _failed_logins.get(ip)
    count = (record[0] if record else 0) + 1
    lockout_until = (time.time() + _LOCKOUT_SECONDS) if count >= _MAX_FAILURES else 0.0
    _failed_logins[ip] = (count, lockout_until)
    # Opportunistic prune: remove other unlocked entries while we have the dict open
    _prune_failed_logins()

from ..auth import (
    create_token,
    create_refresh_token,
    decode_refresh_token,
    get_current_user,
    get_current_user_optional,
    require_admin,
    hash_password,
    verify_password,
    pwd_context,
)
from ..config import settings, get_local_ip
from ..models import (
    ChangePinRequest,
    CreateUserRequest,
    LoginRequest,
    RefreshRequest,
    PairRequest,
    PairCompleteRequest,
    TokenResponse,
    UpdateProfileRequest,
)
from .. import store
from ..audit import audit_log

router = APIRouter(prefix="/api/v1", tags=["auth"])


def _wipe_stale_nas_dirs() -> None:
    """Remove app-managed top-level dirs from NAS root on first-time setup.
    Wipes stale data from previous installations so the new user starts fresh.
    Runs in an executor — never blocks the event loop.
    """
    import shutil
    for dirname in ("personal", "family", "entertainment"):
        d = settings.nas_root / dirname
        if d.exists():
            try:
                shutil.rmtree(d)
                logger.info("First-time setup: wiped stale NAS dir %s", d)
            except Exception as e:
                logger.warning("Could not wipe stale NAS dir %s: %s", d, e)


async def _bg_wipe_stale_nas_dirs() -> None:
    """Await _wipe_stale_nas_dirs in a thread executor."""
    import asyncio
    try:
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, _wipe_stale_nas_dirs)
    except Exception as e:
        logger.warning("Background NAS dir wipe failed: %s", e)


async def _rehash_pin(user_id: str, plain_pin: str) -> None:
    """Background task: re-hash a PIN with the current bcrypt rounds."""
    try:
        new_hash = await hash_password(plain_pin)
        await store.update_user_pin(user_id, new_hash)
        logger.info("Auto-upgraded bcrypt rounds for user %s", user_id)
    except Exception as e:
        logger.warning("Failed to auto-upgrade PIN hash: %s", e)


@router.get("/pair/qr")
async def get_pairing_qr():
    """
    Return the QR payload string that the Flutter app needs to scan.
    The Cubie displays this as a QR code on its screen or web UI.
    Format: aihomecloud://pair?serial=...&key=...&host=...
    """
    ip = get_local_ip()
    serial = settings.device_serial
    key = settings.pairing_key
    host = f"ahc-{serial}.local"

    # Always generate a fresh short-lived OTP so the caller can display it.
    import hashlib
    import secrets
    from datetime import datetime, timedelta, timezone

    otp = f"{secrets.randbelow(10**6):06d}"
    otp_hash = hashlib.sha256(otp.encode()).hexdigest()
    expires_at = int((datetime.now(timezone.utc) + timedelta(seconds=300)).timestamp())
    await store.save_otp(otp_hash, expires_at)

    from urllib.parse import urlencode
    params = {
        "serial": serial,
        "key": key,
        "host": host,
        "expiresAt": str(expires_at),
    }
    qr_value = "aihomecloud://pair?" + urlencode(params)

    return {
        "qrValue": qr_value,
        "otp": otp,
        "serial": serial,
        "ip": ip,
        "host": host,
        "expiresAt": expires_at,
    }


@router.post("/pair", response_model=TokenResponse)
@limiter.limit("10/minute")
async def pair_device(request: Request, body: PairRequest):
    """
    Pair with the Cubie by providing its serial + pairing key.
    Returns a JWT on success.
    """
    if not hmac.compare_digest(body.serial, settings.device_serial):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Unknown serial")
    if not hmac.compare_digest(body.key, settings.pairing_key):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Invalid pairing key")

    token = create_token(subject=body.serial, extra={"type": "device"})
    return TokenResponse(token=token)


@router.post("/pair/complete", response_model=TokenResponse)
@limiter.limit("5/minute")
async def pair_complete(request: Request, body: PairCompleteRequest):
    """
    Complete pairing by validating serial, pairing key, and OTP.
    On success, clears stored OTP and returns a device JWT.
    """
    if not hmac.compare_digest(body.serial, settings.device_serial):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Unknown serial")
    if not hmac.compare_digest(body.key, settings.pairing_key):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Invalid pairing key")

    # Validate OTP
    import hashlib
    from datetime import datetime, timezone

    otp_rec = await store.get_otp()
    now = int(datetime.now(timezone.utc).timestamp())
    if not otp_rec or not otp_rec.get("otp_hash") or not otp_rec.get("expires_at"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "No active OTP for pairing")
    if int(otp_rec.get("expires_at", 0)) < now:
        # Clear expired OTP
        await store.clear_otp()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "OTP expired")

    provided_hash = hashlib.sha256(body.otp.encode()).hexdigest()
    if not hmac.compare_digest(provided_hash, otp_rec.get("otp_hash")):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Invalid OTP")

    # OTP valid — clear it and issue device token
    await store.clear_otp()
    token = create_token(subject=body.serial, extra={"type": "device"})
    return TokenResponse(token=token)


@router.get("/auth/cert-fingerprint")
async def cert_fingerprint():
    """Return SHA-256 fingerprint of server TLS cert (DER hex)."""
    import hashlib
    from base64 import b64decode
    try:
        cert_bytes = settings.tls_cert_path.read_bytes()
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


@router.get("/auth/users/names")
async def list_user_names():
    """
    Return user names and PIN status for the login picker.
    has_pin is True when the account has a PIN set, False when no PIN required.
    No auth required — this is public so the picker can show before login.
    The actual PIN hash is never returned.
    """
    users = await store.get_users()
    return {
        "users": [
            {
                "name": u["name"],
                "has_pin": bool(u.get("pin")),
                "icon_emoji": u.get("icon_emoji", ""),
            }
            for u in users
        ]
    }


@router.post("/users", status_code=status.HTTP_201_CREATED)
@limiter.limit("5/minute")
async def create_user(
    request: Request,
    body: CreateUserRequest,
    caller: dict | None = Depends(get_current_user_optional),
):
    """Create a new user. First call (setup) is unauthenticated; all subsequent calls require admin."""
    if not body.name.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Name cannot be empty")

    # Hash the PIN before entering the creation lock so we don't hold it during bcrypt.
    hashed_pin = await hash_password(body.pin) if body.pin else None

    # Acquire the dedicated creation lock so the read → check → write sequence is
    # atomic.  We cannot reuse store._store_lock here because add_user() also
    # acquires it (via save_users), which would deadlock.
    async with store._user_creation_lock:
        existing = await store.get_users()
        is_first_user = len(existing) == 0

        if not is_first_user:
            # Require admin auth once the first user has been created
            if caller is None:
                raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Authentication required")
            await require_admin(caller)

        is_admin = is_first_user

        # First-time setup: remove stale app folders from a previous
        # installation before creating the new user's directory hierarchy.
        # Awaited (not background) to avoid a race where the wipe deletes
        # folders that add_user just created.
        if is_first_user:
            await _bg_wipe_stale_nas_dirs()

        user = await store.add_user(
            body.name,
            hashed_pin,
            is_admin=is_admin,
            icon_emoji=body.icon_emoji.strip(),
        )

    # Auto-login: return tokens immediately so the client needs only one request.
    access_token = create_token(
        subject=user["id"],
        extra={"type": "user", "is_admin": is_admin},
    )
    refresh_token_str, _jti, _exp = await create_refresh_token(user["id"])

    return {
        "id": user["id"],
        "name": user["name"],
        "isAdmin": user.get("is_admin", False),
        "accessToken": access_token,
        "refreshToken": refresh_token_str,
    }


@router.post("/auth/login")
@limiter.limit("10/minute")
async def login(request: Request, body: LoginRequest):
    """Login with username and PIN and return an access token."""
    client_ip = request.client.host if request.client else "unknown"
    now = time.time()

    # Prune stale entries before checking — keeps dict bounded
    _prune_failed_logins()

    # Check account lockout
    record = _failed_logins.get(client_ip)
    if record:
        count, lockout_until = record
        if lockout_until > now:
            remaining = int(lockout_until - now)
            minutes = max(remaining // 60, 1)
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                f"Too many failed attempts. Try again in {minutes} minute(s).",
            )
        if lockout_until > 0:
            # Lockout expired — reset counter
            _failed_logins.pop(client_ip, None)

    users = await store.get_users()
    found = next((u for u in users if u.get("name") == body.name), None)
    if not found:
        _record_failure(client_ip)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid credentials")

    stored_pin = found.get("pin")
    if not stored_pin:
        # User has no PIN set — allow login with any input (including empty string)
        pass
    elif str(stored_pin).startswith("$2"):
        ok = await verify_password(body.pin, stored_pin)
        if not ok:
            _record_failure(client_ip)
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid credentials")
        # Auto-upgrade bcrypt rounds if configuration changed (e.g. 12 → 10).
        if pwd_context.needs_update(stored_pin):
            import asyncio as _aio
            _aio.get_event_loop().create_task(_rehash_pin(found["id"], body.pin))
    else:
        logger.warning("Non-bcrypt PIN found for user %s — rejecting", body.name)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid credentials")

    # Success — clear lockout counter
    _failed_logins.pop(client_ip, None)

    access_token = create_token(
        subject=found["id"],
        extra={
            "type": "user",
            "is_admin": bool(found.get("is_admin", False)),
        },
    )
    refresh_token, jti, expires_at = await create_refresh_token(found["id"])
    return {
        "accessToken": access_token,
        "refreshToken": refresh_token,
        "user": {
            "id": found["id"],
            "name": found["name"],
            "isAdmin": bool(found.get("is_admin", False)),
        },
    }


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: RefreshRequest | None = None, user: dict = Depends(get_current_user)):
    """Logout — revoke provided refresh token (if any)."""
    if body and getattr(body, "refresh_token", None):
        try:
            payload = decode_refresh_token(body.refresh_token)
            jti = payload.get("jti")
            if jti:
                await store.revoke_token(jti)
        except HTTPException:
            # treat invalid token as already logged out
            pass
    return None



@router.post("/auth/refresh")
@limiter.limit("30/minute")
async def refresh(request: Request, body: RefreshRequest):
    """Exchange a refresh token for a new access token."""
    payload = decode_refresh_token(body.refresh_token)
    jti = payload.get("jti")
    if not jti:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid refresh token")

    rec = await store.get_token(jti)
    if not rec or rec.get("revoked", False):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Refresh token revoked")
    # Issue new access token
    subject = payload.get("sub")
    # Lookup user to set is_admin flag
    found = await store.find_user(subject)
    extra = {"type": "user", "is_admin": bool(found.get("is_admin", False))} if found else {"type": "user"}
    access_token = create_token(subject=subject, extra=extra)
    return {"accessToken": access_token}


@router.put("/users/pin", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("10/minute")
async def change_pin(request: Request, body: ChangePinRequest, user: dict = Depends(get_current_user)):
    """Change the current user's PIN."""
    if len(body.new_pin) < 4:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "PIN must be at least 4 digits")

    user_id = user.get("sub", "")
    found = await store.find_user(user_id)
    if found and found.get("pin"):
        stored_pin = found.get("pin")
        if str(stored_pin).startswith("$2"):
            if not body.old_pin or not await verify_password(body.old_pin, stored_pin):
                raise HTTPException(status.HTTP_403_FORBIDDEN, "Old PIN does not match")
        else:
            if not hmac.compare_digest(str(stored_pin).encode(), body.old_pin.encode() if body.old_pin else b""):
                raise HTTPException(status.HTTP_403_FORBIDDEN, "Old PIN does not match")

    await store.update_user_pin(user_id, await hash_password(body.new_pin))


@router.get("/users/me")
async def get_my_profile(user: dict = Depends(get_current_user)):
    """Return the current user's own profile data."""
    user_id = user.get("sub", "")
    found = await store.find_user(user_id)
    if not found:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    return {
        "id": found["id"],
        "name": found["name"],
        "icon_emoji": found.get("icon_emoji", ""),
        "has_pin": bool(found.get("pin")),
        "is_admin": found.get("is_admin", False),
    }


@router.put("/users/me", status_code=status.HTTP_204_NO_CONTENT)
async def update_my_profile(
    body: UpdateProfileRequest,
    user: dict = Depends(get_current_user),
):
    """Update current user's display name and/or emoji icon."""
    user_id = user.get("sub", "")

    if body.name is not None:
        name = body.name.strip()
        if not name:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, "Name cannot be empty"
            )
        # Prevent duplicate names (case-insensitive)
        existing = await store.get_users()
        for u in existing:
            if u["id"] != user_id and u["name"].lower() == name.lower():
                raise HTTPException(
                    status.HTTP_409_CONFLICT,
                    "That name is already taken by another profile",
                )

    updated = await store.update_user_profile(
        user_id,
        name=body.name,
        icon_emoji=body.icon_emoji,
    )
    if not updated:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")


@router.delete("/users/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_my_profile(user: dict = Depends(get_current_user)):
    """
    Delete the current user's own profile and personal folder.
    Blocked if this user is the only remaining user, or the only admin.
    """
    import shutil as _shutil

    user_id = user.get("sub", "")
    found = await store.find_user(user_id)
    if not found:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")

    all_users = await store.get_users()

    # Block if last user
    if len(all_users) <= 1:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "Cannot delete the only profile on this device",
        )

    # Block if last admin
    if found.get("is_admin"):
        admins = [u for u in all_users if u.get("is_admin")]
        if len(admins) <= 1:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                "Cannot delete the only admin profile",
            )

    # Remove from users list
    removed = await store.remove_user(user_id)
    if not removed:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")

    audit_log("user_deleted_self", actor_id=user_id, user_name=found["name"])

    # Delete personal folder (best-effort, non-blocking)
    safe_name = Path(found["name"]).name
    personal_dir = settings.personal_path / safe_name
    if personal_dir.exists() and personal_dir.is_dir():
        try:
            _shutil.rmtree(personal_dir)
            logger.info("Deleted personal folder for user %s", found["name"])
        except Exception as exc:
            logger.warning("Could not delete folder for %s: %s", found["name"], exc)


@router.delete("/users/pin", status_code=status.HTTP_204_NO_CONTENT)
async def remove_my_pin(user: dict = Depends(get_current_user)):
    """Remove the current user's PIN so no PIN is required to log in."""
    user_id = user.get("sub", "")
    removed = await store.remove_pin(user_id)
    if not removed:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")

