"""
Nightly duplicate scanner — walks all NAS storage, groups files by SHA-256,
and reports duplicate sets.

Runs at 2:00 AM daily (scheduled in main.py lifespan).
Results persisted to kv.json under "duplicate_scan_results".
Telegram report sent at 6:00 PM if duplicates were found.
"""

import asyncio
import hashlib
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional

from .config import settings
from . import store

logger = logging.getLogger("aihomecloud.duplicate_scanner")

# Files smaller than this are skipped (thumbnails, metadata, tiny icons).
_MIN_SIZE_BYTES = 10 * 1024  # 10 KB

# Directories to skip entirely during the scan.
_SKIP_DIR_NAMES = frozenset({".ahc_trash", ".inbox", ".git", "__pycache__"})

# Streaming read chunk size — matches upload_chunk_size in config.
_HASH_CHUNK_SIZE = 4 * 1024 * 1024  # 4 MB


def _stream_sha256(path: Path) -> str:
    """Return the hex SHA-256 digest of *path* using streaming 4 MB reads.

    Never loads the whole file into memory — safe for multi-GB files on ARM.
    This is a blocking function; always call via loop.run_in_executor.
    """
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(_HASH_CHUNK_SIZE), b""):
            h.update(chunk)
    return h.hexdigest()


def _owner_from_path(path: Path) -> str:
    """Derive a human-readable owner label from a NAS path.

    /srv/nas/personal/Paras/…   → "Paras"
    /srv/nas/family/…           → "family"
    /srv/nas/entertainment/…    → "entertainment"
    anything else               → "unknown"
    """
    try:
        rel = path.relative_to(settings.nas_root)
        parts = rel.parts
        if not parts:
            return "unknown"
        top = parts[0]
        if top == settings.personal_base and len(parts) > 1:
            return parts[1]  # username directory
        return top
    except ValueError:
        return "unknown"


def _collect_files(root: Path) -> list[Path]:
    """Iteratively walk *root*, skipping hidden dirs and small files.

    Returns all files >= _MIN_SIZE_BYTES that are not inside a skipped dir.
    Blocking — run in executor.
    """
    result: list[Path] = []
    stack: list[Path] = [root]
    while stack:
        current = stack.pop()
        try:
            entries = list(current.iterdir())
        except (PermissionError, OSError):
            continue
        for entry in entries:
            try:
                if entry.is_symlink():
                    continue
                if entry.is_dir():
                    if entry.name not in _SKIP_DIR_NAMES and not entry.name.startswith("."):
                        stack.append(entry)
                elif entry.is_file():
                    if entry.stat().st_size >= _MIN_SIZE_BYTES:
                        result.append(entry)
            except OSError:
                continue
    return result


def _scan_sync(root: Path) -> list[dict]:
    """Full blocking scan of *root*.  Run in a thread executor.

    Returns a list of duplicate sets sorted largest-first:
        [{"hash": str, "filename": str, "sizeBytes": int,
          "copies": [{"path": str, "owner": str}, ...]}, ...]
    Only sets with 2+ copies are included.
    """
    files = _collect_files(root)
    logger.info("duplicate_scan starting files_found=%d", len(files))

    hash_map: dict[str, list[Path]] = {}
    scanned = 0

    for path in files:
        try:
            digest = _stream_sha256(path)
        except (PermissionError, OSError):
            continue
        hash_map.setdefault(digest, []).append(path)
        scanned += 1

    results: list[dict] = []
    wasted = 0
    for digest, paths in hash_map.items():
        if len(paths) < 2:
            continue
        size = 0
        try:
            size = paths[0].stat().st_size
        except OSError:
            pass
        copies = [{"path": str(p), "owner": _owner_from_path(p)} for p in paths]
        results.append({
            "hash": digest,
            "filename": paths[0].name,
            "sizeBytes": size,
            "copies": copies,
        })
        wasted += size * (len(paths) - 1)

    # Sort largest-first so the Telegram report highlights the biggest wins first.
    results.sort(key=lambda r: r["sizeBytes"], reverse=True)

    logger.info(
        "duplicate_scan complete scanned=%d dup_sets=%d wasted_bytes=%d",
        scanned, len(results), wasted,
    )
    return results


class DuplicateScanner:
    """Scans the NAS for duplicate files using SHA-256 hashing.

    Usage:
        scanner = get_duplicate_scanner()
        results = await scanner._scan_nas_for_duplicates()
    """

    def __init__(self) -> None:
        self._scanning = False

    @property
    def is_scanning(self) -> bool:
        return self._scanning

    async def _scan_nas_for_duplicates(self) -> list[dict]:
        """Walk all NAS storage, detect duplicates, persist results to kv.json."""
        if self._scanning:
            logger.info("duplicate_scan already in progress — skipping")
            return []

        self._scanning = True
        try:
            loop = asyncio.get_running_loop()
            results = await loop.run_in_executor(
                None, lambda: _scan_sync(settings.nas_root)
            )
            await store.set_value("duplicate_scan_results", results)
            await store.set_value("duplicate_scan_ran_at", datetime.now().isoformat())
            return results
        finally:
            self._scanning = False

    @staticmethod
    def _format_telegram_report(results: list[dict]) -> Optional[str]:
        """Return an HTML Telegram summary message, or None if no duplicates."""
        if not results:
            return None

        total_wasted = sum(
            r["sizeBytes"] * (len(r["copies"]) - 1) for r in results
        )

        def _fmt(b: int) -> str:
            if b < 1024 * 1024:
                return f"{b / 1024:.0f} KB"
            if b < 1024 * 1024 * 1024:
                return f"{b / (1024 * 1024):.1f} MB"
            return f"{b / (1024 ** 3):.2f} GB"

        date_str = datetime.now().strftime("%d %b %Y")
        lines: list[str] = [
            f"🔍 <b>Storage Analysis — {date_str}</b>\n",
            f"Found <b>{len(results)}</b> duplicate set{'s' if len(results) != 1 else ''} "
            f"wasting <b>{_fmt(total_wasted)}</b>\n",
        ]

        for r in results[:10]:
            owners = ", ".join(c["owner"] for c in r["copies"])
            lines.append(
                f"📄 <code>{r['filename']}</code> — {_fmt(r['sizeBytes'])} "
                f"× {len(r['copies'])} copies ({owners})"
            )

        if len(results) > 10:
            lines.append(
                f"\n<i>…and {len(results) - 10} more. Use /duplicates to review all.</i>"
            )
        else:
            lines.append("\n<i>Use /duplicates to review and delete duplicates.</i>")

        return "\n".join(lines)


# Module-level singleton — same pattern as get_watcher() in file_sorter.py
_scanner = DuplicateScanner()


def get_duplicate_scanner() -> DuplicateScanner:
    return _scanner
