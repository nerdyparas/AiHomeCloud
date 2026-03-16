"""
Family / user management routes.
"""

import asyncio
import logging
import os
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, status

from ..auth import get_current_user, require_admin
from ..config import settings
from ..models import AddFamilyUserRequest, FamilyUser, SetUserRoleRequest
from .. import store
from ..audit import audit_log

router = APIRouter(prefix="/api/v1/users", tags=["users"])
logger = logging.getLogger("aihomecloud.family")


def _folder_size_gb_sync(path: str, max_depth: int = 5) -> float:
    """Calculate total size of a directory in GB (synchronous).

    *max_depth* limits how many directory levels are traversed so that a very
    large NAS tree cannot block the thread indefinitely.
    """
    total = 0
    root = Path(path)
    try:
        for dirpath, dirnames, filenames in os.walk(path):
            # Prune sub-dirs that exceed the depth limit.
            depth = len(Path(dirpath).relative_to(root).parts)
            if depth >= max_depth:
                dirnames.clear()
            for f in filenames:
                try:
                    total += os.path.getsize(os.path.join(dirpath, f))
                except OSError:
                    pass
    except OSError:
        pass
    return round(total / (1024 ** 3), 2)


async def _folder_size_gb(path: str, timeout: float = 10.0) -> float:
    """Calculate total size of a directory in GB (non-blocking, with timeout).

    Returns the size computed within *timeout* seconds.  On timeout, logs a
    warning and returns -1 so callers can surface an "estimated" indicator.
    """
    loop = asyncio.get_running_loop()
    try:
        return await asyncio.wait_for(
            loop.run_in_executor(None, _folder_size_gb_sync, path),
            timeout=timeout,
        )
    except asyncio.TimeoutError:
        logger.warning("folder_size_timeout path=%s — returning -1", path)
        return -1.0


# Simple deterministic colour palette
_COLORS = ["FFE8A84C", "FF4C9BE8", "FF4CE88A", "FFE84CA8", "FF9B59B6", "FF1ABC9C"]


def _ensure_personal_folder(path: str) -> None:
    """Create personal folder and standard sub-folders if missing."""
    p = Path(path)
    if not p.exists():
        try:
            p.mkdir(parents=True, exist_ok=True)
            for sub in ("Photos", "Videos", "Documents", "Others", ".inbox"):
                (p / sub).mkdir(exist_ok=True)
        except OSError:
            pass


@router.get("/family", response_model=list[FamilyUser])
async def list_family(user: dict = Depends(get_current_user)):
    """List all family users on this Cubie."""
    users = await store.get_users()
    # Compute folder sizes in parallel to avoid sequential blocking
    personal_dirs = [str(settings.personal_path / u["name"]) for u in users]
    # Ensure each user's personal folder exists on the currently mounted NAS
    for d in personal_dirs:
        _ensure_personal_folder(d)
    sizes = await asyncio.gather(*[_folder_size_gb(d) for d in personal_dirs])
    result = [
        FamilyUser(
            id=u["id"],
            name=u["name"],
            isAdmin=u.get("is_admin", False),
            folderSizeGB=sizes[i],
            avatarColor=_COLORS[i % len(_COLORS)],
            iconEmoji=u.get("icon_emoji", ""),
        )
        for i, u in enumerate(users)
    ]
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
        iconEmoji=new_user.get("icon_emoji", ""),
    )


@router.delete("/family/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_family(user_id: str, user: dict = Depends(require_admin)):
    """Remove a family member."""
    target = await store.find_user(user_id)
    if not target or not await store.remove_user(user_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    audit_log("family_member_removed", actor_id=user.get("sub", ""), target_id=user_id, user_name=target.get("name", ""))


@router.put("/family/{user_id}/role", status_code=status.HTTP_204_NO_CONTENT)
async def set_family_role(
    user_id: str,
    body: SetUserRoleRequest,
    caller: dict = Depends(require_admin),
):
    """Promote or demote a family member's admin status.

    Only admins can call this endpoint.
    Demoting the last admin is blocked to prevent lockout.
    """
    target = await store.find_user(user_id)
    if not target:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")

    # Block demoting the last admin
    if not body.is_admin:
        all_users = await store.get_users()
        admins = [u for u in all_users if u.get("is_admin")]
        if len(admins) <= 1 and target.get("is_admin"):
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                "Cannot remove admin rights from the only admin",
            )

    updated = await store.update_user_role(user_id, body.is_admin)
    if not updated:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")

    audit_log(
        "user_role_changed",
        actor_id=caller.get("sub", ""),
        target_id=user_id,
        user_name=target.get("name", ""),
        is_admin=body.is_admin,
    )
