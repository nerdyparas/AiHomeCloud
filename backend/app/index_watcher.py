"""Continuous watcher to keep document_index in sync with NAS file changes."""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from .config import settings
from .document_index import (
    index_document,
    is_indexable_document_path,
    remove_document,
)

logger = logging.getLogger("aihomecloud.index_watcher")

# Polling interval in seconds. Keep moderate to reduce IO on ARM hardware.
_DEFAULT_INTERVAL_SECONDS = 20

# path -> (mtime_ns, size_bytes)
FileSignature = tuple[int, int]
StateMap = dict[str, FileSignature]


def _iter_document_roots() -> list[Path]:
    """Return all Documents roots under shared and personal user folders."""
    roots: list[Path] = []

    family_docs = settings.family_path / "Documents"
    if family_docs.is_dir():
        roots.append(family_docs)

    personal_base = settings.personal_path
    if personal_base.is_dir():
        for user_dir in personal_base.iterdir():
            if user_dir.is_dir():
                docs = user_dir / "Documents"
                if docs.is_dir():
                    roots.append(docs)

    return roots


def _added_by_for_path(path: Path) -> str:
    """Infer added_by from NAS path: personal/<user>/... or shared."""
    try:
        rel = path.resolve().relative_to(settings.nas_root.resolve())
    except ValueError:
        return "system"

    parts = rel.parts
    if len(parts) >= 2 and parts[0] == settings.personal_base:
        return parts[1]
    if len(parts) >= 1 and parts[0] == settings.family_dir:
        return "family"
    return "system"


def _scan_documents_sync() -> StateMap:
    """Scan all watched Documents trees and return current signatures."""
    state: StateMap = {}
    for root in _iter_document_roots():
        try:
            entries = root.rglob("*")
        except OSError:
            continue

        for p in entries:
            try:
                if not is_indexable_document_path(p):
                    continue
                st = p.stat()
                state[str(p.resolve())] = (int(st.st_mtime_ns), int(st.st_size))
            except OSError:
                continue

    return state


def _diff_states(previous: StateMap, current: StateMap) -> tuple[list[str], list[str]]:
    """Return (changed_or_added_abs_paths, removed_abs_paths)."""
    changed_or_added = [path for path, sig in current.items() if previous.get(path) != sig]
    removed = [path for path in previous if path not in current]
    return changed_or_added, removed


async def sync_once(previous_state: StateMap | None) -> StateMap:
    """Run one reconciliation pass and return the new state."""
    loop = asyncio.get_event_loop()
    current_state = await loop.run_in_executor(None, _scan_documents_sync)

    prev = previous_state or {}
    changed_or_added, removed = _diff_states(prev, current_state)

    # Remove stale index rows first to avoid duplicate paths on rename/move.
    for abs_path in removed:
        await remove_document(abs_path)

    # Index new/changed files.
    for abs_path in changed_or_added:
        p = Path(abs_path)
        await index_document(str(p), p.name, _added_by_for_path(p))

    if changed_or_added or removed:
        logger.info(
            "index_watcher_sync changed_or_added=%d removed=%d",
            len(changed_or_added),
            len(removed),
        )

    return current_state


class DocumentIndexWatcher:
    """Background task that continuously syncs file changes into doc index."""

    def __init__(self, interval_seconds: int = _DEFAULT_INTERVAL_SECONDS) -> None:
        self._interval_seconds = interval_seconds
        self._task: asyncio.Task | None = None
        self._state: StateMap | None = None

    def start(self) -> None:
        self._task = asyncio.create_task(self._loop(), name="document_index_watcher")
        logger.info("DocumentIndexWatcher started interval=%ds", self._interval_seconds)

    async def stop(self) -> None:
        if self._task and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        self._task = None
        logger.info("DocumentIndexWatcher stopped")

    async def _loop(self) -> None:
        while True:
            try:
                self._state = await sync_once(self._state)
            except Exception as exc:
                logger.error("DocumentIndexWatcher pass error: %s", exc)
            await asyncio.sleep(self._interval_seconds)


_watcher = DocumentIndexWatcher()


def get_index_watcher() -> DocumentIndexWatcher:
    return _watcher
