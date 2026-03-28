"""
File management routes — list, mkdir, delete, rename, upload, download.
All paths are sandboxed under settings.nas_root.
External storage must be mounted at nas_root; SD card fallback is blocked.
"""

import asyncio
import mimetypes
import os
import shutil
import uuid
from datetime import datetime, timezone
from functools import partial
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query, status
from fastapi.responses import FileResponse
from starlette.requests import Request
from starlette.responses import StreamingResponse

from ..auth import get_current_user
from ..audit import audit_log
from ..config import settings
from ..models import CreateFolderRequest, FileItem, FileListResponse, RenameRequest
from .. import store
from ..file_sorter import _destination_folder
from ..events import file_event_bus, FileEvent
from ..limiter import limiter
from .event_routes import emit_upload_complete

# Larger write buffer for uploads — 2 MB (fewer syscalls on ARM)
_UPLOAD_WRITE_BUF = 2 * 1024 * 1024

# Short-lived scandir result cache.  Key: "<resolved_dir>|<sort_by>|<sort_dir>|<page>|<page_size>"
# Value: (result_tuple, expires_at_monotonic)
import time as _time
_scan_cache: dict[str, tuple] = {}
_SCAN_TTL = 7.0        # seconds
_SCAN_CACHE_MAX = 500  # maximum entries; prevents unbounded growth on busy NAS


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


@router.post("/upload", status_code=status.HTTP_201_CREATED)
@limiter.limit("20/minute")
async def upload_file(
    request: Request,
    path: str = Query("", description="Destination directory (NAS-absolute). If empty, falls back to user's .inbox/ for auto-sorting."),
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
    if not str(resolved_dest).startswith(str(settings.nas_root.resolve())):
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
@limiter.limit("20/minute")
async def upload_file_stream(
    request: Request,
    filename: str = Query(..., min_length=1, max_length=512),
    path: str = Query("", description="Destination directory (NAS-absolute). Empty → user .inbox/."),
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
    if not str(resolved_dest).startswith(str(settings.nas_root.resolve())):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")

    total = 0
    max_bytes = settings.max_upload_bytes
    loop = asyncio.get_running_loop()
    uploading_dest = resolved_dest.with_name(resolved_dest.name + ".uploading")

    fd = open(uploading_dest, "wb", buffering=_UPLOAD_WRITE_BUF)
    try:
        async for chunk in request.stream():
            if not chunk:
                continue
            total += len(chunk)
            if max_bytes and total > max_bytes:
                fd.close()
                uploading_dest.unlink(missing_ok=True)
                raise HTTPException(
                    status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    f"File exceeds maximum upload size of {max_bytes // (1024 * 1024)} MB",
                )
            await loop.run_in_executor(None, fd.write, chunk)
    except Exception:
        fd.close()
        uploading_dest.unlink(missing_ok=True)
        raise
    finally:
        fd.close()

    uploading_dest.rename(resolved_dest)

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
    Download a file from the NAS.
    Returns the raw file with appropriate Content-Disposition header.
    """
    _require_external_storage()
    resolved = _safe_resolve(path)

    if not resolved.exists():
        from ..document_index import remove_document

        await remove_document(path)
        raise HTTPException(status.HTTP_404_NOT_FOUND, "File not found")
    if resolved.is_dir():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Cannot download a directory")

    mime, _ = mimetypes.guess_type(resolved.name)
    file_size = resolved.stat().st_size

    # For files > 1 MB, use streaming response to avoid loading the full file
    # into memory before sending. For small files, FileResponse is fine.
    if file_size > 1_048_576:
        async def _stream_file():
            with open(resolved, "rb") as fh:
                while True:
                    chunk = fh.read(262_144)  # 256 KB chunks
                    if not chunk:
                        break
                    yield chunk

        return StreamingResponse(
            _stream_file(),
            media_type=mime or "application/octet-stream",
            headers={
                "Content-Disposition": f'attachment; filename="{resolved.name}"',
                "Content-Length": str(file_size),
            },
        )

    return FileResponse(
        path=str(resolved),
        filename=resolved.name,
        media_type=mime or "application/octet-stream",
    )


@router.get("/search")
@limiter.limit("30/minute")
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

    username = user.get("sub", "")
    user_role = "admin" if user.get("is_admin") or user.get("type") == "device" else "member"
    results = await search_documents(query=q, limit=limit, user_role=user_role, username=username)
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
