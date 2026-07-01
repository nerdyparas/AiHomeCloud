"""
File management routes — list, mkdir, delete, rename, upload, download.
All paths are sandboxed under settings.nas_root.
External storage must be mounted at nas_root; SD card fallback is blocked.
"""

import asyncio
import hashlib
import io
import logging
import mimetypes
from urllib.parse import quote
import os
import shutil
import subprocess
import uuid
from datetime import datetime, timezone
from functools import partial
from pathlib import Path

from PIL import Image, ImageOps

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query, status
from starlette.requests import Request
from starlette.responses import Response, StreamingResponse

from ..auth import get_current_user, require_admin
from ..audit import audit_log
from ..config import settings
from ..models import CreateFolderRequest, FileItem, FileListResponse, RenameRequest
from .. import store
from ..job_store import JobStatus, create_job, update_job
from ..file_sorter import _destination_folder
from ..events import file_event_bus, FileEvent
from ..limiter import limiter
from .event_routes import emit_upload_complete

logger = logging.getLogger("aihomecloud.files")

# Larger write buffer for uploads — 2 MB (fewer syscalls on ARM)
_UPLOAD_WRITE_BUF = 2 * 1024 * 1024

# Short-lived scandir result cache.  Key: "<resolved_dir>|<sort_by>|<sort_dir>|<page>|<page_size>"
# Value: (result_tuple, expires_at_monotonic)
import time as _time
_scan_cache: dict[str, tuple] = {}
_SCAN_TTL = 7.0        # seconds
_SCAN_CACHE_MAX = 500  # maximum entries; prevents unbounded growth on busy NAS

_THUMB_IMAGE_EXTS: frozenset[str] = frozenset({
    ".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".tiff", ".tif", ".gif"
})
_THUMB_VIDEO_EXTS: frozenset[str] = frozenset({
    ".mp4", ".mov", ".m4v", ".3gp", ".mkv", ".avi", ".webm"
})
_THUMB_FFMPEG: str = "/usr/bin/ffmpeg"
_THUMB_MAX_AGE: int = 86400



def _invalidate_scan_cache(dir_path: str) -> None:
    """Remove every cache entry for the given directory."""
    prefix = dir_path + "|"
    to_del = [k for k in _scan_cache if k.startswith(prefix)]
    for k in to_del:
        _scan_cache.pop(k, None)


def _evict_expired_scan_cache() -> None:
    """Remove expired entries; then evict oldest if over the size cap."""
    now = _time.monotonic()
    stale = [k for k, (_, exp) in _scan_cache.items() if now >= exp]
    for k in stale:
        _scan_cache.pop(k, None)
    # Size cap: drop the oldest insertion-order entries until under the limit.
    while len(_scan_cache) >= _SCAN_CACHE_MAX:
        _scan_cache.pop(next(iter(_scan_cache)))


def _calc_dir_size(path: Path) -> int:
    """Calculate total size of all files under a directory. Designed to run in a thread executor."""
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
router = APIRouter(prefix="/api/v1/files", tags=["files"])

# Executables and dangerous file types that must never be uploaded to the NAS.
BLOCKED_EXTENSIONS: frozenset[str] = frozenset({
    ".sh", ".bash", ".zsh", ".fish",
    ".py", ".rb", ".pl", ".php",
    ".elf", ".bin", ".exe",
    ".apk", ".so", ".ko",
    ".deb", ".rpm",
})


def _is_documents_scoped(path: Path) -> bool:
    """True when path is in a Documents folder (or is that folder)."""
    return path.name == "Documents" or "Documents" in path.parts


