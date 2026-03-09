"""
Tests for telegram_bot.py.

Strategy: no real Telegram connection is needed. Tests cover:
- _is_allowed() access control logic
- start_bot() and stop_bot() lifecycle (no token / no library)
- Handler routing using lightweight mock Update objects
- list_recent_documents via document_index integration
"""

import asyncio
import pytest
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

from app.config import settings


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_update(text: str = "", chat_id: int = 12345) -> MagicMock:
    """Build a minimal mock telegram Update."""
    update = MagicMock()
    update.effective_chat.id = chat_id
    update.message.text = text
    update.message.reply_text = AsyncMock()
    update.message.reply_document = AsyncMock()
    return update


def _make_context() -> MagicMock:
    return MagicMock()


# ---------------------------------------------------------------------------
# _is_allowed
# ---------------------------------------------------------------------------

def test_is_allowed_no_restriction():
    """Empty allowed_ids means everyone is allowed."""
    settings.telegram_allowed_ids = ""
    from app.telegram_bot import _is_allowed
    assert _is_allowed(12345) is True
    assert _is_allowed(99999) is True


def test_is_allowed_with_restriction_permits_known_id():
    settings.telegram_allowed_ids = "12345,67890"
    from app.telegram_bot import _is_allowed
    assert _is_allowed(12345) is True
    assert _is_allowed(67890) is True


def test_is_allowed_with_restriction_rejects_unknown_id():
    settings.telegram_allowed_ids = "12345"
    from app.telegram_bot import _is_allowed
    assert _is_allowed(99999) is False


def test_is_allowed_whitespace_in_ids():
    """Spaces around chat IDs (common copy-paste mistake) are stripped."""
    settings.telegram_allowed_ids = " 12345 , 67890 "
    from app.telegram_bot import _is_allowed
    assert _is_allowed(12345) is True
    assert _is_allowed(67890) is True
    assert _is_allowed(11111) is False


# ---------------------------------------------------------------------------
# Lifecycle: start_bot / stop_bot
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_start_bot_skips_when_no_token():
    """start_bot() returns immediately when the token is empty."""
    settings.telegram_bot_token = ""
    import app.telegram_bot as tb
    tb._application = None
    await tb.start_bot()
    assert tb._application is None


@pytest.mark.asyncio
async def test_start_bot_skips_when_library_missing():
    """start_bot() logs a warning and returns when python-telegram-bot is not installed."""
    settings.telegram_bot_token = "fake-token"
    import app.telegram_bot as tb
    tb._application = None
    with patch.dict("sys.modules", {"telegram": None, "telegram.ext": None}):
        # Force ImportError on 'from telegram.ext import ...'
        import builtins
        real_import = builtins.__import__

        def mock_import(name, *args, **kwargs):
            if name.startswith("telegram"):
                raise ImportError("mocked missing")
            return real_import(name, *args, **kwargs)

        with patch("builtins.__import__", side_effect=mock_import):
            await tb.start_bot()
    assert tb._application is None


@pytest.mark.asyncio
async def test_stop_bot_no_app_is_noop():
    """stop_bot() with no running application does nothing and does not raise."""
    import app.telegram_bot as tb
    tb._application = None
    await tb.stop_bot()  # must not raise
    assert tb._application is None


@pytest.mark.asyncio
async def test_stop_bot_calls_shutdown():
    """stop_bot() calls updater.stop(), stop(), shutdown() on the application."""
    import app.telegram_bot as tb
    mock_app = MagicMock()
    mock_app.updater.stop = AsyncMock()
    mock_app.stop = AsyncMock()
    mock_app.shutdown = AsyncMock()
    tb._application = mock_app

    await tb.stop_bot()

    mock_app.updater.stop.assert_called_once()
    mock_app.stop.assert_called_once()
    mock_app.shutdown.assert_called_once()
    assert tb._application is None


# ---------------------------------------------------------------------------
# /start handler
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_handle_start_unauthorized():
    """/start from an unlisted chat ID → rejection message."""
    settings.telegram_allowed_ids = "99999"
    from app.telegram_bot import _handle_start
    update = _make_update(chat_id=12345)
    await _handle_start(update, _make_context())
    call_args = update.message.reply_text.call_args[0][0]
    assert "private" in call_args.lower()


