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
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

logger = logging.getLogger("cubie.telegram_bot")

_POLL_TIMEOUT_SECONDS = 2
_HTTP_TIMEOUT_SECONDS = 5
_STOP_TIMEOUT_SECONDS = 5
_TELEGRAM_FILE_DOWNLOAD_LIMIT_BYTES = 20 * 1024 * 1024

# Per-chat last-search results {chat_id: [{"path": ..., "filename": ..., ...}]}
_last_results: dict[int, list[dict]] = {}


@dataclass
class PendingUpload:
    file_id: str
    filename: str
    kind: str
    file_size: int = 0
    caption: str = ""


# Per-chat pending upload selection state.
_pending_uploads: dict[int, PendingUpload] = {}

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


async def _set_chat_folder_owner(chat_id: int, username: str) -> None:
    """Persist preferred personal-folder owner for a Telegram chat."""
    from .store import get_value, set_value

    mapping = await get_value("telegram_chat_folder_owners", default={})
    mapping[str(chat_id)] = username
    await set_value("telegram_chat_folder_owners", mapping)


async def _get_chat_folder_owner(chat_id: int) -> Optional[str]:
    """Return preferred personal-folder owner for a Telegram chat if configured."""
    from .store import get_value

    mapping = await get_value("telegram_chat_folder_owners", default={})
    value = mapping.get(str(chat_id))
    return value if isinstance(value, str) and value.strip() else None


async def _resolve_personal_owner(chat_id: int, preferred_name: str = "") -> str:
    """Resolve which AiHomeCloud personal folder this chat should use."""
    from .store import get_users

    explicit = await _get_chat_folder_owner(chat_id)
    if explicit:
        return explicit

    users = await get_users()
    if not users:
        return "admin"

    wanted = preferred_name.strip().casefold()
    if wanted:
        for user in users:
            if str(user.get("name", "")).casefold() == wanted:
                return str(user["name"])

    admin = next((u for u in users if str(u.get("name", "")).casefold() == "admin"), None)
    if admin is not None:
        return str(admin["name"])

    return str(users[0].get("name", "admin"))


def _sanitize_filename(name: str, default_stem: str = "telegram_file") -> str:
    """Return a filesystem-safe file name."""
    candidate = Path(name or default_stem).name.strip()
    if not candidate or candidate in (".", ".."):
        candidate = default_stem
    return candidate


def _human_size(num_bytes: int) -> str:
    """Return a compact human-readable byte size string."""
    if num_bytes <= 0:
        return "unknown size"
    mb = num_bytes / (1024 * 1024)
    if mb < 1024:
        return f"{mb:.1f} MB"
    gb = mb / 1024
    return f"{gb:.2f} GB"


def _is_too_large_telegram_file_error(exc: Exception) -> bool:
    return "file is too big" in str(exc).casefold()


async def _download_to_path(bot, file_id: str, dest_path: Path) -> Path:
    """Download a Telegram file to *dest_path*."""
    telegram_file = await bot.get_file(file_id)
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    await telegram_file.download_to_drive(custom_path=str(dest_path))
    return dest_path


async def _store_private_or_shared_file(bot, pending: PendingUpload, base_dir: Path, added_by: str) -> Path:
    """Download to .inbox, sort immediately, and index if it lands in Documents/."""
    from .document_index import index_document
    from .file_sorter import _sort_file

    inbox_dir = base_dir / ".inbox"
    inbox_dir.mkdir(parents=True, exist_ok=True)
    temp_name = _sanitize_filename(pending.filename)
    temp_path = inbox_dir / temp_name
    await _download_to_path(bot, pending.file_id, temp_path)

    dest = _sort_file(temp_path, base_dir, check_age=False)
    if dest is None:
        raise RuntimeError("Failed to sort downloaded file")

    if dest.parent.name == "Documents":
        await index_document(str(dest), dest.name, added_by)

    return dest


async def _store_entertainment_file(bot, pending: PendingUpload) -> Path:
    """Download file directly into shared Entertainment folder."""
    from .file_sorter import _unique_dest
    from .config import settings

    entertainment_dir = settings.shared_path / "Entertainment"
    entertainment_dir.mkdir(parents=True, exist_ok=True)
    safe_name = _sanitize_filename(pending.filename, default_stem="telegram_media")
    dest_path = _unique_dest(entertainment_dir, safe_name)
    await _download_to_path(bot, pending.file_id, dest_path)
    return dest_path


