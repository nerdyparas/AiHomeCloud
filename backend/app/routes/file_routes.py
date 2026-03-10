"""
File management routes — list, mkdir, delete, rename, upload, download.
All paths are sandboxed under settings.nas_root.
External storage must be mounted at nas_root; SD card fallback is blocked.
"""

import mimetypes
import os
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query, status
from fastapi.responses import FileResponse

from ..auth import get_current_user
from ..config import settings
from ..models import CreateFolderRequest, FileItem, FileListResponse, RenameRequest, TrashItem
from .. import store
from .event_routes import emit_upload_complete

router = APIRouter(prefix="/api/v1/files", tags=["files"])

# Executables and dangerous file types that must never be uploaded to the NAS.
BLOCKED_EXTENSIONS: frozenset[str] = frozenset({
    ".sh", ".bash", ".zsh", ".fish",
    ".py", ".rb", ".pl", ".php",
    ".elf", ".bin", ".exe",
    ".apk", ".so", ".ko",
    ".deb", ".rpm",
})


def _require_external_storage() -> None:
    """
    Verify that external storage (USB / NVMe) is mounted at nas_root.
    If nas_root is just a directory on the SD card, reject file operations
    so users don't accidentally browse OS files.
    """
    if settings.skip_mount_check:
        return
    nas = settings.nas_root
    if not nas.is_mount():
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "No external storage mounted. Please connect a USB or NVMe drive.",
        )


def _safe_resolve(raw_path: str) -> Path:
    """
    Resolve a NAS-relative path (e.g. /srv/nas/shared/Photos) to an
    absolute filesystem path, ensuring it stays within nas_root.
    """
    # Reject null bytes early — they can confuse OS path operations
    if "\x00" in raw_path:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")

    # Reject excessively long paths before touching the filesystem
    if len(raw_path) > 4096:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Path too long")

    # raw_path from the app looks like /srv/nas/shared/...
    # Strip the nas_root prefix if present so we don't double it.
    nas_prefix = str(settings.nas_root)
    if raw_path.startswith(nas_prefix):
        raw_path = raw_path[len(nas_prefix):]

    try:
        resolved = (settings.nas_root / raw_path.lstrip("/")).resolve()
    except (OSError, ValueError):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")

    nas_resolved = settings.nas_root.resolve()
    # Use os.sep suffix to prevent prefix-match attacks (e.g. /srv/nasty)
    if resolved != nas_resolved and not str(resolved).startswith(str(nas_resolved) + os.sep):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")
    return resolved


def _file_item(p: Path, rel_prefix: str) -> dict:
    """Convert a Path into a FileItem-compatible dict."""
    stat = p.stat()
    is_dir = p.is_dir()
    name = p.name
    # Rebuild NAS-style path: /srv/nas/...
    nas_path = "/" + str(p.relative_to(settings.nas_root.resolve())).replace("\\", "/")
    if is_dir and not nas_path.endswith("/"):
        nas_path += "/"

    mime, _ = mimetypes.guess_type(name)

    return {
        "name": name,
        "path": nas_path,
        "isDirectory": is_dir,
        "sizeBytes": 0 if is_dir else stat.st_size,
        "modified": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
        "mimeType": mime,
    }


@router.get("/list", response_model=FileListResponse)
async def list_files(
    path: str = Query("/srv/nas/shared/"),
    page: int = Query(0, ge=0),
    page_size: int = Query(50, ge=1, le=500, alias="page_size"),
    sort_by: str = Query("name"),
    sort_dir: str = Query("asc"),
    user: dict = Depends(get_current_user),
):
    """List files and folders at the given NAS path."""
    _require_external_storage()
    resolved = _safe_resolve(path)

    if not resolved.exists():
        # Auto-create the directory if it doesn't exist yet
        resolved.mkdir(parents=True, exist_ok=True)

    if not resolved.is_dir():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Path is not a directory")

    items = []
    for child in resolved.iterdir():
        try:
            items.append(_file_item(child, path))
        except OSError:
            # Skip broken symlinks, inaccessible files, etc.
            continue

    # Sort with stability guarantees for pagination.
    reverse = sort_dir.lower() == "desc"
    sort_key = sort_by.lower()

    def _key_name(item: dict):
        return ((item["name"] or "").casefold(), item["name"] or "")

    def _key_modified(item: dict):
        return item.get("modified") or ""

    def _key_size(item: dict):
        return item.get("sizeBytes") or 0

    if sort_key == "modified":
        items.sort(key=_key_modified, reverse=reverse)
    elif sort_key == "size":
        items.sort(key=_key_size, reverse=reverse)
    else:
        # 5E.3 requirement: stable tuple sort for names
        items.sort(key=_key_name, reverse=reverse)

    total_count = len(items)
    start = page * page_size
    end = start + page_size
    paged = items[start:end]

    return FileListResponse(
        items=[FileItem(**i) for i in paged],
        totalCount=total_count,
        page=page,
        pageSize=page_size,
    )