@pytest.mark.asyncio
async def test_handle_start_authorized():
    """/start from allowed chat ID → welcome message."""
    settings.telegram_allowed_ids = ""
    from app.telegram_bot import _handle_start
    update = _make_update(chat_id=12345)
    await _handle_start(update, _make_context())
    call_args = update.message.reply_text.call_args[0][0]
    assert "Welcome" in call_args or "welcome" in call_args.lower()


# ---------------------------------------------------------------------------
# /list handler
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_handle_list_no_docs():
    """/list when index is empty → friendly 'no docs' message."""
    settings.telegram_allowed_ids = ""
    from app.telegram_bot import _handle_list
    with patch("app.telegram_bot._handle_list.__module__"):
        pass
    with patch("app.document_index.list_recent_documents", new=AsyncMock(return_value=[])):
        update = _make_update(chat_id=12345)
        await _handle_list(update, _make_context())
    call_args = update.message.reply_text.call_args[0][0]
    assert "no" in call_args.lower() or "empty" in call_args.lower() or "yet" in call_args.lower()


@pytest.mark.asyncio
async def test_handle_list_with_docs_stores_results():
    """/list with docs → numbered list sent; _last_results populated for chat."""
    settings.telegram_allowed_ids = ""
    import app.telegram_bot as tb
    tb._last_results.clear()
    docs = [
        {"path": "/personal/alice/Documents/a.txt", "filename": "a.txt", "added_by": "alice", "added_at": "2026-01-01T00:00:00"},
        {"path": "/personal/alice/Documents/b.pdf", "filename": "b.pdf", "added_by": "alice", "added_at": "2026-01-02T00:00:00"},
    ]
    with patch("app.document_index.list_recent_documents", new=AsyncMock(return_value=docs)):
        update = _make_update(chat_id=42)
        await tb._handle_list(update, _make_context())

    assert 42 in tb._last_results
    assert len(tb._last_results[42]) == 2
    msg = update.message.reply_text.call_args[0][0]
    assert "1." in msg
    assert "2." in msg


# ---------------------------------------------------------------------------
# Message handler — search
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_handle_message_search_no_results():
    """Search with no results → 'no documents found' message."""
    settings.telegram_allowed_ids = ""
    import app.telegram_bot as tb
    tb._last_results.clear()
    with patch("app.document_index.search_documents", new=AsyncMock(return_value=[])):
        update = _make_update(text="zzznomatch", chat_id=42)
        await tb._handle_message(update, _make_context())
    msg = update.message.reply_text.call_args[0][0]
    assert "zzznomatch" in msg


@pytest.mark.asyncio
async def test_handle_message_search_single_result_sends_file(tmp_path):
    """Search returning 1 result → file is sent directly."""
    settings.telegram_allowed_ids = ""
    nas = tmp_path / "nas"
    doc_dir = nas / "personal" / "alice" / "Documents"
    doc_dir.mkdir(parents=True)
    doc = doc_dir / "invoice.pdf"
    doc.write_bytes(b"%PDF-1.4 test")
    settings.nas_root = nas

    import app.telegram_bot as tb
    tb._last_results.clear()
    result = [{"path": "/personal/alice/Documents/invoice.pdf", "filename": "invoice.pdf", "added_by": "alice"}]
    with patch("app.document_index.search_documents", new=AsyncMock(return_value=result)):
        update = _make_update(text="invoice", chat_id=42)
        await tb._handle_message(update, _make_context())

    update.message.reply_document.assert_called_once()
    kw = update.message.reply_document.call_args
    assert kw.kwargs.get("filename") == "invoice.pdf" or "invoice.pdf" in str(kw)


@pytest.mark.asyncio
async def test_handle_message_search_multiple_results():
    """Search returning 2+ results → numbered list sent."""
    settings.telegram_allowed_ids = ""
    import app.telegram_bot as tb
    tb._last_results.clear()
    results = [
        {"path": "/personal/alice/Documents/a.txt", "filename": "a.txt", "added_by": "alice"},
        {"path": "/personal/alice/Documents/b.txt", "filename": "b.txt", "added_by": "alice"},
    ]
    with patch("app.document_index.search_documents", new=AsyncMock(return_value=results)):
        update = _make_update(text="something", chat_id=42)
        await tb._handle_message(update, _make_context())

    assert len(tb._last_results.get(42, [])) == 2
    msg = update.message.reply_text.call_args[0][0]
    assert "1." in msg and "2." in msg