def _is_document_file(path: Path) -> bool:
    from ..document_index import is_indexable_document_path

    return _is_documents_scoped(path) and is_indexable_document_path(path)


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
    Resolve a NAS-relative path (e.g. /srv/nas/family/Photos) to an
    absolute filesystem path, ensuring it stays within nas_root.
    """
    # Reject null bytes early — they can confuse OS path operations
    if "\x00" in raw_path:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")

    # Reject excessively long paths before touching the filesystem
    if len(raw_path) > 4096:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Path too long")

    # raw_path from the app looks like /srv/nas/family/...
    # Strip the nas_root prefix if present so we don't double it.
    nas_prefix = str(settings.nas_root)
    if raw_path.startswith(nas_prefix):
        boundary = len(nas_prefix)
        if len(raw_path) == boundary or raw_path[boundary] in ("/", "\\"):
            raw_path = raw_path[boundary:]

    candidate = settings.nas_root / raw_path.lstrip("/")

    # Reject symlinks — they could point outside the NAS root
    if candidate.is_symlink():
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Symbolic links are not allowed")

    try:
        resolved = candidate.resolve()
    except (OSError, ValueError):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")

    nas_resolved = settings.nas_root.resolve()
    try:
        resolved.relative_to(nas_resolved)
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")
    return resolved


async def _resolve_identity(user: dict) -> tuple[str, bool]:
    """Resolve the authenticated principal to (personal_folder_name, is_admin).

    Paired-device tokens carry no personal folder and are admin-level. A valid
    JWT whose user has since been deleted is rejected.
    """
    if user.get("type") == "device":
        return "", True
    found = await store.find_user(user.get("sub", ""))
    if not found:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User no longer exists")
    return found.get("name", ""), bool(found.get("is_admin", False))


async def _authorize_path(resolved: Path, user: dict) -> None:
    """Enforce that ``/personal/<name>/`` subtrees are private to their owner.

    Shared scopes (family, sync, entertainment, …) stay open to every
    authenticated user; only the ``/personal/<name>/`` tree is owner-restricted
    (admins and paired devices bypass). Must be called AFTER ``_safe_resolve``.
    """
    rel_parts = resolved.relative_to(settings.nas_root.resolve()).parts
    if len(rel_parts) < 2 or rel_parts[0] != "personal":
        return  # shared location — no per-user restriction
    owner = rel_parts[1]
    name, is_admin = await _resolve_identity(user)
    if is_admin or Path(name).name == owner:
        return
    raise HTTPException(
        status.HTTP_403_FORBIDDEN,
        "Access to another user's personal files is not allowed",
    )


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


def _scandir_list(resolved: Path, nas_root_str: str, sort_key: str, reverse: bool, page: int, page_size: int) -> tuple:
    """Run in thread pool: scandir + sort + paginate without blocking the event loop.

    Uses os.scandir() which is significantly faster than Path.iterdir() + stat()
    because it reads directory entries and their stat info in a single syscall
    per entry (on Linux, via getdents + fstatat cached in the dirent).
    """
    entries = []
    try:
        with os.scandir(resolved) as it:
            for entry in it:
                try:
                    st = entry.stat(follow_symlinks=False)
                    is_dir = entry.is_dir(follow_symlinks=False)
                    name = entry.name
                    rel = os.path.relpath(entry.path, nas_root_str)
                    nas_path = "/" + rel.replace("\\", "/")
                    if is_dir and not nas_path.endswith("/"):
                        nas_path += "/"
                    mime, _ = mimetypes.guess_type(name)
                    entries.append({
                        "name": name,
                        "path": nas_path,
                        "isDirectory": is_dir,
                        "sizeBytes": 0 if is_dir else st.st_size,
                        "modified": datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).isoformat(),
                        "mimeType": mime,
                    })
                except OSError:
                    continue
    except OSError:
        pass

    # Sort
    if sort_key == "modified":
        entries.sort(key=lambda i: i.get("modified") or "", reverse=reverse)
    elif sort_key == "size":
        entries.sort(key=lambda i: i.get("sizeBytes") or 0, reverse=reverse)
    else:
        entries.sort(key=lambda i: ((i["name"] or "").casefold(), i["name"] or ""), reverse=reverse)

    total_count = len(entries)
    start = page * page_size
    paged = entries[start:start + page_size]
    return paged, total_count


@router.get("/list", response_model=FileListResponse)
@limiter.limit("60/minute")
async def list_files(
    request: Request,
    path: str = Query("/srv/nas/family/"),
    page: int = Query(0, ge=0),
    page_size: int = Query(50, ge=1, le=500, alias="page_size"),
    sort_by: str = Query("name"),
    sort_dir: str = Query("asc"),
    user: dict = Depends(get_current_user),
):
    """List files and folders at the given NAS path."""
    _require_external_storage()
    resolved = _safe_resolve(path)
    await _authorize_path(resolved, user)

    if not resolved.exists():
        resolved.mkdir(parents=True, exist_ok=True)

    if not resolved.is_dir():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Path is not a directory")

    loop = asyncio.get_running_loop()
    nas_root_str = str(settings.nas_root.resolve())
    cache_key = f"{str(resolved)}|{sort_by}|{sort_dir}|{page}|{page_size}"
    now = _time.monotonic()
    cached = _scan_cache.get(cache_key)
    if cached and now < cached[1]:
        paged, total_count = cached[0]
    else:
        paged, total_count = await loop.run_in_executor(
            None,
            partial(_scandir_list, resolved, nas_root_str,
                    sort_by.lower(), sort_dir.lower() == "desc",
                    page, page_size),
        )
        _evict_expired_scan_cache()
        _scan_cache[cache_key] = ((paged, total_count), now + _SCAN_TTL)

    return FileListResponse(
        items=[FileItem(**i) for i in paged],
        totalCount=total_count,
        page=page,
        pageSize=page_size,
    )


@router.post("/mkdir", status_code=status.HTTP_201_CREATED)
@limiter.limit("60/minute")
async def create_folder(request: Request, body: CreateFolderRequest, user: dict = Depends(get_current_user)):
    """Create a new directory."""
    _require_external_storage()
    resolved = _safe_resolve(body.path)
    await _authorize_path(resolved, user)
    if resolved.exists():
        raise HTTPException(status.HTTP_409_CONFLICT, "Folder already exists")
    resolved.mkdir(parents=True, exist_ok=True)
    _invalidate_scan_cache(str(resolved.parent))
    return {"path": body.path}


@router.delete("/delete", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("60/minute")
async def delete_file(
    request: Request,
    path: str = Query(...),
    user: dict = Depends(get_current_user),
):
    """Soft-delete: move file/directory to the per-user trash folder."""
    _require_external_storage()
    resolved = _safe_resolve(path)
    await _authorize_path(resolved, user)
    if not resolved.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")

    user_id = user.get("sub", "")
    filename = resolved.name
    ts = int(datetime.now(timezone.utc).timestamp())
    trash_name = f"{ts}_{filename}"

    # Per-user trash directory: {nas_root}/.ahc_trash/{user_id}/
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
        loop = asyncio.get_running_loop()
        size_bytes = await loop.run_in_executor(None, _calc_dir_size, resolved)

    item = {
        "id": str(uuid.uuid4()),
        "originalPath": path,
        "trashPath": str(trash_path),
        "filename": filename,
        "deletedAt": datetime.now(timezone.utc).isoformat(),
        "sizeBytes": size_bytes,
        "deletedBy": user_id,
    }

    # Write metadata FIRST — if the move fails we can roll it back cleanly.
    items = await store.get_trash_items()
    items.append(item)
    await store.save_trash_items(items)

    try:
        shutil.move(str(resolved), str(trash_path))
    except Exception:
        # Rollback: remove the item we just appended and re-save.
        items = [i for i in items if i["id"] != item["id"]]
        await store.save_trash_items(items)
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "Failed to move file to trash")

    _invalidate_scan_cache(str(resolved.parent))

    # Keep document index in sync with soft-delete operations.
    from ..document_index import remove_document, remove_documents_by_prefix
    if resolved.is_file() and _is_documents_scoped(resolved):
        await remove_document(path)
    elif resolved.is_dir() and _is_documents_scoped(resolved):
        await remove_documents_by_prefix(path)

    audit_log("file_deleted", actor_id=user_id, path=path, file_name=filename, size_bytes=size_bytes)

    # Publish file-event for downstream consumers (AI features, audit log)
    await file_event_bus.publish(FileEvent(
        path=path,
        action="delete",
        user=user_id,
    ))

    # Run trash purge in background — don't block the delete response
    from .trash_routes import _safe_purge_trash
    asyncio.create_task(_safe_purge_trash())


@router.put("/rename", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("60/minute")
async def rename_file(request: Request, body: RenameRequest, user: dict = Depends(get_current_user)):
    """Rename a file or directory."""
    _require_external_storage()
    if not body.new_name.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Name cannot be empty")

    # Reject names containing path separators to prevent traversal via rename
    safe_new_name = Path(body.new_name).name
    if safe_new_name != body.new_name.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid file name")
    if not safe_new_name or safe_new_name in (".", ".."):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid file name")
    # Block renaming to dangerous extensions
    rename_suffixes = [s.lower() for s in Path(safe_new_name).suffixes]
    for ext in rename_suffixes:
        if ext in BLOCKED_EXTENSIONS:
            raise HTTPException(
                status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                f"Renaming to '{ext}' is not allowed for security reasons.",
            )

    resolved = _safe_resolve(body.old_path)
    await _authorize_path(resolved, user)
    if not resolved.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")

    new_path = resolved.parent / safe_new_name
    # Verify new path is still inside NAS root
    nas_resolved = settings.nas_root.resolve()
    try:
        new_path.resolve().relative_to(nas_resolved)
    except ValueError:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")
    if new_path.exists():
        raise HTTPException(status.HTTP_409_CONFLICT, "A file with that name already exists")

    was_file = resolved.is_file()
    was_dir = resolved.is_dir()
    resolved.rename(new_path)
    _invalidate_scan_cache(str(resolved.parent))

    # Keep index paths aligned after rename/move.
    from ..document_index import (
        index_document,
        index_documents_under_path,
        remove_document,
        remove_documents_by_prefix,
    )
    added_by = user.get("sub", "unknown")
    if was_file and (_is_documents_scoped(resolved) or _is_documents_scoped(new_path)):
        await remove_document(str(resolved))
        if _is_document_file(new_path):
            await index_document(str(new_path), new_path.name, added_by)
    elif was_dir and (_is_documents_scoped(resolved) or _is_documents_scoped(new_path)):
        await remove_documents_by_prefix(str(resolved))
        if _is_documents_scoped(new_path):
            await index_documents_under_path(str(new_path), added_by)


def _extract_capture_epoch(file_path: Path):
    """Return the media's embedded capture time (epoch seconds), or None."""
    suffix = file_path.suffix.lower()
    if suffix in (".jpg", ".jpeg", ".png", ".webp", ".tiff", ".tif", ".heic", ".heif"):
        try:
            from PIL import Image

            with Image.open(file_path) as img:
                exif = img.getexif()
                try:
                    exif_ifd = exif.get_ifd(0x8769)
                except Exception:
                    exif_ifd = {}
                for src, tag in ((exif_ifd, 36867), (exif_ifd, 36868), (exif, 306)):
                    raw = src.get(tag)
                    if raw:
                        return datetime.strptime(str(raw).strip(), "%Y:%m:%d %H:%M:%S").timestamp()
        except Exception:
            return None
        return None
    if suffix in (".mp4", ".mov", ".m4v", ".3gp", ".mkv", ".avi", ".webm"):
        if not shutil.which("ffprobe"):
            return None
        try:
            out = subprocess.run(
                ["ffprobe", "-v", "quiet", "-show_entries", "format_tags=creation_time",
                 "-of", "default=nw=1:nk=1", str(file_path)],
                capture_output=True, text=True, timeout=15,
            ).stdout.strip()
            if out:
                return datetime.fromisoformat(out.replace("Z", "+00:00")).timestamp()
        except Exception:
            return None
    return None


