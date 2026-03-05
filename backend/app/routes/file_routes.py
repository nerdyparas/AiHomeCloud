"""
File management routes — list, mkdir, delete, rename, upload, download.
All paths are sandboxed under settings.nas_root.
"""

import mimetypes
import os
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query, status
from fastapi.responses import FileResponse

from ..auth import get_current_user
from ..config import settings
from ..models import CreateFolderRequest, FileItem, FileListResponse, RenameRequest
from .event_routes import emit_upload_complete

router = APIRouter(prefix="/api/v1/files", tags=["files"])


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
    # Convert it to absolute by treating nas_root as the anchor.
    try:
        resolved = (settings.nas_root / raw_path.lstrip("/")).resolve()
    except (OSError, ValueError):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")

    nas_resolved = settings.nas_root.resolve()
    if not str(resolved).startswith(str(nas_resolved)):
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
        except PermissionError:
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
    """Delete a file or directory (recursively)."""
    resolved = _safe_resolve(path)
    if not resolved.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")

    if resolved.is_dir():
        import shutil
        shutil.rmtree(resolved)
    else:
        resolved.unlink()


@router.put("/rename", status_code=status.HTTP_204_NO_CONTENT)
async def rename_file(body: RenameRequest, user: dict = Depends(get_current_user)):
    """Rename a file or directory."""
    if not body.new_name.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Name cannot be empty")

    resolved = _safe_resolve(body.old_path)
    if not resolved.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not found")

    new_path = resolved.parent / body.new_name
    if new_path.exists():
        raise HTTPException(status.HTTP_409_CONFLICT, "A file with that name already exists")

    resolved.rename(new_path)


@router.post("/upload", status_code=status.HTTP_201_CREATED)
async def upload_file(
    path: str = Query(..., description="Destination directory path"),
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    """
    Upload a file via multipart form data.
    The 'path' query param is the destination directory.
    """
    dest_dir = _safe_resolve(path)
    dest_dir.mkdir(parents=True, exist_ok=True)

    dest_file = dest_dir / file.filename
    total = 0

    with open(dest_file, "wb") as f:
        while chunk := await file.read(settings.upload_chunk_size):
            f.write(chunk)
            total += len(chunk)

    # Notify connected clients
    user_name = user.get("sub", "unknown")
    await emit_upload_complete(file.filename, user_name)

    return {
        "name": file.filename,
        "path": "/" + str(dest_file.relative_to(settings.nas_root.resolve())).replace("\\", "/"),
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
