"""
Auth routes — pairing, user creation, logout, PIN management, QR generation.
"""

import socket

from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import create_token, get_current_user, hash_password, verify_password
from ..config import settings
from ..models import (
    ChangePinRequest,
    CreateUserRequest,
    LoginRequest,
    PairRequest,
    TokenResponse,
)
from .. import store

router = APIRouter(prefix="/api/v1", tags=["auth"])


def _get_local_ip() -> str:
    """Get the device's local IP address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


@router.get("/pair/qr")
async def get_pairing_qr():
    """
    Return the QR payload string that the Flutter app needs to scan.
    The Cubie displays this as a QR code on its screen or web UI.
    Format: cubie://pair?serial=...&key=...&host=...
    """
    ip = _get_local_ip()
    serial = settings.device_serial
    key = settings.pairing_key
    host = f"cubie-{serial}.local"

    qr_value = (
        f"cubie://pair"
        f"?serial={serial}"
        f"&key={key}"
        f"&host={host}"
    )

    return {
        "qrValue": qr_value,
        "serial": serial,
        "ip": ip,
        "host": host,
    }


@router.post("/pair", response_model=TokenResponse)
async def pair_device(body: PairRequest):
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


@router.post("/users", status_code=status.HTTP_201_CREATED)
async def create_user(body: CreateUserRequest):
    """Create a new user on the device. First user is automatically admin."""
    if not body.name.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Name cannot be empty")

    existing = await store.get_users()
    is_admin = len(existing) == 0  # First user is admin

    hashed_pin = await hash_password(body.pin) if body.pin else None
    user = await store.add_user(body.name, hashed_pin, is_admin=is_admin)
    return {
        "id": user["id"],
        "name": user["name"],
        "isAdmin": user.get("is_admin", False),
    }


@router.post("/auth/login")
async def login(body: LoginRequest):
    """Login with username and PIN and return an access token."""
    users = await store.get_users()
    found = next((u for u in users if u.get("name") == body.name), None)
    if not found:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid credentials")

    stored_pin = found.get("pin")
    if not stored_pin:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "PIN is not configured for this user")

    if str(stored_pin).startswith("$2"):
        ok = await verify_password(body.pin, stored_pin)
    else:
        # Legacy plaintext pin compatibility
        ok = body.pin == stored_pin

    if not ok:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid credentials")

    token = create_token(
        subject=found["id"],
        extra={
            "type": "user",
            "is_admin": bool(found.get("is_admin", False)),
        },
    )
    return {
        "accessToken": token,
        "user": {
            "id": found["id"],
            "name": found["name"],
            "isAdmin": bool(found.get("is_admin", False)),
        },
    }


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(user: dict = Depends(get_current_user)):
    """Logout — client should discard its token."""
    return None


@router.put("/users/pin", status_code=status.HTTP_204_NO_CONTENT)
async def change_pin(body: ChangePinRequest, user: dict = Depends(get_current_user)):
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
            if stored_pin != body.old_pin:
                raise HTTPException(status.HTTP_403_FORBIDDEN, "Old PIN does not match")

    await store.update_user_pin(user_id, await hash_password(body.new_pin))
