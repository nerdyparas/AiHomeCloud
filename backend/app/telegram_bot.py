"""
Telegram bot for document retrieval from AiHomeCloud.

Bot commands:
  /start — welcome + prompt to /auth if not linked
  /auth  — link Telegram account to AiHomeCloud
  /list  — last 10 indexed documents
  /help  — show all commands
  <text> — full-text search; 0 results → message; 1 → send file; 2-5 → numbered list
  <num>  — send the nth file from the last search

Security: users must send /auth to link their Telegram account before accessing
any data. Linked chat IDs are persisted in the KV store.

The bot is entirely optional — it is only started when CUBIE_TELEGRAM_BOT_TOKEN is
configured.  If python-telegram-bot is not installed the startup silently skips.
"""

import asyncio
import logging
from pathlib import Path
from typing import Optional

logger = logging.getLogger("cubie.telegram_bot")

# Per-chat last-search results {chat_id: [{"path": ..., "filename": ..., ...}]}
_last_results: dict[int, list[dict]] = {}

# Module-level Application instance (None when bot is disabled)
_application = None


# ---------------------------------------------------------------------------
# Access control — linked chat IDs persisted in KV store
# ---------------------------------------------------------------------------

async def _get_linked_ids() -> set[int]:
    """Return set of linked Telegram chat IDs from KV store."""
    from .store import get_value
    ids = await get_value("telegram_linked_ids", default=[])
    return {int(i) for i in ids if str(i).lstrip("-").isdigit()}


async def _add_linked_id(chat_id: int) -> None:
    """Persistently link a new chat_id."""
    from .store import get_value, set_value
    ids = await get_value("telegram_linked_ids", default=[])
    if chat_id not in ids:
        ids.append(chat_id)
        await set_value("telegram_linked_ids", ids)


async def _is_allowed(chat_id: int) -> bool:
    """Return True if chat_id has linked their account via /auth."""
    linked = await _get_linked_ids()
    return chat_id in linked


# ---------------------------------------------------------------------------
# Command + Message handlers
# ---------------------------------------------------------------------------

async def _handle_start(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    first_name = update.effective_user.first_name or "there"

    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            f"👋 Hi {first_name}! This is a private AiHomeCloud.\n\n"
            "Send /auth to link your Telegram account and get access."
        )
        return

    await update.message.reply_text(
        f"👋 Welcome back, {first_name}!\n\n"
        "Type anything to search your documents, or /help for all commands."
    )


async def _handle_auth(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    first_name = update.effective_user.first_name or "there"

    if await _is_allowed(chat_id):
        await update.message.reply_text(
            f"✅ You're already linked, {first_name}!\n"
            "Type anything to search your files, or /list for recent documents."
        )
        return

    await _add_linked_id(chat_id)
    await update.message.reply_text(
        f"✅ Linked! Welcome, {first_name}.\n\n"
        "You can now:\n"
        "• Type anything to search documents\n"
        "• /list — see recent files\n"
        "• /help — show all commands"
    )


async def _handle_help(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            "Send /auth first to link your account to AiHomeCloud."
        )
        return
    await update.message.reply_text(
        "🏠 AiHomeCloud Bot\n\n"
        "Commands:\n"
        "• /list — last 10 documents\n"
        "• /help — this message\n\n"
        "Search:\n"
        "• Type any word to search your files\n"
        "• Reply with a number to receive that file\n\n"
        "Examples: aadhaar, pan card, invoice, passport"
    )


async def _handle_list(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            "Send /auth first to link your account to AiHomeCloud."
        )
        return

    from .document_index import list_recent_documents
    docs = await list_recent_documents(limit=10)
    if not docs:
        await update.message.reply_text("No documents indexed yet.")
        return

    _last_results[chat_id] = docs
    lines = [f"{i + 1}. {d['filename']} (by {d['added_by']})" for i, d in enumerate(docs)]
    await update.message.reply_text(
        "📄 Recent documents:\n" + "\n".join(lines) +
        "\n\nReply with a number to receive the file."
    )


async def _handle_message(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            "Send /auth first to link your account to AiHomeCloud."
        )
        return

    text = (update.message.text or "").strip()

    # Numeric reply → send file from previous search / list
    if text.isdigit():
        prev = _last_results.get(chat_id, [])
        idx = int(text) - 1
        if 0 <= idx < len(prev):
            await _send_file(update, prev[idx])
        else:
            await update.message.reply_text(
                "Invalid number. Search for something first or use /list."
            )
        return

    # Full-text search (admin-scope — bot has unrestricted access to the index)
    from .document_index import search_documents
    results = await search_documents(query=text, limit=5, user_role="admin", username="")

    if not results:
        await update.message.reply_text(f"🔍 No documents found for '{text}'.")
        return

    if len(results) == 1:
        _last_results[chat_id] = results
        await _send_file(update, results[0])
        return

    # 2-5 results → numbered list
    _last_results[chat_id] = results
    lines = [f"{i + 1}. {r['filename']}" for i, r in enumerate(results)]
    await update.message.reply_text(
        f"🔍 Found {len(results)} documents:\n" + "\n".join(lines) +
        "\n\nReply with a number to receive the file."
    )


async def _send_file(update, doc: dict) -> None:
    from .config import settings
    from .document_index import remove_document
    nas_path = doc.get("path", "")
    abs_path = settings.nas_root / nas_path.lstrip("/")
    p = Path(str(abs_path))
    if not p.exists() or not p.is_file():
        # Self-heal stale search index entries when files were deleted out-of-band.
        if nas_path:
            await remove_document(nas_path)
        await update.message.reply_text(f"⚠️ File not found: {doc.get('filename', '?')}")
        return
    with open(p, "rb") as fh:
        await update.message.reply_document(document=fh, filename=doc.get("filename", p.name))


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

async def start_bot() -> None:
    """Initialise and start the Telegram bot.  No-op if token is not configured."""
    global _application
    from .config import settings

    if not settings.telegram_bot_token:
        logger.info("Telegram bot token not set — bot disabled")
        return

    try:
        from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, filters
    except ImportError:
        logger.warning("python-telegram-bot not installed — Telegram bot disabled")
        return

    try:
        _application = (
            ApplicationBuilder()
            .token(settings.telegram_bot_token)
            .build()
        )

        _application.add_handler(CommandHandler("start", _handle_start))
        _application.add_handler(CommandHandler("auth", _handle_auth))
        _application.add_handler(CommandHandler("help", _handle_help))
        _application.add_handler(CommandHandler("list", _handle_list))
        _application.add_handler(
            MessageHandler(filters.TEXT & ~filters.COMMAND, _handle_message)
        )

        await _application.initialize()
        await _application.start()
        await _application.updater.start_polling(drop_pending_updates=True)

        logger.info("Telegram bot started polling")
    except Exception as exc:
        logger.error("Telegram bot failed to start: %s", exc)
        _application = None


async def stop_bot() -> None:
    """Gracefully shut down the Telegram bot."""
    global _application
    if _application is None:
        return
    try:
        await _application.updater.stop()
        await _application.stop()
        await _application.shutdown()
        logger.info("Telegram bot stopped")
    except Exception as exc:
        logger.warning("Telegram bot stop error: %s", exc)
    finally:
        _application = None
