"""
Family / user management routes.
"""

import asyncio
import os
from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import get_current_user, require_admin
from ..config import settings
from ..models import AddFamilyUserRequest, FamilyUser
from .. import store

router = APIRouter(prefix="/api/v1/users", tags=["users"])


def _folder_size_gb_sync(path: str) -> float:
    """Calculate total size of a directory in GB (synchronous)."""
    total = 0
    try:
        for dirpath, _, filenames in os.walk(path):
            for f in filenames:
                try:
                    total += os.path.getsize(os.path.join(dirpath, f))
                except OSError:
                    pass
    except OSError:
        pass
    return round(total / (1024 ** 3), 2)


async def _folder_size_gb(path: str) -> float:
    """Calculate total size of a directory in GB (non-blocking)."""
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, _folder_size_gb_sync, path)


# Simple deterministic colour palette
_COLORS = ["FFE8A84C", "FF4C9BE8", "FF4CE88A", "FFE84CA8", "FF9B59B6", "FF1ABC9C"]


@router.get("/family", response_model=list[FamilyUser])
async def list_family(user: dict = Depends(get_current_user)):
    """List all family users on this Cubie."""
    users = await store.get_users()
    result = []
    for i, u in enumerate(users):
        personal_dir = settings.personal_path / u["name"]
        result.append(
            FamilyUser(
                id=u["id"],
                name=u["name"],
                isAdmin=u.get("is_admin", False),
                folderSizeGB=await _folder_size_gb(str(personal_dir)),
                avatarColor=_COLORS[i % len(_COLORS)],
            )
        )
    return result


@router.post("/family", response_model=FamilyUser, status_code=status.HTTP_201_CREATED)
async def add_family(body: AddFamilyUserRequest, user: dict = Depends(require_admin)):
    """Add a new family member."""
    if not body.name.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Name cannot be empty")

    new_user = await store.add_user(body.name)
    users = await store.get_users()
    idx = len(users) - 1

    return FamilyUser(
        id=new_user["id"],
        name=new_user["name"],
        isAdmin=False,
        folderSizeGB=0.0,
        avatarColor=_COLORS[idx % len(_COLORS)],
    )


@router.delete("/family/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_family(user_id: str, user: dict = Depends(require_admin)):
    """Remove a family member."""
    if not await store.remove_user(user_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