@router.post("/mkdir", status_code=status.HTTP_201_CREATED)
async def create_folder(body: CreateFolderRequest, user: dict = Depends(get_current_user)):
    """Create a new directory."""
    _require_external_storage()
    resolved = _safe_resolve(body.path)
    if resolved.exists():
        raise HTTPException(status.HTTP_409_CONFLICT, "Folder already exists")
    resolved.mkdir(parents=True, exist_ok=True)
    return {"path": body.path}


@router.delete("/delete", status_code=status.HTTP_204_NO_CONTENT)
async def delete_file(
    path: str = Query(...),
    user: dict = Depends(get_current_user),
):
    """Soft-delete: move file/directory to the per-user trash folder."""
    _require_external_storage()
    resolved = _safe_resolve(path)
    if not resolved.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")

    user_id = user.get("sub", "")
    filename = resolved.name
    ts = int(datetime.now(timezone.utc).timestamp())
    trash_name = f"{ts}_{filename}"

    # Per-user trash directory: {nas_root}/.cubie_trash/{user_id}/
    user_trash_dir = settings.trash_dir / user_id
    user_trash_dir.mkdir(parents=True, exist_ok=True)

    # Guard against name collision inside trash
    trash_path = user_trash_dir / trash_name
    counter = 1
    while trash_path.exists():
        trash_path = user_trash_dir / f"{ts}_{counter}_{filename}"
        counter += 1

    # Calculate size before moving
    if resolved.is_file():
        size_bytes = resolved.stat().st_size
    else:
        size_bytes = sum(f.stat().st_size for f in resolved.rglob("*") if f.is_file())

    shutil.move(str(resolved), str(trash_path))

    item = {
        "id": str(uuid.uuid4()),
        "originalPath": path,
        "trashPath": str(trash_path),
        "filename": filename,
        "deletedAt": datetime.now(timezone.utc).isoformat(),
        "sizeBytes": size_bytes,
        "deletedBy": user_id,
    }

    items = await store.get_trash_items()
    items.append(item)
    await store.save_trash_items(items)

    await _purge_trash_if_needed()


# ─── Trash helpers ────────────────────────────────────────────────────────────

_TRASH_MAX_DAYS = 30


def _validate_trash_path(trash_path_str: str) -> Path:
    """Ensure a stored trash_path is actually inside trash_dir (prevents metadata tampering)."""
    p = Path(trash_path_str).resolve()
    trash_resolved = settings.trash_dir.resolve()
    if p != trash_resolved and not str(p).startswith(str(trash_resolved) + os.sep):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Invalid trash path")
    return p


async def _purge_trash_if_needed() -> None:
    """Auto-purge oldest trash items when trash exceeds 10% of NAS capacity or items >30 days old."""
    try:
        usage = shutil.disk_usage(settings.nas_root)
        quota_bytes = usage.total * 0.10
    except Exception:
        quota_bytes = float("inf")

    now = datetime.now(timezone.utc)
    items = await store.get_trash_items()
    to_keep: list[dict] = []

    # First pass: drop items older than TRASH_MAX_DAYS regardless of quota
    for item in items:
        try:
            deleted_at = datetime.fromisoformat(item["deletedAt"])
            if deleted_at.tzinfo is None:
                deleted_at = deleted_at.replace(tzinfo=timezone.utc)
            age_days = (now - deleted_at).days
        except Exception:
            age_days = 0

        if age_days >= _TRASH_MAX_DAYS:
            _unlink_trash_item(item)
        else:
            to_keep.append(item)

    # Second pass: purge oldest until total trash size is under quota
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


@router.put("/rename", status_code=status.HTTP_204_NO_CONTENT)
async def rename_file(body: RenameRequest, user: dict = Depends(get_current_user)):
    """Rename a file or directory."""
    _require_external_storage()
    if not body.new_name.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Name cannot be empty")

    # Reject names containing path separators to prevent traversal via rename
    safe_new_name = Path(body.new_name).name
    if safe_new_name != body.new_name.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid file name")

    resolved = _safe_resolve(body.old_path)
    if not resolved.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")

    new_path = resolved.parent / safe_new_name
    # Verify new path is still inside NAS root
    nas_resolved = settings.nas_root.resolve()
    if new_path.resolve() != nas_resolved and not str(new_path.resolve()).startswith(str(nas_resolved) + os.sep):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")
    if new_path.exists():
        raise HTTPException(status.HTTP_409_CONFLICT, "A file with that name already exists")

    resolved.rename(new_path)