def _pending_upload_prompt(filename: str) -> str:
    return (
        f"Received: {filename}\n\n"
        "Choose where to save it:\n"
        "1. Private personal\n"
        "2. Shared personal\n"
        "3. Entertainment\n\n"
        "Reply with 1, 2, or 3."
    )


async def _handle_media_message(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            "Send /auth first to link your account to AiHomeCloud."
        )
        return

    message = update.message
    pending: Optional[PendingUpload] = None

    if getattr(message, "document", None):
        doc = message.document
        pending = PendingUpload(
            file_id=doc.file_id,
            filename=_sanitize_filename(getattr(doc, "file_name", "telegram_document")),
            kind="document",
            file_size=int(getattr(doc, "file_size", 0) or 0),
            caption=(message.caption or "").strip(),
        )
    elif getattr(message, "video", None):
        video = message.video
        pending = PendingUpload(
            file_id=video.file_id,
            filename=_sanitize_filename(getattr(video, "file_name", "telegram_video.mp4")),
            kind="video",
            file_size=int(getattr(video, "file_size", 0) or 0),
            caption=(message.caption or "").strip(),
        )
    elif getattr(message, "audio", None):
        audio = message.audio
        pending = PendingUpload(
            file_id=audio.file_id,
            filename=_sanitize_filename(getattr(audio, "file_name", "telegram_audio.mp3")),
            kind="audio",
            file_size=int(getattr(audio, "file_size", 0) or 0),
            caption=(message.caption or "").strip(),
        )
    elif getattr(message, "photo", None):
        photo = message.photo[-1]
        pending = PendingUpload(
            file_id=photo.file_id,
            filename="telegram_photo.jpg",
            kind="photo",
            file_size=int(getattr(photo, "file_size", 0) or 0),
            caption=(message.caption or "").strip(),
        )

    if pending is None:
        await update.message.reply_text("Unsupported file type. Send a document, photo, video, or audio.")
        return

    _pending_uploads[chat_id] = pending

    # For oversized files, note the size in the prompt so the user knows it
    # will be handled via a direct upload link after they pick a destination.
    size_note = ""
    if pending.file_size > _TELEGRAM_FILE_DOWNLOAD_LIMIT_BYTES:
        size_note = (
            f"\n⚠️ This file ({_human_size(pending.file_size)}) is too large "
            "for Telegram bot download. After you choose a destination, "
            "I'll send you a direct upload link.\n"
        )
    await update.message.reply_text(size_note + _pending_upload_prompt(pending.filename))


