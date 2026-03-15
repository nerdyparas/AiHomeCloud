"""
SQLite schema stub for the file index â€” feature-flagged, off by default.

Enable via env var:  AHC_ENABLE_SQLITE=true

When enabled, creates two tables in {data_dir}/file_index.db:
  - file_index  â€” FTS5-searchable record for every indexed file
  - ai_jobs     â€” queue of pending AI processing tasks

When disabled, this module is a no-op and has zero impact on startup time
or runtime behaviour.
"""

from __future__ import annotations

import logging

logger = logging.getLogger("aihomecloud.db_stub")

# â”€â”€â”€ Schema â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

_CREATE_FILE_INDEX = """
CREATE TABLE IF NOT EXISTS file_index (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    path        TEXT NOT NULL UNIQUE,
    filename    TEXT NOT NULL,
    size_bytes  INTEGER NOT NULL DEFAULT 0,
    mime_type   TEXT,
    owner       TEXT,
    indexed_at  TEXT NOT NULL,     -- ISO-8601 UTC
    content_fts TEXT               -- extracted text for FTS5
);

CREATE VIRTUAL TABLE IF NOT EXISTS file_index_fts USING fts5(
    filename,
    content_fts,
    content='file_index',
    content_rowid='id'
);
"""

_CREATE_AI_JOBS = """
CREATE TABLE IF NOT EXISTS ai_jobs (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path   TEXT NOT NULL,
    job_type    TEXT NOT NULL,      -- "tag" | "ocr" | "transcribe"
    status      TEXT NOT NULL DEFAULT 'pending',  -- "pending" | "running" | "done" | "failed"
    created_at  TEXT NOT NULL,      -- ISO-8601 UTC
    updated_at  TEXT,
    result      TEXT                -- JSON blob of output
);
"""


# â”€â”€â”€ Public API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

async def init_db() -> None:
    """
    Create the SQLite database and tables if `enable_sqlite` is True.
    Safe to call multiple times â€” all statements are CREATE IF NOT EXISTS.
    Zero cost when the flag is off.
    """
    from .config import settings

    if not settings.enable_sqlite:
        logger.debug("SQLite file index disabled (AHC_ENABLE_SQLITE=false)")
        return

    import aiosqlite

    db_path = settings.data_dir / "file_index.db"
    settings.data_dir.mkdir(parents=True, exist_ok=True)
    logger.info("Initialising SQLite file index at %s", db_path)

    async with aiosqlite.connect(db_path) as db:
        await db.executescript(_CREATE_FILE_INDEX)
        await db.executescript(_CREATE_AI_JOBS)
        await db.commit()

    logger.info("SQLite file index ready")
