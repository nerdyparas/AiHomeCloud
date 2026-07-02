"""
Unified file-ingestion core.

Every path that writes bytes into the NAS (direct app upload, phone auto-sync,
Telegram bot, web upload portal) funnels through :func:`ingest` (or, for callers
that need custom duplicate-handling UX like the Telegram bot, the lower-level
:func:`stream_to_temp`). This replaces four independent, drifting
implementations of "write a file to a bucket" with one hardened writer.

Also hosts the path-safety/authorization helpers (`_safe_resolve`,
`_authorize_path`, `_require_external_storage`) and capture-time helpers
(`_apply_capture_time`) that used to live in `routes/file_routes.py` — moved
here so both `file_routes.py` and this module can share them without a
circular import. `file_routes.py` re-exports them for backward compatibility
with existing external importers (`trash_routes.py`, `web_browser_routes.py`,
`auth_routes.py`, `telegram_upload_routes.py`).
"""

import asyncio
import hashlib
import logging
import os
import shutil
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import AsyncIterator, Optional

from fastapi import HTTPException, status

from . import store
from .config import settings
from .file_sorter import _destination_folder, _unique_dest, _sort_file

logger = logging.getLogger("aihomecloud.ingest")

# Larger write buffer for uploads — 2 MB (fewer syscalls on ARM).
_UPLOAD_WRITE_BUF = 2 * 1024 * 1024

BLOCKED_EXTENSIONS: frozenset[str] = frozenset({
    ".sh", ".bash", ".zsh", ".fish",
    ".py", ".rb", ".pl", ".php",
    ".elf", ".bin", ".exe",
    ".apk", ".so", ".ko",
    ".deb", ".rpm",
})


# ---------------------------------------------------------------------------
# Path safety / authorization (moved from file_routes.py, unchanged logic)
# ---------------------------------------------------------------------------

