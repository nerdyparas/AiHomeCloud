"""
Trash management routes — list, restore, permanent delete, preferences.
Split from file_routes.py for maintainability.
"""

import asyncio
import shutil
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from ..auth import get_current_user, require_admin
from ..config import settings
from .. import store
from ..models import TrashItem
from .file_routes import (
    _require_external_storage,
    _safe_resolve,
    _is_document_file,
    _is_documents_scoped,
)

router = APIRouter(prefix="/api/v1/files", tags=["trash"])

_TRASH_MAX_DAYS = 30

# Lock to prevent concurrent trash purge operations
_trash_purge_lock = asyncio.Lock()


class _TrashPrefsBody(BaseModel):
    autoDelete: bool


def _validate_trash_path(trash_path_str: str) -> Path:
    """Ensure a stored trash_path is actually inside trash_dir (prevents metadata tampering)."""
    p = Path(trash_path_str).resolve()
    trash_resolved = settings.trash_dir.resolve()
    try:
        p.relative_to(trash_resolved)
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Invalid trash path")
    return p


async def _safe_purge_trash() -> None:
    """Best-effort background trash purge — never raises. Lock prevents concurrent runs."""
    if _trash_purge_lock.locked():
        return  # Another purge is already running
    async with _trash_purge_lock:
        try:
            await _purge_trash_if_needed()
        except Exception:
            pass


async def _purge_trash_if_needed() -> None:
    """Auto-purge oldest trash items when trash exceeds 10% of NAS capacity.
    Age-based 30-day deletion only runs when the user has enabled auto-delete."""
    try:
        usage = shutil.disk_usage(settings.nas_root)
        quota_bytes = usage.total * 0.10
    except Exception:
        quota_bytes = float("inf")

    # Age-based auto-delete only runs when explicitly enabled by the user
    auto_delete = await store.get_value("trash_auto_delete", default=False)

    now = datetime.now(timezone.utc)
    items = await store.get_trash_items()
    to_keep: list[dict] = []

    # First pass: drop items older than TRASH_MAX_DAYS only when auto-delete is on
    for item in items:
        if auto_delete:
            try:
                deleted_at = datetime.fromisoformat(item["deletedAt"])
                if deleted_at.tzinfo is None:
                    deleted_at = deleted_at.replace(tzinfo=timezone.utc)
                age_days = (now - deleted_at).days
            except Exception:
                age_days = 0
            if age_days >= _TRASH_MAX_DAYS:
                _unlink_trash_item(item)
                continue
        to_keep.append(item)

    # Second pass: purge oldest until total trash size is under quota (always active)
    total_size = sum(i.get("sizeBytes", 0) for i in to_keep)
    if total_size > quota_bytes:
        to_keep.sort(key=lambda i: i.get("deletedAt", ""))
        final: list[dict] = []
        for item in to_keep:
            if total_size <= quota_bytes:
                final.append(item)
            else:
                _unlink_trash_item(item)
                total_size -= item.get("sizeBytes", 0)
        to_keep = final

    await store.save_trash_items(to_keep)


def _unlink_trash_item(item: dict) -> None:
    """Permanently remove the physical file/dir for a trash item, best-effort."""
    try:
        p = Path(item.get("trashPath", ""))
        if p.is_dir():
            shutil.rmtree(p)
        elif p.exists():
            p.unlink()
    except Exception:
        pass


# ─── Trash CRUD endpoints ─────────────────────────────────────────────────────

@router.get("/trash", response_model=list[TrashItem])
async def list_trash(user: dict = Depends(get_current_user)):
    """List the caller's trash items (files they deleted)."""
    user_id = user.get("sub", "")
    all_items = await store.get_trash_items()
    user_items = [i for i in all_items if i.get("deletedBy") == user_id]
    return [TrashItem(**i) for i in user_items]


@router.post("/trash/{item_id}/restore", status_code=status.HTTP_204_NO_CONTENT)
async def restore_trash_item(item_id: str, user: dict = Depends(get_current_user)):
    """Restore a trash item back to its original path."""
    _require_external_storage()
    user_id = user.get("sub", "")

    all_items = await store.get_trash_items()
    match = next((i for i in all_items if i.get("id") == item_id), None)
    if match is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Trash item not found")

    # Admins can restore any item; members only their own
    if match.get("deletedBy") != user_id and not (user.get("is_admin") or user.get("type") == "device"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Cannot restore other user's trash")

    trash_path = _validate_trash_path(match["trashPath"])
    if not trash_path.exists():
        # Physical file gone — remove metadata and 404
        remaining = [i for i in all_items if i.get("id") != item_id]
        await store.save_trash_items(remaining)
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Trash file no longer exists")

    original_path = _safe_resolve(match["originalPath"])
    original_path.parent.mkdir(parents=True, exist_ok=True)

    # Handle restore collision — add "_restored" suffix
    dest = original_path
    if dest.exists():
        stem = dest.stem
        suffix = dest.suffix
        dest = dest.parent / f"{stem}_restored{suffix}"

    shutil.move(str(trash_path), str(dest))

    # Re-index restored documents so search remains accurate.
    from ..document_index import index_document, index_documents_under_path
    if dest.is_file() and _is_document_file(dest):
        await index_document(str(dest), dest.name, user_id)
    elif dest.is_dir() and _is_documents_scoped(dest):
        await index_documents_under_path(str(dest), user_id)

    remaining = [i for i in all_items if i.get("id") != item_id]
    await store.save_trash_items(remaining)


@router.delete("/trash/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def permanent_delete_trash_item(item_id: str, user: dict = Depends(get_current_user)):
    """Permanently delete a trash item (cannot be undone)."""
    user_id = user.get("sub", "")

    all_items = await store.get_trash_items()
    match = next((i for i in all_items if i.get("id") == item_id), None)
    if match is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Trash item not found")

    if match.get("deletedBy") != user_id and not (user.get("is_admin") or user.get("type") == "device"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Cannot permanently delete other user's trash")

    _validate_trash_path(match["trashPath"])
    _unlink_trash_item(match)

    remaining = [i for i in all_items if i.get("id") != item_id]
    await store.save_trash_items(remaining)


@router.get("/trash/prefs")
async def get_trash_prefs(user: dict = Depends(get_current_user)):
    """Return the trash auto-delete preference (global, not per-user)."""
    auto_delete = await store.get_value("trash_auto_delete", default=False)
    return {"autoDelete": bool(auto_delete)}


@router.put("/trash/prefs", status_code=status.HTTP_204_NO_CONTENT)
async def set_trash_prefs(body: _TrashPrefsBody, user: dict = Depends(require_admin)):
    """Enable or disable the 30-day auto-delete for trash items. Admin only."""
    await store.set_value("trash_auto_delete", body.autoDelete)