def _apply_capture_time(file_path: Path, fallback_epoch=None) -> None:
    """Best-effort: set the file mtime to its capture time so listings group/sort by when the
    media was taken. Prefers the embedded EXIF/ffprobe date; falls back to the client-supplied
    original date (e.g. phone MediaStore date); else leaves the upload time. Never raises."""
    try:
        ts = _extract_capture_epoch(file_path)
        if ts is None and fallback_epoch and float(fallback_epoch) > 0:
            ts = float(fallback_epoch)
        if ts:
            os.utime(file_path, (ts, ts))
    except Exception:
        pass


@router.post("/upload", status_code=status.HTTP_201_CREATED)
@limiter.limit("120/minute")
async def upload_file(
    request: Request,
    path: str = Query("", description="Destination directory (NAS-absolute). If empty, falls back to user's .inbox/ for auto-sorting."),
    original_date: float | None = Query(None, description="Client-supplied original capture time (epoch seconds), used when the file has no embedded date."),
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    """
    Upload a file via multipart form data.
    When *path* points to a valid NAS directory the file is written there directly.
    When *path* is empty the file lands in the user's personal .inbox/ directory
    where the InboxWatcher will auto-sort it into Photos/Videos/Documents/Others.
    """
    _require_external_storage()
    # Device-type tokens (pairing) cannot upload files
    if user.get("type") == "device":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Device tokens cannot upload files")

    user_record = await store.find_user(user.get("sub", ""))
    if user_record is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "User not found")
    safe_username = Path(user_record["name"]).name

    # Determine destination: honour explicit path when it resolves to a NAS directory.
    use_inbox = True
    if path and path.strip():
        resolved_dir = _safe_resolve(path)
        await _authorize_path(resolved_dir, user)
        if resolved_dir.is_dir():
            dest_dir = resolved_dir
            use_inbox = False
    if use_inbox:
        dest_dir = settings.personal_path / safe_username / ".inbox"
    dest_dir.mkdir(parents=True, exist_ok=True)

    # Sanitize filename: strip path separators to prevent directory traversal
    raw_name = file.filename or "upload"
    safe_name = Path(raw_name).name  # strips any directory components
    if not safe_name or safe_name in (".", ".."):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid filename")

    # Block executable and dangerous file types — check ALL suffixes, not just last
    all_suffixes = [s.lower() for s in Path(safe_name).suffixes]
    for ext in all_suffixes:
        if ext in BLOCKED_EXTENSIONS:
            raise HTTPException(
                status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                f"File type '{ext}' is not allowed for security reasons.",
            )

    dest_file = dest_dir / safe_name
    # Final safety check: ensure resolved path is still within NAS root
    resolved_dest = dest_file.resolve()
    if not resolved_dest.is_relative_to(settings.nas_root.resolve()):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")

    total = 0
    max_bytes = settings.max_upload_bytes
    loop = asyncio.get_running_loop()

    # Write to .uploading temp path so the file sorter skips in-progress uploads.
    uploading_dest = resolved_dest.with_name(resolved_dest.name + ".uploading")

    # Use buffered I/O and write in the thread pool to avoid blocking the event loop.
    fd = open(uploading_dest, "wb", buffering=_UPLOAD_WRITE_BUF)
    try:
        while chunk := await file.read(settings.upload_chunk_size):
            total += len(chunk)
            if max_bytes and total > max_bytes:
                fd.close()
                uploading_dest.unlink(missing_ok=True)
                raise HTTPException(
                    status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    f"File exceeds maximum upload size of {max_bytes // (1024*1024)} MB",
                )
            await loop.run_in_executor(None, fd.write, chunk)
    except Exception:
        fd.close()
        uploading_dest.unlink(missing_ok=True)
        raise
    finally:
        fd.close()

    # Rename from .uploading to final path atomically
    uploading_dest.rename(resolved_dest)

    # Preserve the media's original capture time (best-effort; falls back to upload time).
    _apply_capture_time(resolved_dest, original_date)

    # Fire-and-forget notifications so the upload response returns immediately.
    user_name = user.get("sub", "unknown")
    asyncio.create_task(_post_upload_notify(safe_name, user_name, str(resolved_dest)))
    _invalidate_scan_cache(str(dest_dir))

    # Direct uploads to Documents bypass .inbox; index them immediately.
    if not use_inbox and _is_document_file(resolved_dest):
        from ..document_index import index_document

        asyncio.create_task(
            index_document(str(resolved_dest), safe_name, user_name),
            name=f"index_upload_{safe_name}",
        )

    # When written directly to a folder (not .inbox), no auto-sort will happen.
    sorted_to = None if not use_inbox else _destination_folder(resolved_dest)

    return {
        "name": safe_name,
        "path": "/" + str(resolved_dest.relative_to(settings.nas_root.resolve())).replace("\\", "/"),
        "sizeBytes": total,
        "sortedTo": sorted_to,
    }