# ---------------------------------------------------------------------------
# Message handler — number reply
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_handle_message_number_sends_file(tmp_path):
    """Numeric reply sends the nth file from the last search."""
    settings.telegram_allowed_ids = ""
    nas = tmp_path / "nas"
    doc_dir = nas / "personal" / "alice" / "Documents"
    doc_dir.mkdir(parents=True)
    doc = doc_dir / "notes.txt"
    doc.write_text("hello")
    settings.nas_root = nas

    import app.telegram_bot as tb
    tb._last_results[55] = [
        {"path": "/personal/alice/Documents/notes.txt", "filename": "notes.txt", "added_by": "alice"},
    ]
    update = _make_update(text="1", chat_id=55)
    await tb._handle_message(update, _make_context())
    update.message.reply_document.assert_called_once()


@pytest.mark.asyncio
async def test_handle_message_invalid_number():
    """Out-of-range number reply → error message, no file sent."""
    settings.telegram_allowed_ids = ""
    import app.telegram_bot as tb
    tb._last_results[55] = [
        {"path": "/personal/alice/Documents/a.txt", "filename": "a.txt", "added_by": "alice"},
    ]
    update = _make_update(text="5", chat_id=55)  # only 1 result stored
    await tb._handle_message(update, _make_context())
    update.message.reply_document.assert_not_called()
    msg = update.message.reply_text.call_args[0][0]
    assert "invalid" in msg.lower() or "number" in msg.lower()


@pytest.mark.asyncio
async def test_handle_message_number_with_no_prior_search():
    """Numeric reply when no prior search → error message."""
    settings.telegram_allowed_ids = ""
    import app.telegram_bot as tb
    tb._last_results.pop(77, None)
    update = _make_update(text="1", chat_id=77)
    await tb._handle_message(update, _make_context())
    update.message.reply_document.assert_not_called()
    msg = update.message.reply_text.call_args[0][0]
    assert "invalid" in msg.lower() or "search" in msg.lower()


# ---------------------------------------------------------------------------
# _send_file edge case
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_send_file_missing_path_sends_error(tmp_path):
    """_send_file with a non-existent path sends an error message, not a file."""
    settings.nas_root = tmp_path / "nas"
    (settings.nas_root / "personal" / "alice" / "Documents").mkdir(parents=True)
    import app.telegram_bot as tb
    update = _make_update(chat_id=1)
    doc = {"path": "/personal/alice/Documents/ghost.pdf", "filename": "ghost.pdf"}
    await tb._send_file(update, doc)
    update.message.reply_document.assert_not_called()
    msg = update.message.reply_text.call_args[0][0]
    assert "not found" in msg.lower() or "ghost" in msg.lower()


# ---------------------------------------------------------------------------
# list_recent_documents (document_index integration)
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_list_recent_documents_empty(tmp_path):
    """list_recent_documents returns [] when index is empty."""
    settings.data_dir = tmp_path
    from app.document_index import init_db, list_recent_documents
    await init_db()
    docs = await list_recent_documents(limit=10)
    assert docs == []


@pytest.mark.asyncio
async def test_list_recent_documents_returns_newest_first(tmp_path):
    """list_recent_documents returns docs sorted newest first."""
    settings.data_dir = tmp_path
    nas = tmp_path / "nas"
    (nas / "personal" / "alice" / "Documents").mkdir(parents=True)
    settings.nas_root = nas

    from app.document_index import init_db, index_document, list_recent_documents
    await init_db()

    doc_a = nas / "personal" / "alice" / "Documents" / "old.txt"
    doc_b = nas / "personal" / "alice" / "Documents" / "new.txt"
    doc_a.write_text("older document")
    doc_b.write_text("newer document")

    await index_document(str(doc_a), doc_a.name, "alice")
    # Small sleep to ensure different added_at timestamps
    await asyncio.sleep(0.01)
    await index_document(str(doc_b), doc_b.name, "alice")

    docs = await list_recent_documents(limit=10)
    assert len(docs) == 2
    assert docs[0]["filename"] == "new.txt"
    assert docs[1]["filename"] == "old.txt"
