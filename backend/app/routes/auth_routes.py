"""
Auth routes — pairing, user creation, logout, PIN management.
"""

from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import create_token, get_current_user
from ..config import settings
from ..models import (
    ChangePinRequest,
    CreateUserRequest,
    PairRequest,
    TokenResponse,
)
from .. import store

router = APIRouter(prefix="/api", tags=["auth"])


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
    """Create a new user on the device."""
    if not body.name.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Name cannot be empty")
    user = store.add_user(body.name, body.pin)
    return {"id": user["id"], "name": user["name"]}


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
    found = store.find_user(user_id)
    if found and found.get("pin") != body.old_pin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Old PIN does not match")

    store.update_user_pin(user_id, body.new_pin)