@router.post("/upload-stream", status_code=status.HTTP_201_CREATED)
@limiter.limit("120/minute")
async def upload_file_stream(
    request: Request,
    filename: str = Query(..., min_length=1, max_length=512),
    path: str = Query("", description="Destination directory (NAS-absolute). Empty → user .inbox/."),
    original_date: float | None = Query(None, description="Client-supplied original capture time (epoch seconds)."),
    user: dict = Depends(get_current_user),
):
    """
    Upload a file by streaming the raw request body (Content-Type: application/octet-stream).

    Bypasses Starlette's multipart SpooledTemporaryFile buffering entirely — data flows
    directly from the TCP socket to the destination file with zero intermediate copies.
    Use this endpoint for large files (>1 GB) from the web portal.
    """
    _require_external_storage()
    if user.get("type") == "device":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Device tokens cannot upload files")

    user_record = await store.find_user(user.get("sub", ""))
    if user_record is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "User not found")
    safe_username = Path(user_record["name"]).name

    use_inbox = True
    if path and path.strip():
        resolved_dir = _safe_resolve(path)
        await _authorize_path(resolved_dir, user)
        if resolved_dir.is_dir():
            dest_dir = resolved_dir
            use_inbox = False
    if use_inbox:
        dest_dir = settings.personal_path / safe_username / ".inbox"
    dest_dir.mkdir(parents=True, exist_ok=True)

    safe_name = Path(filename).name
    if not safe_name or safe_name in (".", ".."):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid filename")

    for ext in [s.lower() for s in Path(safe_name).suffixes]:
        if ext in BLOCKED_EXTENSIONS:
            raise HTTPException(
                status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                f"File type '{ext}' is not allowed for security reasons.",
            )

    resolved_dest = (dest_dir / safe_name).resolve()
    if not resolved_dest.is_relative_to(settings.nas_root.resolve()):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")

    total = 0
    max_bytes = settings.max_upload_bytes
    loop = asyncio.get_running_loop()
    uploading_dest = resolved_dest.with_name(resolved_dest.name + ".uploading")

    fd = open(uploading_dest, "wb", buffering=_UPLOAD_WRITE_BUF)
    wrote_ok = False
    try:
        async for chunk in request.stream():
            if not chunk:
                continue
            total += len(chunk)
            if max_bytes and total > max_bytes:
                raise HTTPException(
                    status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    f"File exceeds maximum upload size of {max_bytes // (1024 * 1024)} MB",
                )
            await loop.run_in_executor(None, fd.write, chunk)
        wrote_ok = True
    finally:
        # Bug fix 1 & 3: close exactly once, in run_in_executor so it never
        # blocks the event loop (flush + close can stall on USB3/HDD under load).
        await loop.run_in_executor(None, fd.close)
        if not wrote_ok:
            uploading_dest.unlink(missing_ok=True)

    # Bug fix 2: rename is a syscall — run it off the event loop.
    await loop.run_in_executor(None, uploading_dest.rename, resolved_dest)

    # Preserve the media's original capture time (best-effort; falls back to upload time).
    _apply_capture_time(resolved_dest, original_date)

    user_name = user.get("sub", "unknown")
    asyncio.create_task(_post_upload_notify(safe_name, user_name, str(resolved_dest)))
    _invalidate_scan_cache(str(dest_dir))

    if not use_inbox and _is_document_file(resolved_dest):
        from ..document_index import index_document
        asyncio.create_task(
            index_document(str(resolved_dest), safe_name, user_name),
            name=f"index_upload_{safe_name}",
        )

    sorted_to = None if not use_inbox else _destination_folder(resolved_dest)
    return {
        "name": safe_name,
        "path": "/" + str(resolved_dest.relative_to(settings.nas_root.resolve())).replace("\\", "/"),
        "sizeBytes": total,
        "sortedTo": sorted_to,
    }