async def _handle_pending_upload_choice(update, context, choice: str) -> bool:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    pending = _pending_uploads.get(chat_id)
    if pending is None:
        return False

    from .config import settings

    owner_hint = update.effective_user.username or update.effective_user.first_name or ""
    owner = await _resolve_personal_owner(chat_id, owner_hint)

    # Map choice → destination label
    dest_map = {
        "1": ("private", f"private personal ({owner})"),
        "2": ("shared", "shared"),
        "3": ("entertainment", "entertainment"),
    }
    if choice not in dest_map:
        await update.message.reply_text("Reply with 1, 2, or 3.")
        return True

    dest_key, target_label = dest_map[choice]

    # ── Large file → generate one-time upload link ──
    if pending.file_size > _TELEGRAM_FILE_DOWNLOAD_LIMIT_BYTES:
        from .routes.telegram_upload_routes import create_upload_token

        token = create_upload_token(
            chat_id=chat_id,
            destination=dest_key,
            owner=owner,
            filename=pending.filename,
        )

        host = settings.host if settings.host != "0.0.0.0" else "192.168.0.212"
        scheme = "https" if settings.tls_enabled else "http"
        link = f"{scheme}://{host}:{settings.port}/api/telegram-upload/{token}"

        _pending_uploads.pop(chat_id, None)
        await update.message.reply_text(
            f"📤 This file is too large for Telegram download.\n\n"
            f"Open this link on your phone to upload directly to {target_label}:\n"
            f"{link}\n\n"
            f"⏳ Link expires in 15 minutes (one-time use)."
        )
        return True

    # ── Normal-size file → download via Telegram Bot API ──
    try:
        if choice == "1":
            base_dir = settings.personal_path / owner
            dest = await _store_private_or_shared_file(context.bot, pending, base_dir, owner)
        elif choice == "2":
            base_dir = settings.shared_path
            dest = await _store_private_or_shared_file(context.bot, pending, base_dir, "shared")
        else:
            dest = await _store_entertainment_file(context.bot, pending)

        _pending_uploads.pop(chat_id, None)
        await update.message.reply_text(
            f"✅ Operation completed. Saved to {target_label}: {dest.name}"
        )
    except Exception as exc:
        logger.warning("telegram_upload_store_failed chat_id=%s file=%s error=%s", chat_id, pending.filename, exc)
        if _is_too_large_telegram_file_error(exc):
            await update.message.reply_text(
                "⚠️ Telegram reports this file is too large to download via bot API. "
                "Please upload a smaller/compressed file, split it, or copy via app/SMB."
            )
        else:
            await update.message.reply_text(
                f"⚠️ Failed to save {pending.filename}. Please try again."
            )
    return True


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
    requested_owner = ""
    text = (update.message.text or "").strip()
    if " " in text:
        requested_owner = text.split(" ", 1)[1].strip()

    if await _is_allowed(chat_id):
        if requested_owner:
            owner = await _resolve_personal_owner(chat_id, requested_owner)
            await _set_chat_folder_owner(chat_id, owner)
        await update.message.reply_text(
            f"✅ You're already linked, {first_name}!\n"
            "Type anything to search your files, or /list for recent documents."
        )
        return

    await _add_linked_id(chat_id)
    owner = await _resolve_personal_owner(chat_id, requested_owner or first_name)
    await _set_chat_folder_owner(chat_id, owner)
    await update.message.reply_text(
        f"✅ Linked! Welcome, {first_name}.\n\n"
        "You can now:\n"
        "• Type anything to search documents\n"
        "• /list — see recent files\n"
        "• Send a file to store it\n"
        f"• Personal folder linked to: {owner}\n"
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
        "Upload:\n"
        "• Send a document, photo, video, or audio\n"
        "• Reply 1 for private personal, 2 for shared, 3 for entertainment\n\n"
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

    # Pending upload destination choice takes precedence over search result numbering.
    if text in {"1", "2", "3"}:
        handled = await _handle_pending_upload_choice(update, context, text)
        if handled:
            return

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
            .connect_timeout(_HTTP_TIMEOUT_SECONDS)
            .read_timeout(_HTTP_TIMEOUT_SECONDS)
            .write_timeout(_HTTP_TIMEOUT_SECONDS)
            .pool_timeout(_HTTP_TIMEOUT_SECONDS)
            .build()
        )

        _application.add_handler(CommandHandler("start", _handle_start))
        _application.add_handler(CommandHandler("auth", _handle_auth))
        _application.add_handler(CommandHandler("help", _handle_help))
        _application.add_handler(CommandHandler("list", _handle_list))
        _application.add_handler(
            MessageHandler(
                filters.Document.ALL | filters.PHOTO | filters.VIDEO | filters.AUDIO,
                _handle_media_message,
            )
        )
        _application.add_handler(
            MessageHandler(filters.TEXT & ~filters.COMMAND, _handle_message)
        )

        await _application.initialize()
        await _application.start()
        await _application.updater.start_polling(
            drop_pending_updates=True,
            poll_interval=0.0,
            timeout=_POLL_TIMEOUT_SECONDS,
            read_timeout=_HTTP_TIMEOUT_SECONDS,
            write_timeout=_HTTP_TIMEOUT_SECONDS,
            connect_timeout=_HTTP_TIMEOUT_SECONDS,
            pool_timeout=_HTTP_TIMEOUT_SECONDS,
        )

        logger.info("Telegram bot started polling")
    except Exception as exc:
        logger.error("Telegram bot failed to start: %s", exc)
        _application = None


async def stop_bot() -> None:
    """Gracefully shut down the Telegram bot."""
    global _application
    if _application is None:
        return

    async def _await_with_timeout(coro, label: str) -> None:
        try:
            await asyncio.wait_for(coro, timeout=_STOP_TIMEOUT_SECONDS)
        except asyncio.TimeoutError:
            logger.warning("Telegram bot %s timed out after %ss", label, _STOP_TIMEOUT_SECONDS)

    try:
        if getattr(_application, "updater", None) is not None:
            await _await_with_timeout(_application.updater.stop(), "updater.stop")
        await _await_with_timeout(_application.stop(), "application.stop")
        await _await_with_timeout(_application.shutdown(), "application.shutdown")
        _last_results.clear()
        _pending_uploads.clear()
        logger.info("Telegram bot stopped")
    except Exception as exc:
        logger.warning("Telegram bot stop error: %s", exc)
    finally:
        _application = None