def _require_external_storage() -> None:
    """Verify that external storage (USB / NVMe) is mounted at nas_root.

    If nas_root is just a directory on the SD card, reject file operations so
    users don't accidentally browse OS files.
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
    """Resolve a NAS-relative path to an absolute filesystem path, ensuring it
    stays within nas_root."""
    if "\x00" in raw_path:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")
    if len(raw_path) > 4096:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Path too long")

    nas_prefix = str(settings.nas_root)
    if raw_path.startswith(nas_prefix):
        boundary = len(nas_prefix)
        if len(raw_path) == boundary or raw_path[boundary] in ("/", "\\"):
            raw_path = raw_path[boundary:]

    candidate = settings.nas_root / raw_path.lstrip("/")

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
    """Resolve the authenticated principal to (personal_folder_name, is_admin)."""
    if user.get("type") == "device":
        return "", True
    found = await store.find_user(user.get("sub", ""))
    if not found:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User no longer exists")
    return found.get("name", ""), bool(found.get("is_admin", False))


async def _authorize_path(resolved: Path, user: dict) -> None:
    """Enforce that ``/personal/<name>/`` subtrees are private to their owner."""
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


# ---------------------------------------------------------------------------
# Capture-time helpers (moved from file_routes.py, unchanged logic)
# ---------------------------------------------------------------------------

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
    """Best-effort: set the file mtime to its capture time. Never raises."""
    try:
        ts = _extract_capture_epoch(file_path)
        if ts is None and fallback_epoch and float(fallback_epoch) > 0:
            ts = float(fallback_epoch)
        if ts:
            os.utime(file_path, (ts, ts))
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Ingestion core
# ---------------------------------------------------------------------------

class Scope(str, Enum):
    PERSONAL = "personal"
    FAMILY = "family"
    ENTERTAINMENT = "entertainment"


class IngestMode(str, Enum):
    SORTED = "sorted"    # auto-classify by extension into Photos/Videos/Documents/Others
    MIRROR = "mirror"    # write verbatim into dest.subpath, no auto-sort


@dataclass(frozen=True)
class Destination:
    scope: Scope
    owner: Optional[str] = None       # required iff scope == PERSONAL and raw_dir is None
    subpath: Optional[str] = None     # explicit subdir under the scope root; None + SORTED = auto-classify
    mode: IngestMode = IngestMode.SORTED
    raw_dir: Optional[Path] = None    # already-resolved+authorized dir (bypasses scope->dir derivation)

    def base_dir(self) -> Path:
        if self.raw_dir is not None:
            return self.raw_dir
        if self.scope == Scope.PERSONAL:
            if not self.owner:
                raise ValueError("Destination.owner is required for PERSONAL scope")
            return settings.personal_path / Path(self.owner).name
        if self.scope == Scope.FAMILY:
            return settings.family_path
        return settings.entertainment_path


@dataclass(frozen=True)
class IngestResult:
    path: Path
    sha256: str
    sorted_to: Optional[str]
    dedup_hit: bool
    bytes_written: int


class IngestStallError(Exception):
    """Raised when no data was received from the chunk source within the stall timeout."""


class IngestSizeError(Exception):
    """Raised when the incoming stream exceeds the configured max upload size."""


async def stream_to_temp(
    chunks: AsyncIterator[bytes],
    temp_path: Path,
    *,
    max_bytes: Optional[int] = None,
    stall_timeout_s: int = 60,
) -> tuple[int, str]:
    """Stream *chunks* into *temp_path*, hashing incrementally as it writes.

    Low-level primitive shared by :func:`ingest` and any caller (e.g. the
    Telegram bot) that needs its own duplicate-handling policy instead of
    ingest()'s default dedup-skip behavior. Bounds the GAP between successive
    chunks (not total transfer time), so a slow-but-alive transfer completes
    fine while a truly stalled connection is caught within `stall_timeout_s`.

    On any error the caller is responsible for cleaning up temp_path — this
    function does not delete it, so partial state is inspectable if needed.

    Returns (bytes_written, sha256_hex).
    """
    temp_path.parent.mkdir(parents=True, exist_ok=True)
    loop = asyncio.get_running_loop()
    sha = hashlib.sha256()
    total = 0

    fd = open(temp_path, "wb", buffering=_UPLOAD_WRITE_BUF)
    try:
        iterator = chunks.__aiter__()
        while True:
            try:
                chunk = await asyncio.wait_for(iterator.__anext__(), timeout=stall_timeout_s)
            except StopAsyncIteration:
                break
            except asyncio.TimeoutError:
                raise IngestStallError(
                    f"No data received for {stall_timeout_s}s — transfer stalled"
                )
            if not chunk:
                continue
            total += len(chunk)
            if max_bytes and total > max_bytes:
                raise IngestSizeError(
                    f"Stream exceeds maximum size of {max_bytes // (1024 * 1024)} MB"
                )
            sha.update(chunk)
            await loop.run_in_executor(None, fd.write, chunk)
    finally:
        await loop.run_in_executor(None, fd.close)

    return total, sha.hexdigest()


async def _dedup_lookup(scope: Scope, sha256: str) -> Optional[dict]:
    hashes = await store.get_value("ingest_hashes", default={})
    return hashes.get(f"{scope.value}:{sha256}")


async def _dedup_record(scope: Scope, sha256: str, filename: str, path: str) -> None:
    _MAX_HASHES = 20_000

    def _add(hashes):
        hashes = dict(hashes or {})
        key = f"{scope.value}:{sha256}"
        hashes[key] = {
            "filename": filename,
            "path": path,
            "saved_at": datetime.now(timezone.utc).isoformat(),
        }
        if len(hashes) > _MAX_HASHES:
            oldest = sorted(hashes, key=lambda k: hashes[k].get("saved_at", ""))
            for k in oldest[: len(hashes) - _MAX_HASHES]:
                del hashes[k]
        return hashes

    await store.atomic_update("ingest_hashes", _add, default={})


async def ingest(
    chunks: AsyncIterator[bytes],
    *,
    filename: str,
    dest: Destination,
    user: Optional[dict] = None,
    size_hint: Optional[int] = None,
    original_date: Optional[float] = None,
    stall_timeout_s: int = 60,
    skip_dedup: bool = False,
) -> IngestResult:
    """Ingest a byte stream into a NAS bucket.

    Handles: path safety, per-user authorization (if `user` is given —
    trusted internal callers like the Telegram bot may pass None to skip
    this, since they resolve ownership through their own linked-chat logic),
    filename/extension validation, stall-bounded chunked write to a
    `.uploading` temp file, incremental SHA-256, per-(scope, hash)
    deduplication, atomic rename, capture-time correction, and synchronous
    extension-based sorting.
    """
    _require_external_storage()

    safe_name = Path(filename).name
    if not safe_name or safe_name in (".", ".."):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid filename")
    for ext in (s.lower() for s in Path(safe_name).suffixes):
        if ext in BLOCKED_EXTENSIONS:
            raise HTTPException(
                status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                f"File type '{ext}' is not allowed for security reasons.",
            )

    base_dir = dest.base_dir()
    if dest.subpath:
        target_dir = base_dir / dest.subpath
        sorted_to = None
    elif dest.mode == IngestMode.SORTED:
        folder_name = _destination_folder(Path(safe_name), base_dir=base_dir)
        target_dir = base_dir / folder_name
        sorted_to = folder_name
    else:
        target_dir = base_dir
        sorted_to = None

    resolved_dir = target_dir.resolve() if target_dir.exists() else (
        target_dir.parent.resolve() / target_dir.name
    )
    if not resolved_dir.is_relative_to(settings.nas_root.resolve()):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")
    if user is not None:
        await _authorize_path(resolved_dir, user)

    target_dir.mkdir(parents=True, exist_ok=True)
    # _unique_dest (rather than a raw overwrite) is a deliberate, strictly-safer
    # change from the old /upload behavior: true duplicates are already caught
    # by the hash-dedup check above, so this only affects same-name-different-
    # content collisions, where auto-suffixing beats silently destroying data.
    final_dest = _unique_dest(target_dir, safe_name)
    if not final_dest.resolve().is_relative_to(settings.nas_root.resolve()):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Path outside NAS root")

    temp_path = target_dir / (safe_name + ".uploading")
    max_bytes = settings.max_upload_bytes

    try:
        total, sha256 = await stream_to_temp(
            chunks, temp_path, max_bytes=max_bytes, stall_timeout_s=stall_timeout_s,
        )
    except Exception:
        temp_path.unlink(missing_ok=True)
        raise

    if not skip_dedup:
        existing = await _dedup_lookup(dest.scope, sha256)
        if existing:
            temp_path.unlink(missing_ok=True)
            return IngestResult(
                path=Path(existing["path"]), sha256=sha256, sorted_to=None,
                dedup_hit=True, bytes_written=total,
            )

    loop = asyncio.get_running_loop()
    await loop.run_in_executor(None, temp_path.rename, final_dest)

    _apply_capture_time(final_dest, original_date)

    if not skip_dedup:
        rel_path = "/" + str(final_dest.relative_to(settings.nas_root.resolve())).replace("\\", "/")
        await _dedup_record(dest.scope, sha256, safe_name, rel_path)

    return IngestResult(
        path=final_dest, sha256=sha256, sorted_to=sorted_to,
        dedup_hit=False, bytes_written=total,
    )