async def _post_upload_notify(safe_name: str, user_name: str, resolved_path: str) -> None:
    """Fire-and-forget: emit upload event + file event after response is sent."""
    try:
        await emit_upload_complete(safe_name, user_name)
        await file_event_bus.publish(FileEvent(
            path=resolved_path,
            action="upload",
            user=user_name,
        ))
    except Exception:
        pass  # best-effort notification


@router.get("/download")
@limiter.limit("120/minute")
async def download_file(
    request: Request,
    path: str = Query(..., description="NAS path to the file to download"),
    user: dict = Depends(get_current_user),
):
    """
    Download or stream a file from the NAS.
    Supports HTTP Range requests (RFC 7233) for video/audio seeking and resumable downloads.
    Responds with 206 Partial Content for range requests, 200 OK for full file.
    """
    _require_external_storage()
    resolved = _safe_resolve(path)
    await _authorize_path(resolved, user)

    if not resolved.exists():
        from ..document_index import remove_document
        await remove_document(path)
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
    if resolved.is_dir():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Cannot download a directory")

    mime, _ = mimetypes.guess_type(resolved.name)
    file_size = resolved.stat().st_size

    ascii_name = resolved.name.encode("ascii", errors="replace").decode("ascii")
    utf8_name = quote(resolved.name.encode("utf-8"), safe="")
    content_disposition = (
        'inline; filename="' + ascii_name + '"; filename*=UTF-8\'\'' + utf8_name
    )

    range_header = request.headers.get("Range")

    if range_header:
        try:
            if not range_header.startswith("bytes="):
                raise ValueError("unsupported range unit")
            # Take the first range spec only (multi-range not supported)
            range_spec = range_header[6:].split(",")[0].strip()
            start_str, _, end_str = range_spec.partition("-")
            start_str = start_str.strip()
            end_str = end_str.strip()

            if start_str == "" and end_str == "":
                raise ValueError("empty range spec")
            elif start_str == "":
                # suffix range: bytes=-N means last N bytes
                start = max(0, file_size - int(end_str))
                end = file_size - 1
            elif end_str == "":
                # open-ended: bytes=N- means from N to EOF
                start = int(start_str)
                end = file_size - 1
            else:
                start = int(start_str)
                end = int(end_str)

            if start < 0 or end >= file_size or start > end:
                raise ValueError("range out of bounds")

        except (ValueError, IndexError):
            return Response(
                status_code=416,
                headers={
                    "Content-Range": f"bytes */{file_size}",
                    "Accept-Ranges": "bytes",
                },
            )

        content_length = end - start + 1

        def _range_stream():
            _remaining = content_length
            with open(resolved, "rb") as fh:
                fh.seek(start)
                while _remaining > 0:
                    data = fh.read(min(262_144, _remaining))
                    if not data:
                        break
                    _remaining -= len(data)
                    yield data

        return StreamingResponse(
            _range_stream(),
            status_code=206,
            media_type=mime or "application/octet-stream",
            headers={
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Content-Length": str(content_length),
                "Content-Disposition": content_disposition,
                "Accept-Ranges": "bytes",
            },
        )

    # No Range header — stream the full file
    def _full_stream():
        with open(resolved, "rb") as fh:
            while True:
                data = fh.read(262_144)
                if not data:
                    break
                yield data

    return StreamingResponse(
        _full_stream(),
        media_type=mime or "application/octet-stream",
        headers={
            "Content-Length": str(file_size),
            "Content-Disposition": content_disposition,
            "Accept-Ranges": "bytes",
        },
    )


