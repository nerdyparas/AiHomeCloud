"""
Auth routes — pairing, user creation, logout, PIN management, QR generation.
"""

from __future__ import annotations

import hmac
import logging
import time
from typing import Dict, Tuple

from fastapi import APIRouter, Depends, HTTPException, Request, status

from ..limiter import limiter

logger = logging.getLogger("cubie.auth")

# In-memory account lockout: IP → (fail_count, lockout_until_timestamp)
_failed_logins: Dict[str, Tuple[int, float]] = {}
_MAX_FAILURES = 10
_LOCKOUT_SECONDS = 900  # 15 minutes


def _record_failure(ip: str) -> None:
    """Increment failed login counter for an IP; set lockout when threshold reached."""
    record = _failed_logins.get(ip)
    count = (record[0] if record else 0) + 1
    lockout_until = (time.time() + _LOCKOUT_SECONDS) if count >= _MAX_FAILURES else 0.0
    _failed_logins[ip] = (count, lockout_until)

from ..auth import (
    create_token,
    create_refresh_token,
    decode_refresh_token,
    get_current_user,
    get_current_user_optional,
    require_admin,
    hash_password,
    verify_password,
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
)
from .. import store

router = APIRouter(prefix="/api/v1", tags=["auth"])


@router.get("/pair/qr")
async def get_pairing_qr():
    """
    Return the QR payload string that the Flutter app needs to scan.
    The Cubie displays this as a QR code on its screen or web UI.
    Format: cubie://pair?serial=...&key=...&host=...
    """
    ip = get_local_ip()
    serial = settings.device_serial
    key = settings.pairing_key
    host = f"cubie-{serial}.local"

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
    qr_value = "cubie://pair?" + urlencode(params)

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
    if body.serial != settings.device_serial:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Unknown serial")
    if body.key != settings.pairing_key:
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
    if body.serial != settings.device_serial:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Unknown serial")
    if body.key != settings.pairing_key:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Invalid pairing key")

    # Validate OTP
    import hashlib
    import hmac
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
    """Return just the user names (no auth required) so the login screen can show a picker."""
    users = await store.get_users()
    return {"names": [u["name"] for u in users]}


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

    existing = await store.get_users()
    is_first_user = len(existing) == 0

    if not is_first_user:
        # Require admin auth once the first user has been created
        if caller is None:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Authentication required")
        await require_admin(caller)

    is_admin = is_first_user

    hashed_pin = await hash_password(body.pin) if body.pin else None
    user = await store.add_user(body.name, hashed_pin, is_admin=is_admin)
    return {
        "id": user["id"],
        "name": user["name"],
        "isAdmin": user.get("is_admin", False),
    }


@router.post("/auth/login")
@limiter.limit("10/minute")
async def login(request: Request, body: LoginRequest):
    """Login with username and PIN and return an access token."""
    client_ip = request.client.host if request.client else "unknown"
    now = time.time()

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
