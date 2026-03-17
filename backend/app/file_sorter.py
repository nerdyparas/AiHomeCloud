"""
File sorting — InboxWatcher polls .inbox/ directories every 30 seconds and
auto-sorts files into Photos / Videos / Documents / Others based on extension.
"""

import asyncio
import logging
import shutil
import time
from pathlib import Path
from typing import Optional

from .config import settings

logger = logging.getLogger("aihomecloud.file_sorter")

# Extension → destination folder name (lowercase extensions only)
SORT_RULES: dict[str, str] = {
    # Photos
    ".jpg": "Photos", ".jpeg": "Photos", ".png": "Photos", ".gif": "Photos",
    ".heic": "Photos", ".heif": "Photos", ".webp": "Photos", ".tiff": "Photos",
    ".tif": "Photos", ".bmp": "Photos", ".raw": "Photos", ".cr2": "Photos",
    ".nef": "Photos", ".arw": "Photos", ".dng": "Photos",
    # Videos
    ".mp4": "Videos", ".mkv": "Videos", ".mov": "Videos", ".avi": "Videos",
    ".wmv": "Videos", ".flv": "Videos", ".ts": "Videos", ".m2ts": "Videos",
    ".mts": "Videos", ".m4v": "Videos", ".3gp": "Videos", ".webm": "Videos",
    # Documents
    ".pdf": "Documents", ".doc": "Documents", ".docx": "Documents",
    ".xls": "Documents", ".xlsx": "Documents", ".ppt": "Documents",
    ".pptx": "Documents", ".txt": "Documents", ".md": "Documents",
    ".csv": "Documents", ".odt": "Documents", ".ods": "Documents",
    ".odp": "Documents", ".rtf": "Documents",
}

# Keywords in filename (stem, lowercase) that indicate a document-style photo
DOC_KEYWORDS: frozenset[str] = frozenset({
    "aadhaar", "aadhar", "pan", "passport", "license", "licence",
    "invoice", "receipt", "bill", "certificate", "marksheet", "degree",
    "statement", "insurance", "policy", "property", "agreement", "contract",
})

# Entertainment sub-folder routing (applied when base_dir is entertainment_path)
ENTERTAINMENT_SORT_RULES: dict[str, str] = {
    ".mp4": "Movies", ".mkv": "Movies", ".avi": "Movies", ".mov": "Movies",
    ".m4v": "Movies", ".wmv": "Movies",
    ".ts": "Series", ".m2ts": "Series", ".mts": "Series",
    ".mp3": "Music", ".flac": "Music", ".aac": "Music", ".wav": "Music",
    ".ogg": "Music", ".m4a": "Music",
}

_MIN_AGE_SECONDS = 30          # file must be at least this old (not still uploading)
_DOC_PHOTO_MAX_BYTES = 800 * 1024   # < 800 KB image → likely a scanned document
_SKIP_SUFFIXES = frozenset({".uploading", ".part", ".tmp"})


def _destination_folder(file_path: Path, base_dir: Path | None = None) -> str:
    """Return the target sub-folder name for *file_path*.

    When *base_dir* is the entertainment folder, ENTERTAINMENT_SORT_RULES are used.
    """
    # Entertainment-specific routing
    if base_dir is not None:
        try:
            from .config import settings as _s
            if base_dir == _s.entertainment_path:
                ext = file_path.suffix.lower()
                return ENTERTAINMENT_SORT_RULES.get(ext, "Others")
        except Exception:
            pass

    ext = file_path.suffix.lower()
    folder = SORT_RULES.get(ext, "Others")

    # Document-photo override: small image OR doc keyword in filename → Documents/
    if folder == "Photos":
        name_lower = file_path.stem.lower()
        has_keyword = any(kw in name_lower for kw in DOC_KEYWORDS)
        try:
            is_small = file_path.stat().st_size < _DOC_PHOTO_MAX_BYTES
        except OSError:
            is_small = False
        if has_keyword or is_small:
            folder = "Documents"

    return folder


def _unique_dest(dest_dir: Path, name: str) -> Path:
    """Return a destination path inside *dest_dir* that does not already exist."""
    dest = dest_dir / name
    if not dest.exists():
        return dest
    stem = Path(name).stem
    suffix = Path(name).suffix
    counter = 2
    while True:
        candidate = dest_dir / f"{stem}_{counter}{suffix}"
        if not candidate.exists():
            return candidate
        counter += 1


def _sort_file(file_path: Path, base_dir: Path, *, check_age: bool = True) -> Optional[Path]:
    """
    Move *file_path* from .inbox/ to the appropriate sub-folder under *base_dir*.
    Returns the destination Path on success; None if skipped or an error occurred.
    Sort failures are logged as warnings — the file stays in .inbox/ so it can be
    retried on the next pass.
    """
    try:
        if check_age:
            # Skip files with upload-in-progress suffixes
            if any(file_path.name.endswith(s) for s in _SKIP_SUFFIXES):
                return None
            age = time.time() - file_path.stat().st_mtime
            if age < _MIN_AGE_SECONDS:
                return None  # file still being written; skip this pass

        folder_name = _destination_folder(file_path, base_dir)
        dest_dir = base_dir / folder_name
        dest_dir.mkdir(parents=True, exist_ok=True)

        dest = _unique_dest(dest_dir, file_path.name)
        shutil.move(str(file_path), str(dest))
        logger.info(
            "sorted file=%s folder=%s dest=%s",
            file_path.name, folder_name, dest.name,
        )
        return dest

    except Exception as exc:
        logger.warning(
            "sort_failed file=%s error=%s — file stays in inbox",
            file_path.name, exc,
        )
        return None