@router.get("/search")
@limiter.limit("120/minute")
async def search_files(
    request: Request,
    q: str = Query(..., min_length=1, max_length=200, description="Full-text search query"),
    limit: int = Query(10, ge=1, le=50),
    user: dict = Depends(get_current_user),
):
    """
    Full-text search over indexed documents in the NAS.
    Admins see all results; regular users see only their own and shared documents.
    """
    from ..document_index import search_documents

    # The JWT carries only the user id (sub) — resolve the real personal-folder
    # name and admin flag from the store, else members match nothing of their own
    # and admins are wrongly treated as members.
    name, is_admin = await _resolve_identity(user)
    user_role = "admin" if is_admin else "member"
    results = await search_documents(query=q, limit=limit, user_role=user_role, username=name)
    return {"results": results, "query": q, "count": len(results)}


@router.post("/sort-now")
@limiter.limit("10/minute")
async def sort_now(
    request: Request,
    path: str = Query(..., description="NAS directory path to sort immediately"),
    user: dict = Depends(get_current_user),
):
    """
    Manually sort an existing folder into Photos/Videos/Documents/Others.
    Useful for bulk imports copied directly onto NAS (outside .inbox).
    """
    _require_external_storage()
    resolved = _safe_resolve(path)
    await _authorize_path(resolved, user)
    if not resolved.exists() or not resolved.is_dir():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Directory not found")

    from ..file_sorter import sort_folder_now

    added_by = user.get("sub", "unknown")
    stats = await sort_folder_now(resolved, added_by=added_by)
    nas_path = "/" + str(resolved.relative_to(settings.nas_root.resolve())).replace("\\", "/")
    return {
        "path": nas_path,
        **stats,
    }