@router.post("/upload", status_code=status.HTTP_201_CREATED)
async def upload_file(
    path: str = Query("", description="Ignored — files always land in user's .inbox/ for auto-sorting"),
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    """
    Upload a file via multipart form data.
    All uploads are placed in the authenticated user's personal .inbox/ directory
    where the InboxWatcher will auto-sort them into Photos/Videos/Documents/Others.
    """
    _require_external_storage()
    # Device-type tokens (pairing) cannot upload files
    if user.get("type") == "device":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Device tokens cannot upload files")
    # Resolve the user's personal .inbox/ directory
    user_record = await store.find_user(user.get("sub", ""))
    if user_record is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "User not found")
    safe_username = Path(user_record["name"]).name
    dest_dir = settings.personal_path / safe_username / ".inbox"
    dest_dir.mkdir(parents=True, exist_ok=True)

    # Sanitize filename: strip path separators to prevent directory traversal
    raw_name = file.filename or "upload"
    safe_name = Path(raw_name).name  # strips any directory components
    if not safe_name or safe_name in (".", ".."):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid filename")

    # Block executable and dangerous file types — check before any disk I/O
    ext = Path(safe_name).suffix.lower()
    if ext in BLOCKED_EXTENSIONS:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            f"File type '{ext}' is not allowed for security reasons.",
        )

    dest_file = dest_dir / safe_name
    # Final safety check: ensure resolved path is still within NAS root
    resolved_dest = dest_file.resolve()
    if not str(resolved_dest).startswith(str(settings.nas_root.resolve())):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")

    total = 0
    max_bytes = settings.max_upload_bytes

    with open(resolved_dest, "wb") as f:
        while chunk := await file.read(settings.upload_chunk_size):
            total += len(chunk)
            if max_bytes and total > max_bytes:
                f.close()
                resolved_dest.unlink(missing_ok=True)
                raise HTTPException(
                    status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    f"File exceeds maximum upload size of {max_bytes // (1024*1024)} MB",
                )
            f.write(chunk)

    # Notify connected clients
    user_name = user.get("sub", "unknown")
    await emit_upload_complete(safe_name, user_name)

    return {
        "name": safe_name,
        "path": "/" + str(resolved_dest.relative_to(settings.nas_root.resolve())).replace("\\", "/"),
        "sizeBytes": total,
    }


@router.get("/download")
async def download_file(
    path: str = Query(..., description="NAS path to the file to download"),
    user: dict = Depends(get_current_user),
):
    """
    Download a file from the NAS.
    Returns the raw file with appropriate Content-Disposition header.
    """
    _require_external_storage()
    resolved = _safe_resolve(path)

    if not resolved.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
    if resolved.is_dir():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Cannot download a directory")

    mime, _ = mimetypes.guess_type(resolved.name)

    return FileResponse(
        path=str(resolved),
        filename=resolved.name,
        media_type=mime or "application/octet-stream",
    )


@router.get("/search")
async def search_files(
    q: str = Query(..., min_length=1, max_length=200, description="Full-text search query"),
    limit: int = Query(10, ge=1, le=50),
    user: dict = Depends(get_current_user),
):
    """
    Full-text search over indexed documents in the NAS.
    Admins see all results; regular users see only their own and shared documents.
    """
    from ..document_index import search_documents

    username = user.get("sub", "")
    user_role = "admin" if user.get("is_admin") or user.get("type") == "device" else "member"
    results = await search_documents(query=q, limit=limit, user_role=user_role, username=username)
    return {"results": results, "query": q, "count": len(results)}


@router.get("/roots")
async def storage_roots(user: dict = Depends(get_current_user)):
    """Return browseable storage roots — mounted USB/NVMe drives."""
    from .storage_helpers import build_device_list, flatten_devices, list_block_devices

    raw = await list_block_devices()
    devices = build_device_list(flatten_devices(raw))
    roots = []
    for dev in devices:
        if dev.mounted and dev.mount_point:
            roots.append({
                "name": dev.label or dev.model or dev.name,
                "path": dev.mount_point,
                "device": dev.path,
                "transport": dev.transport,
                "sizeBytes": dev.size_bytes,
                "sizeDisplay": dev.size_display,
                "fstype": dev.fstype or "",
                "label": dev.label or "",
                "model": dev.model or "",
            })
    return {"roots": roots}