async def _try_index_document(dest: Path, added_by: str) -> None:
    """Trigger document indexing after sorting to Documents/. Stub until TASK-P2-02."""
    try:
        from .document_index import index_document  # available after TASK-P2-02
        await index_document(str(dest), dest.name, added_by)
    except ImportError:
        pass  # document_index module not yet available
    except Exception as exc:
        logger.warning("index_document failed path=%s error=%s", dest, exc)


def _collect_inboxes() -> list[tuple[Path, Path]]:
    """
    Return list of (inbox_dir, base_dir) pairs to watch.
    base_dir is the parent of .inbox/ — sorted outputs go directly under it.
    """
    inboxes: list[tuple[Path, Path]] = []

    # family/.inbox/
    family_inbox = settings.family_path / ".inbox"
    if family_inbox.is_dir():
        inboxes.append((family_inbox, settings.family_path))

    # entertainment/.inbox/
    entertainment_inbox = settings.entertainment_path / ".inbox"
    if entertainment_inbox.is_dir():
        inboxes.append((entertainment_inbox, settings.entertainment_path))

    # personal/{username}/.inbox/
    if settings.personal_path.is_dir():
        for user_dir in settings.personal_path.iterdir():
            if user_dir.is_dir():
                inbox = user_dir / ".inbox"
                if inbox.is_dir():
                    inboxes.append((inbox, user_dir))

    return inboxes


async def _run_sort_pass() -> None:
    """Single pass: sort all ready files across all known .inbox/ directories."""
    loop = asyncio.get_event_loop()
    for inbox, base_dir in _collect_inboxes():
        try:
            entries = list(inbox.iterdir())
        except OSError:
            continue

        for file_path in entries:
            if not file_path.is_file():
                continue
            dest = await loop.run_in_executor(
                None,
                lambda p=file_path, b=base_dir: _sort_file(p, b, check_age=True),
            )
            if dest is not None and dest.parent.name == "Documents":
                # Best-effort indexing — never blocks the watcher
                asyncio.create_task(
                    _try_index_document(dest, base_dir.name),
                    name=f"index_doc_{dest.name}",
                )


def _sort_folder_sync(folder: Path) -> tuple[int, int, int, list[Path]]:
    """Recursively sort files in *folder* without age checks."""
    moved = 0
    skipped = 0
    failed = 0
    docs: list[Path] = []
    category_dirs = {"Photos", "Videos", "Documents", "Others", ".inbox"}

    try:
        entries = list(folder.rglob("*"))
    except OSError:
        return moved, skipped, failed, docs

    for entry in entries:
        if not entry.is_file():
            skipped += 1
            continue

        # Skip files already inside known category folders to avoid churn.
        try:
            rel_parent_parts = entry.relative_to(folder).parent.parts
        except ValueError:
            rel_parent_parts = ()
        if any(part in category_dirs for part in rel_parent_parts):
            skipped += 1
            continue

        dest = _sort_file(entry, folder, check_age=False)
        if dest is None:
            failed += 1
            continue

        moved += 1
        if dest.parent.name == "Documents":
            docs.append(dest)

    return moved, skipped, failed, docs


async def sort_folder_now(folder: Path, added_by: str) -> dict[str, int]:
    """
    Manually sort all top-level files inside *folder* into category subfolders.
    Intended for one-shot ingestion of existing dumps (e.g. RawData).
    """
    loop = asyncio.get_event_loop()
    moved, skipped, failed, docs = await loop.run_in_executor(
        None, lambda: _sort_folder_sync(folder)
    )

    indexed = 0
    for doc in docs:
        await _try_index_document(doc, added_by)
        indexed += 1

    return {
        "moved": moved,
        "skipped": skipped,
        "failed": failed,
        "indexed": indexed,
    }


class InboxWatcher:
    """Background async task that polls .inbox/ directories every *interval* seconds."""

    def __init__(self, interval: int = 30) -> None:
        self._interval = interval
        self._task: asyncio.Task | None = None

    def start(self) -> None:
        self._task = asyncio.create_task(self._loop(), name="inbox_watcher")
        logger.info("InboxWatcher started interval=%ds", self._interval)

    async def stop(self) -> None:
        if self._task and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        self._task = None
        logger.info("InboxWatcher stopped")

    async def _loop(self) -> None:
        while True:
            try:
                await _run_sort_pass()
            except Exception as exc:
                logger.error("InboxWatcher pass error: %s", exc)
            await asyncio.sleep(self._interval)


# Module-level singleton — started/stopped from main.py lifespan
_watcher = InboxWatcher()


def get_watcher() -> InboxWatcher:
    return _watcher