@router.get("/roots")
async def storage_roots(user: dict = Depends(get_current_user)):
    """Return browseable storage roots — mounted USB/NVMe drives."""
    from .storage_helpers import build_device_list, list_block_devices

    raw = await list_block_devices()
    devices = build_device_list(raw)
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


def _thumb_cache_path(resolved: Path, mtime: float, size: int) -> Path:
    """Return the on-disk cache path for a thumbnail."""
    key = hashlib.sha256(f"{resolved}\x00{mtime}\x00{size}".encode()).hexdigest()
    return settings.data_dir / "thumb_cache" / f"{key}.jpg"


async def _generate_image_thumbnail(resolved: Path, size: int) -> bytes:
    """Generate a JPEG thumbnail from an image using Pillow."""
    def _make() -> bytes:
        with Image.open(resolved) as img:
            img = ImageOps.exif_transpose(img)
            img.thumbnail((size, size), Image.Resampling.LANCZOS)
            buf = io.BytesIO()
            img.convert("RGB").save(buf, format="JPEG", quality=80, optimize=True)
            return buf.getvalue()

    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, _make)


async def _generate_video_thumbnail(resolved: Path, size: int) -> bytes:
    """Generate a JPEG thumbnail by grabbing a single frame with ffmpeg."""
    def _grab(seek: str) -> bytes:
        proc = subprocess.run(
            [
                _THUMB_FFMPEG,
                "-ss", seek,
                "-i", str(resolved),
                "-frames:v", "1",
                "-vf", f"scale='min({size},iw)':-2",
                "-f", "mjpeg",
                "-",
            ],
            capture_output=True,
            timeout=15,
        )
        if proc.returncode != 0 or not proc.stdout:
            return b""
        return proc.stdout

    def _make() -> bytes:
        # Short clips or odd keyframe layouts yield nothing at 1s — fall back to frame 0.
        for seek in ("1", "0"):
            out = _grab(seek)
            if out:
                return out
        raise RuntimeError("ffmpeg thumbnail failed")

    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, _make)


