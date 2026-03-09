"""
Document index — SQLite FTS5 full-text search for files sorted into Documents/.
Database is stored at settings.data_dir / "docs.db".

OCR strategy:
  .txt / .md / .csv / .rtf  → read file directly
  .pdf                       → pdftotext (from poppler-utils)
  .jpg / .png / .heic / ...  → tesseract OCR (eng+hin)
  anything else              → empty string

If pdftotext / tesseract is not installed, a warning is logged and the file
is indexed with an empty ocr_text — never fails permanently.
"""

import asyncio
import logging
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from .config import settings
from .subprocess_runner import run_command

logger = logging.getLogger("cubie.document_index")


# ---------------------------------------------------------------------------
# DB helpers (sync — executed via run_in_executor)
# ---------------------------------------------------------------------------

def _db_path() -> Path:
    return settings.data_dir / "docs.db"


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(str(_db_path()))
    conn.row_factory = sqlite3.Row
    return conn


def _init_db_sync() -> None:
    conn = _connect()
    try:
        conn.execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS doc_index USING fts5(
                path     UNINDEXED,
                filename,
                ocr_text,
                added_by UNINDEXED,
                added_at UNINDEXED
            )
            """
        )
        conn.commit()
    finally:
        conn.close()


async def init_db() -> None:
    """Initialise the FTS5 database. Call once from main.py lifespan."""
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, _init_db_sync)


# ---------------------------------------------------------------------------
# OCR helpers — async, never raise
# ---------------------------------------------------------------------------

async def _extract_text(file_path: Path) -> str:
    """Return searchable text for *file_path*. Returns '' on any failure."""
    if not file_path.exists():
        return ""

    ext = file_path.suffix.lower()

    # Plain-text types: read directly
    if ext in (".txt", ".md", ".csv", ".rtf"):
        loop = asyncio.get_event_loop()
        try:
            return await loop.run_in_executor(
                None, lambda: file_path.read_text(errors="replace")[:100_000]
            )
        except Exception as exc:
            logger.warning("text_read_error file=%s error=%s", file_path.name, exc)
            return ""

    # PDF: use pdftotext (poppler-utils)
    if ext == ".pdf":
        rc, stdout, stderr = await run_command(
            ["pdftotext", str(file_path), "-"], timeout=30
        )
        if rc == 0:
            return stdout[:100_000]
        if stderr == "not_found":
            logger.warning("pdftotext_missing file=%s — indexed without OCR", file_path.name)
        else:
            logger.warning(
                "pdftotext_failed file=%s rc=%d stderr=%s", file_path.name, rc, stderr[:200]
            )
        return ""

    # Images: tesseract OCR
    if ext in (".jpg", ".jpeg", ".png", ".heic", ".heif", ".tiff", ".tif", ".bmp"):
        rc, stdout, stderr = await run_command(
            ["tesseract", str(file_path), "stdout", "-l", "eng+hin"], timeout=60
        )
        if rc == 0:
            return stdout[:100_000]
        if stderr == "not_found":
            logger.warning("tesseract_missing file=%s — indexed without OCR", file_path.name)
        else:
            logger.warning(
                "tesseract_failed file=%s rc=%d stderr=%s", file_path.name, rc, stderr[:200]
            )
        return ""

    return ""


# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

def _to_nas_path(abs_path: Path) -> str:
    """Convert an absolute filesystem path to a NAS-relative slash path (/personal/...)."""
    try:
        relative = abs_path.resolve().relative_to(settings.nas_root.resolve())
        return "/" + str(relative).replace("\\", "/")
    except ValueError:
        return str(abs_path)


# ---------------------------------------------------------------------------
# Sync DB operations — called via run_in_executor
# ---------------------------------------------------------------------------

def _upsert_sync(nas_path: str, filename: str, ocr_text: str, added_by: str) -> None:
    added_at = datetime.now(timezone.utc).isoformat()
    conn = _connect()
    try:
        # Replace any existing entry (path is the unique key)
        conn.execute("DELETE FROM doc_index WHERE path = ?", (nas_path,))
        conn.execute(
            "INSERT INTO doc_index (path, filename, ocr_text, added_by, added_at)"
            " VALUES (?, ?, ?, ?, ?)",
            (nas_path, filename, ocr_text, added_by, added_at),
        )
        conn.commit()
    finally:
        conn.close()


def _search_sync(query: str, limit: int, user_role: str, username: str) -> list[dict]:
    conn = _connect()
    try:
        if user_role == "admin":
            rows = conn.execute(
                """
                SELECT path, filename, added_by, added_at,
                       snippet(doc_index, 2, '', '', '…', 10) AS snippet
                FROM doc_index
                WHERE doc_index MATCH ?
                ORDER BY rank
                LIMIT ?
                """,
                (query, limit),
            ).fetchall()
        else:
            # Member scope: own personal Documents + shared Documents
            own_prefix = f"/personal/{username}/%"
            shared_prefix = "/shared/%"
            rows = conn.execute(
                """
                SELECT path, filename, added_by, added_at,
                       snippet(doc_index, 2, '', '', '…', 10) AS snippet
                FROM doc_index
                WHERE doc_index MATCH ?
                  AND (path LIKE ? OR path LIKE ?)
                ORDER BY rank
                LIMIT ?
                """,
                (query, own_prefix, shared_prefix, limit),
            ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


def _remove_sync(nas_path: str) -> None:
    conn = _connect()
    try:
        conn.execute("DELETE FROM doc_index WHERE path = ?", (nas_path,))
        conn.commit()
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Public async API
# ---------------------------------------------------------------------------

async def index_document(path: str, filename: str, added_by: str) -> None:
    """
    Async: OCR and index a document at *path*.
    *path* may be an absolute filesystem path or a NAS-relative path (/personal/…).
    Never raises — errors are logged as warnings.
    """
    try:
        abs_path = (
            Path(path)
            if Path(path).is_absolute()
            else settings.nas_root / path.lstrip("/")
        )
        nas_path = _to_nas_path(abs_path)
        ocr_text = await _extract_text(abs_path)
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _upsert_sync, nas_path, filename, ocr_text, added_by)
        logger.info(
            "indexed_document path=%s added_by=%s ocr_chars=%d",
            nas_path, added_by, len(ocr_text),
        )
    except Exception as exc:
        logger.warning("index_document_failed path=%s error=%s", path, exc)


async def search_documents(
    query: str,
    limit: int = 5,
    user_role: str = "member",
    username: str = "",
) -> list[dict]:
    """
    Async FTS5 full-text search.

    Scope:
      admin  → all indexed documents
      member → own (/personal/{username}/…) + shared (/shared/…) only
    """
    if not query.strip():
        return []
    try:
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None, _search_sync, query, limit, user_role, username
        )
    except sqlite3.OperationalError as exc:
        # Malformed FTS query (bare AND/OR, unclosed quotes, etc.)
        logger.warning("search_documents_bad_query query=%r error=%s", query, exc)
        return []


async def remove_document(path: str) -> None:
    """Async: remove a document entry from the index."""
    if Path(path).is_absolute():
        path = _to_nas_path(Path(path))
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, _remove_sync, path)


def _list_recent_sync(limit: int) -> list[dict]:
    conn = _connect()
    try:
        rows = conn.execute(
            """
            SELECT path, filename, added_by, added_at
            FROM doc_index
            ORDER BY added_at DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        conn.close()


async def list_recent_documents(limit: int = 10) -> list[dict]:
    """Return the *limit* most recently indexed documents, newest first."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, _list_recent_sync, limit)