@router.get("/thumbnail")
@limiter.limit("120/minute")
async def thumbnail(
    request: Request,
    path: str = Query(..., description="NAS path to the image or video"),
    size: int = Query(256, description="Max thumbnail edge in pixels"),
    user: dict = Depends(get_current_user),
):
    """Return a small cached JPEG thumbnail for an image or video file."""
    _require_external_storage()
    resolved = _safe_resolve(path)
    await _authorize_path(resolved, user)

    if not resolved.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
    if resolved.is_dir():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Cannot thumbnail a directory")

    size = max(64, min(512, size))
    suffix = resolved.suffix.lower()
    src_stat = resolved.stat()
    cache_path = _thumb_cache_path(resolved, src_stat.st_mtime, size)

    try:
        if cache_path.exists() and cache_path.stat().st_mtime >= src_stat.st_mtime:
            data = cache_path.read_bytes()
            return Response(
                data,
                media_type="image/jpeg",
                headers={"Cache-Control": f"private, max-age={_THUMB_MAX_AGE}"},
            )
    except Exception:
        pass

    try:
        if suffix in _THUMB_IMAGE_EXTS:
            data = await _generate_image_thumbnail(resolved, size)
        elif suffix in _THUMB_VIDEO_EXTS:
            data = await _generate_video_thumbnail(resolved, size)
        else:
            raise HTTPException(
                status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                "Unsupported file type for thumbnail",
            )
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Thumbnail generation failed for %s: %s", path, exc)
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Thumbnail not available")

    try:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = cache_path.with_suffix(".tmp")
        tmp.write_bytes(data)
        tmp.replace(cache_path)
    except Exception as exc:
        logger.error("Failed to write thumbnail cache %s: %s", cache_path, exc)

    return Response(
        data,
        media_type="image/jpeg",
        headers={"Cache-Control": f"private, max-age={_THUMB_MAX_AGE}"},
    )


# Job IDs requested to cancel — the reindex loop checks this cooperatively between files.
_reindex_cancels: set[str] = set()


@router.post("/reindex", status_code=status.HTTP_202_ACCEPTED)
@limiter.limit("6/hour")
async def reindex_storage(request: Request, user: dict = Depends(require_admin)):
    """Admin: re-scan NAS storage and rebuild the search index to match the filesystem.

    The filesystem is the source of truth — this prunes index rows whose files are gone, then
    (re)indexes every supported file under the watched roots (documents + OCR text for images),
    so search reflects exactly what's on disk. Runs in the background; poll
    `GET /api/v1/jobs/{jobId}` for status (`running` -> `completed`/`failed`, with
    `result={indexed, pruned}`).
    """
    job = create_job(user_id=user.get("sub", ""))

    async def _run() -> None:
        try:
            update_job(job.id, status=JobStatus.running, progress={"current": 0, "total": 0})
            from pathlib import Path as _Path
            from ..document_index import remove_missing_documents, nas_paths_with_ocr, _to_nas_path
            from ..index_watcher import (
                sync_once, _load_persisted_state, _save_persisted_state, _scan_documents_sync,
            )
            pruned = await remove_missing_documents()

            def _progress(current: int, total: int) -> None:
                update_job(job.id, progress={"current": current, "total": total})

            # Re-OCR files that are NEW or indexed with EMPTY text (e.g. a prior OCR timeout), while
            # skipping files that already have good OCR — so re-scan actually FIXES gaps efficiently.
            loop = asyncio.get_running_loop()
            well = await nas_paths_with_ocr()
            current_files = await loop.run_in_executor(None, _scan_documents_sync)
            redo = {ap for ap in current_files if _to_nas_path(_Path(ap)) not in well}

            new_state = await sync_once(
                _load_persisted_state(),
                on_progress=_progress,
                should_cancel=lambda: job.id in _reindex_cancels,
                redo_paths=redo,
            )
            if job.id in _reindex_cancels:
                _reindex_cancels.discard(job.id)
                # Don't persist partial state — leave un-indexed files "new" for the next scan.
                update_job(job.id, status=JobStatus.failed, error="cancelled")
            else:
                _save_persisted_state(new_state)
                update_job(
                    job.id,
                    status=JobStatus.completed,
                    result={"indexed": len(new_state), "pruned": pruned},
                )
        except Exception as exc:  # surface any failure as a failed job, never crash the worker
            _reindex_cancels.discard(job.id)
            logger.error("reindex_failed error=%s", exc)
            update_job(job.id, status=JobStatus.failed, error=str(exc))

    asyncio.create_task(_run())
    return {"jobId": job.id, "status": "running"}


@router.post("/reindex/cancel")
async def cancel_reindex(request: Request, jobId: str = Query(...), user: dict = Depends(require_admin)):
    """Admin: request cancellation of a running re-scan (stops after the current batch of files)."""
    _reindex_cancels.add(jobId)
    return {"cancelled": jobId}
