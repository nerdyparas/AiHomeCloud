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
from contextlib import suppress
from datetime import datetime
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

logger = logging.getLogger("cubie.telegram_bot")

_POLL_TIMEOUT_SECONDS = 2
_HTTP_TIMEOUT_SECONDS = 600
_STOP_TIMEOUT_SECONDS = 5
_UPLOAD_PROGRESS_INTERVAL_SECONDS = 15

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

# Weekly trash-warning scheduler task
_TRASH_WARNING_BYTES = 10 * 1024 * 1024 * 1024  # 10 GB
_trash_warning_task: asyncio.Task | None = None


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


def _is_timeout_error(exc: Exception) -> bool:
    return "timed out" in str(exc).casefold() or "timeout" in str(exc).casefold()


def _format_elapsed(total_seconds: float) -> str:
    """Return elapsed duration as h m s."""
    seconds = max(0, int(total_seconds))
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f"{hours}h {minutes}m {secs}s"
    if minutes:
        return f"{minutes}m {secs}s"
    return f"{secs}s"


def _format_avg_speed(num_bytes: int, elapsed_seconds: float) -> str:
    """Return average speed text (e.g. 3.2 MB/s)."""
    if num_bytes <= 0 or elapsed_seconds <= 0:
        return "n/a"
    return f"{_human_size(int(num_bytes / elapsed_seconds))}/s"


async def _safe_edit_text(message, text: str, parse_mode: str = "HTML") -> None:
    """Best-effort edit for status messages (ignore edit failures)."""
    if message is None:
        return
    try:
        await message.edit_text(text, parse_mode=parse_mode)
    except Exception:
        return


async def _upload_progress_heartbeat(message, filename: str, size_text: str, target_label: str, started_at: float) -> None:
    """Periodically update the same Telegram message while download is in progress."""
    loop = asyncio.get_running_loop()
    while True:
        await asyncio.sleep(_UPLOAD_PROGRESS_INTERVAL_SECONDS)
        elapsed = _format_elapsed(loop.time() - started_at)
        await _safe_edit_text(
            message,
            (
                f"📥 <b>Downloading…</b>\n\n"
                f"📄 <code>{filename}</code>\n"
                f"📦 {size_text}\n"
                f"📂 {target_label}\n"
                f"⏱ {elapsed}\n\n"
                "<i>Large files can take a few minutes.</i>"
            ),
        )


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

    entertainment_dir = settings.entertainment_path
    entertainment_dir.mkdir(parents=True, exist_ok=True)
    safe_name = _sanitize_filename(pending.filename, default_stem="telegram_media")
    dest_path = _unique_dest(entertainment_dir, safe_name)
    await _download_to_path(bot, pending.file_id, dest_path)
    return dest_path


def _file_type_emoji(kind: str) -> str:
    """Return an emoji for a given file kind."""
    return {
        "document": "📄",
        "video":    "🎬",
        "audio":    "🎵",
        "photo":    "🖼",
        "voice":    "🎙",
    }.get(kind, "📁")


def _make_destination_keyboard(chat_id: int):
    """Return a 4-button inline keyboard for upload destination choice."""
    from telegram import InlineKeyboardButton, InlineKeyboardMarkup
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤  My Folder",        callback_data=f"dest:{chat_id}:1")],
        [InlineKeyboardButton("👨\u200d👩\u200d👧  Family Shared",   callback_data=f"dest:{chat_id}:2")],
        [InlineKeyboardButton("🎬  Entertainment",   callback_data=f"dest:{chat_id}:3")],
        [InlineKeyboardButton("❌  Cancel",            callback_data=f"dest:{chat_id}:cancel")],
    ])


async def _handle_media_message(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            "Send /auth first to link your account to AiHomeCloud."
        )
        return

    from .config import settings

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
    elif getattr(message, "voice", None):
        voice = message.voice
        pending = PendingUpload(
            file_id=voice.file_id,
            filename=f"voice_{voice.file_unique_id}.ogg",
            kind="voice",
            file_size=int(getattr(voice, "file_size", 0) or 0),
            caption=(message.caption or "").strip(),
        )

    if pending is None:
        await update.message.reply_text(
            "⚠️ <i>Unsupported file type.</i>\n\nSend a document, photo, video, or audio.",
            parse_mode="HTML",
        )
        return

    _pending_uploads[chat_id] = pending

    emoji = _file_type_emoji(pending.kind)
    size_text = _human_size(pending.file_size) if pending.file_size else "unknown size"
    await update.message.reply_text(
        f"{emoji} <b>{pending.filename}</b>\n"
        f"<i>{size_text}</i>\n\n"
        "Where would you like to save this?",
        parse_mode="HTML",
        reply_markup=_make_destination_keyboard(chat_id),
    )


async def _handle_destination_callback(update, context) -> None:  # type: ignore[type-arg]
    """Handle inline keyboard taps for upload destination."""
    query = update.callback_query
    await query.answer()  # dismiss loading spinner on button

    data = query.data or ""
    # Format: "dest:{chat_id}:{choice}"
    parts = data.split(":")
    if len(parts) != 3 or parts[0] != "dest":
        return

    chat_id = int(parts[1])
    choice = parts[2]

    if choice == "cancel":
        _pending_uploads.pop(chat_id, None)
        await query.edit_message_text(
            "\u274c Upload cancelled.",
            parse_mode="HTML",
        )
        return

    if choice not in {"1", "2", "3"}:
        return

    # Remove the keyboard so buttons can't be tapped twice
    await query.edit_message_reply_markup(reply_markup=None)

    pending = _pending_uploads.get(chat_id)
    if pending is None:
        await query.edit_message_text(
            "⚠️ <i>No pending upload found. Please resend the file.</i>",
            parse_mode="HTML",
        )
        return

    await _process_upload_choice(query, context, chat_id, choice, pending)


async def _process_upload_choice(
    source,
    context,
    chat_id: int,
    choice: str,
    pending: PendingUpload,
) -> None:
    """Process an upload destination choice from either a callback query or text message."""
    from .config import settings

    owner_hint = ""
    if hasattr(source, "effective_user") and source.effective_user:
        owner_hint = source.effective_user.username or source.effective_user.first_name or ""
    elif hasattr(source, "from_user") and source.from_user:
        owner_hint = source.from_user.username or source.from_user.first_name or ""

    owner = await _resolve_personal_owner(chat_id, owner_hint)

    dest_labels = {
        "1": f"\U0001f464 My Folder ({owner})",
        "2": "\U0001f468\u200d\U0001f469\u200d\U0001f467 Family Shared",
        "3": "\U0001f3ac Entertainment",
    }
    target_label = dest_labels[choice]
    emoji = _file_type_emoji(pending.kind)
    size_text = _human_size(pending.file_size) if pending.file_size else "unknown size"

    loop = asyncio.get_running_loop()
    started_at = loop.time()

    status_message = await context.bot.send_message(
        chat_id=chat_id,
        text=(
            f"\U0001f4e5 <b>Downloading\u2026</b>\n\n"
            f"{emoji} <code>{pending.filename}</code>\n"
            f"\U0001f4e6 {size_text}\n"
            f"\U0001f4c2 {target_label}\n"
            f"\u23f1 Just started"
        ),
        parse_mode="HTML",
    )

    progress_task = None
    size_mb = pending.file_size / (1024 * 1024) if pending.file_size else 0
    if size_mb >= 5:
        progress_task = asyncio.create_task(
            _upload_progress_heartbeat(
                status_message,
                pending.filename,
                size_text,
                target_label,
                started_at,
            )
        )

    try:
        if choice == "1":
            base_dir = settings.personal_path / owner
            dest = await _store_private_or_shared_file(context.bot, pending, base_dir, owner)
        elif choice == "2":
            base_dir = settings.family_path
            dest = await _store_private_or_shared_file(context.bot, pending, base_dir, "family")
        else:
            dest = await _store_entertainment_file(context.bot, pending)

        _pending_uploads.pop(chat_id, None)
        actual_bytes = dest.stat().st_size
        elapsed_seconds = loop.time() - started_at

        await _safe_edit_text(
            status_message,
            (
                f"\u2705 <b>Saved</b>\n\n"
                f"{emoji} <code>{dest.name}</code>\n"
                f"\U0001f4c2 {target_label}\n"
                f"\U0001f4e6 {_human_size(actual_bytes)}\n"
                f"\u26a1 {_format_avg_speed(actual_bytes, elapsed_seconds)}  "
                f"\u23f1 {_format_elapsed(elapsed_seconds)}"
            ),
        )

    except Exception as exc:
        logger.warning(
            "telegram_upload_failed chat_id=%s file=%s error=%s",
            chat_id, pending.filename, exc,
        )
        elapsed_seconds = loop.time() - started_at
        elapsed_text = _format_elapsed(elapsed_seconds)

        if _is_too_large_telegram_file_error(exc):
            await _safe_edit_text(
                status_message,
                (
                    f"\u26a0\ufe0f <b>File too large</b>\n\n"
                    f"{emoji} <code>{pending.filename}</code>\n"
                    f"\u23f1 Failed after {elapsed_text}\n\n"
                    "Ask your admin to enable <b>Large File mode</b> in AiHomeCloud:\n"
                    "<i>More \u2192 Telegram Bot \u2192 Large file mode (up to 2 GB)</i>"
                ),
            )
        elif _is_timeout_error(exc):
            await _safe_edit_text(
                status_message,
                (
                    f"\u23f1 <b>Download timed out</b>\n\n"
                    f"{emoji} <code>{pending.filename}</code>\n"
                    f"Failed after {elapsed_text}\n\n"
                    "Network may be slow. Please try again."
                ),
            )
        else:
            await _safe_edit_text(
                status_message,
                (
                    f"\u274c <b>Save failed</b>\n\n"
                    f"{emoji} <code>{pending.filename}</code>\n"
                    f"\u23f1 {elapsed_text}\n\n"
                    "Please try again."
                ),
            )
    finally:
        if progress_task is not None:
            progress_task.cancel()
            with suppress(asyncio.CancelledError):
                await progress_task


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
            f"👋 <b>Hi {first_name}!</b>\n\n"
            "This is a private AiHomeCloud. Send /auth to link your account and get access.",
            parse_mode="HTML",
        )
        return

    await update.message.reply_text(
        f"🏠 <b>Welcome back, {first_name}!</b>\n\n"
        "Type anything to search your files.\n"
        "Send a file to save it to your cloud.\n\n"
        "Use /help to see all commands.",
        parse_mode="HTML",
    )


async def _handle_auth(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    first_name = update.effective_user.first_name or "there"
    requested_owner = ""
    text = (update.message.text or "").strip()
    if " " in text:
        requested_owner = text.split(" ", 1)[1].strip()

    if await _is_allowed(chat_id):
        owner = await _get_chat_folder_owner(chat_id) or "admin"
        if requested_owner:
            new_owner = await _resolve_personal_owner(chat_id, requested_owner)
            await _set_chat_folder_owner(chat_id, new_owner)
            owner = new_owner
        await update.message.reply_text(
            f"✅ <b>Already linked, {first_name}</b>\n\n"
            f"👤 Personal folder: <b>{owner}</b>\n\n"
            "To switch folder: <code>/auth &lt;name&gt;</code>",
            parse_mode="HTML",
        )
        return

    await _add_linked_id(chat_id)
    owner = await _resolve_personal_owner(chat_id, requested_owner or first_name)
    await _set_chat_folder_owner(chat_id, owner)
    await update.message.reply_text(
        f"✅ <b>Linked! Welcome, {first_name}.</b>\n\n"
        f"👤 Personal folder: <b>{owner}</b>\n\n"
        "You can now:\n"
        "• Type anything to <b>search documents</b>\n"
        "• Send a file to <b>save it to your cloud</b>\n"
        "• /list — recent files\n"
        "• /status — device health\n"
        "• /help — all commands",
        parse_mode="HTML",
    )


async def _handle_help(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            "🔒 Send /auth first to link your account.",
            parse_mode="HTML",
        )
        return

    owner = await _get_chat_folder_owner(chat_id) or "admin"
    await update.message.reply_text(
        "🏠 <b>AiHomeCloud Bot</b>\n\n"
        "<b>Commands</b>\n"
        "• /list — last 10 indexed documents\n"
        "• /status — device health and storage\n"
        "• /whoami — your linked profile\n"
        "• /cancel — discard a pending file upload\n"
        "• /unlink — disconnect this Telegram account\n"
        "• /help — this message\n\n"
        "<b>Search</b>\n"
        "• Type any word to search files\n"
        "• Reply with a number to receive that file\n\n"
        "<b>Upload</b>\n"
        "• Send any file — tap where to save it\n"
        "• Supports documents, photos, videos, audio\n"
        f"• Files save to your <b>{owner}</b> folder by default\n\n"
        "<i>Examples: aadhaar, pan card, invoice, passport</i>",
        parse_mode="HTML",
    )


async def _handle_list(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Send /auth first to link your account.", parse_mode="HTML")
        return

    await context.bot.send_chat_action(chat_id=chat_id, action="typing")

    from .document_index import list_recent_documents
    docs = await list_recent_documents(limit=10)
    if not docs:
        await update.message.reply_text(
            "📂 <i>No documents indexed yet.</i>\n\nSend a file to start building your library.",
            parse_mode="HTML",
        )
        return

    _last_results[chat_id] = docs
    lines = []
    for i, d in enumerate(docs, 1):
        added_by = d.get("added_by", "?")
        lines.append(f"{i}. <code>{d['filename']}</code>  <i>({added_by})</i>")

    await update.message.reply_text(
        "📄 <b>Recent documents</b>\n\n"
        + "\n".join(lines)
        + "\n\n<i>Reply with a number to receive the file.</i>",
        parse_mode="HTML",
    )


async def _handle_message(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            "🔒 Send /auth first to link your account.",
            parse_mode="HTML",
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
                "❓ <i>Invalid number.</i> Search for something first or use /list.",
                parse_mode="HTML",
            )
        return

    # Full-text search (admin-scope — bot has unrestricted access to the index)
    await context.bot.send_chat_action(chat_id=chat_id, action="typing")

    from .document_index import search_documents
    results = await search_documents(query=text, limit=5, user_role="admin", username="")

    if not results:
        await update.message.reply_text(
            f"🔍 <i>No documents found for</i> <b>{text}</b>.\n\n"
            "Try a different word or /list to browse recent files.",
            parse_mode="HTML",
        )
        return

    if len(results) == 1:
        _last_results[chat_id] = results
        await _send_file(update, results[0])
        return

    # 2-5 results → numbered list
    _last_results[chat_id] = results
    lines = [f"{i + 1}. <code>{r['filename']}</code>" for i, r in enumerate(results)]
    await update.message.reply_text(
        f"🔍 <b>Found {len(results)} files</b>\n\n"
        + "\n".join(lines)
        + "\n\n<i>Reply with a number to receive the file.</i>",
        parse_mode="HTML",
    )


async def _send_file(update, doc: dict) -> None:
    from .config import settings
    from .document_index import remove_document
    nas_path = doc.get("path", "")
    abs_path = settings.nas_root / nas_path.lstrip("/")
    p = Path(str(abs_path))
    if not p.exists() or not p.is_file():
        if nas_path:
            await remove_document(nas_path)
        await update.message.reply_text(
            f"⚠️ <b>File not found</b>\n\n"
            f"<code>{doc.get('filename', '?')}</code>\n\n"
            "<i>It may have been moved or deleted. The index has been updated.</i>",
            parse_mode="HTML",
        )
        return
    with open(p, "rb") as fh:
        await update.message.reply_document(document=fh, filename=doc.get("filename", p.name))


# ---------------------------------------------------------------------------
# New commands: /status, /cancel, /whoami, /unlink
# ---------------------------------------------------------------------------


async def _handle_status(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Send /auth first to link your account.", parse_mode="HTML")
        return

    await context.bot.send_chat_action(chat_id=chat_id, action="typing")

    try:
        import psutil
        import time as _time

        cpu = psutil.cpu_percent(interval=0.3)
        ram = psutil.virtual_memory()
        ram_pct = round(ram.percent, 1)
        ram_used_gb = round(ram.used / (1024 ** 3), 1)
        ram_total_gb = round(ram.total / (1024 ** 3), 1)

        # Uptime
        boot_time = psutil.boot_time()
        uptime_sec = int(_time.time() - boot_time)
        hours, rem = divmod(uptime_sec, 3600)
        minutes, _ = divmod(rem, 60)
        if hours >= 24:
            uptime_str = f"{hours // 24}d {hours % 24}h"
        else:
            uptime_str = f"{hours}h {minutes}m"

        # Temperature
        temp_str = "n/a"
        try:
            temps = psutil.sensors_temperatures()
            if temps:
                for key in ("cpu_thermal", "soc_thermal", "coretemp"):
                    entries = temps.get(key, [])
                    if entries:
                        temp_str = f"{entries[0].current:.0f}\u00b0C"
                        break
        except Exception:
            pass

        # Storage
        from .config import settings
        try:
            usage = psutil.disk_usage(str(settings.nas_root))
            used_gb = round(usage.used / (1024 ** 3), 1)
            total_gb_s = round(usage.total / (1024 ** 3), 1)
            free_gb = round(usage.free / (1024 ** 3), 1)
            pct = round(usage.used / usage.total * 100, 1)
            storage_bar = _storage_bar(pct)
            storage_str = f"{storage_bar}  {used_gb} / {total_gb_s} GB ({pct}%)"
        except Exception:
            storage_str = "unavailable"
            free_gb = 0.0

        # Health indicator
        if cpu > 80 or ram_pct > 85:
            health_icon, health_text = "🔴", "High load"
        elif cpu > 50 or ram_pct > 70:
            health_icon, health_text = "🟡", "Moderate"
        else:
            health_icon, health_text = "🟢", "Healthy"

        await update.message.reply_text(
            f"🖥 <b>AiHomeCloud Status</b>  {health_icon} {health_text}\n\n"
            f"\u23f1 Uptime:  <b>{uptime_str}</b>\n"
            f"\U0001f9e0 CPU:     <b>{cpu:.0f}%</b>\n"
            f"\U0001f4be RAM:     <b>{ram_used_gb} / {ram_total_gb} GB</b>  ({ram_pct}%)\n"
            f"\U0001f321 Temp:    <b>{temp_str}</b>\n\n"
            f"\U0001f4bd Storage\n{storage_str}\n"
            f"<i>{free_gb} GB free</i>",
            parse_mode="HTML",
        )

    except Exception as exc:
        logger.warning("telegram_status_error: %s", exc)
        await update.message.reply_text(
            "⚠️ <i>Could not read device status.</i>",
            parse_mode="HTML",
        )


def _storage_bar(percent: float, width: int = 10) -> str:
    """Return a text progress bar for storage, e.g. \u2593\u2593\u2593\u2593\u2593\u2591\u2591\u2591\u2591\u2591 50%."""
    filled = round(percent / 100 * width)
    bar = "\u2593" * filled + "\u2591" * (width - filled)
    return bar


async def _handle_cancel(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Send /auth first to link your account.", parse_mode="HTML")
        return

    had_pending = chat_id in _pending_uploads
    _pending_uploads.pop(chat_id, None)
    _last_results.pop(chat_id, None)

    if had_pending:
        await update.message.reply_text(
            "\u274c <b>Upload cancelled.</b>\n\n<i>Send a new file whenever you're ready.</i>",
            parse_mode="HTML",
        )
    else:
        await update.message.reply_text(
            "\u2705 <i>Nothing to cancel.</i>",
            parse_mode="HTML",
        )


async def _handle_whoami(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Send /auth first to link your account.", parse_mode="HTML")
        return

    owner = await _get_chat_folder_owner(chat_id) or "admin"
    first_name = update.effective_user.first_name or "there"
    tg_username = update.effective_user.username
    tg_line = f"@{tg_username}" if tg_username else f"ID: {chat_id}"

    await update.message.reply_text(
        f"👤 <b>{first_name}</b>  ({tg_line})\n\n"
        f"Personal folder: <b>{owner}</b>\n\n"
        "<i>To switch folder: /auth &lt;name&gt;</i>",
        parse_mode="HTML",
    )


async def _handle_unlink(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Not linked. Nothing to unlink.", parse_mode="HTML")
        return

    from .store import get_value, set_value
    ids = await get_value("telegram_linked_ids", default=[])
    ids = [i for i in ids if int(i) != chat_id]
    await set_value("telegram_linked_ids", ids)

    _pending_uploads.pop(chat_id, None)
    _last_results.pop(chat_id, None)

    await update.message.reply_text(
        "🔓 <b>Account unlinked.</b>\n\n"
        "<i>Your Telegram account has been removed from AiHomeCloud.\n"
        "Send /auth to link again.</i>",
        parse_mode="HTML",
    )


# ---------------------------------------------------------------------------
# Trash warning scheduler
# ---------------------------------------------------------------------------


async def _trash_warning_loop() -> None:
    """Hourly loop — sends a Telegram notification on Saturday at 10 AM when total
    trash exceeds 10 GB.  Fires at most once per ISO week via the KV store."""
    from . import store as _store

    while True:
        try:
            await asyncio.sleep(3600)

            now = datetime.now()
            if now.weekday() != 5 or now.hour != 10:  # weekday 5 = Saturday
                continue

            iso_week = f"{now.isocalendar()[0]}-W{now.isocalendar()[1]:02d}"
            if await _store.get_value("trash_warn_week", default="") == iso_week:
                continue  # already sent this week

            items = await _store.get_trash_items()
            total_bytes: int = sum(i.get("sizeBytes", 0) for i in items)
            if total_bytes < _TRASH_WARNING_BYTES:
                continue

            linked_ids = await _get_linked_ids()
            if not linked_ids or _application is None:
                continue

            total_gb = total_bytes / (1024 ** 3)
            msg = (
                f"🗑 <b>Trash is getting full</b>\n\n"
                f"Total trash: <b>{total_gb:.1f} GB</b> (threshold: 10 GB)\n\n"
                f"Open <b>AiHomeCloud</b> \u2192 Files \u2192 Trash to free up space."
            )
            for chat_id in linked_ids:
                with suppress(Exception):
                    await _application.bot.send_message(
                        chat_id=chat_id, text=msg, parse_mode="HTML"
                    )

            await _store.set_value("trash_warn_week", iso_week)
            logger.info(
                "Trash warning sent to %d user(s) (%.1f GB)", len(linked_ids), total_gb
            )

        except asyncio.CancelledError:
            break
        except Exception as exc:
            logger.warning("trash_warning_loop error: %s", exc)


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
        from telegram.ext import (
            ApplicationBuilder, CommandHandler, MessageHandler,
            CallbackQueryHandler, filters,
        )
    except ImportError:
        logger.warning("python-telegram-bot not installed — Telegram bot disabled")
        return

    try:
        builder = (
            ApplicationBuilder()
            .token(settings.telegram_bot_token)
            .connect_timeout(_HTTP_TIMEOUT_SECONDS)
            .read_timeout(_HTTP_TIMEOUT_SECONDS)
            .write_timeout(_HTTP_TIMEOUT_SECONDS)
            .pool_timeout(_HTTP_TIMEOUT_SECONDS)
        )

        # Use local Bot API server if configured — removes 20MB file limit
        if settings.telegram_local_api_enabled and settings.telegram_local_api_url:
            local_url = settings.telegram_local_api_url.rstrip("/")
            builder = (
                builder
                .base_url(f"{local_url}/bot")
                .base_file_url(f"{local_url}/file/bot")
                .local_mode(True)
            )
            logger.info("Telegram bot using local API at %s (2GB file limit)",
                        settings.telegram_local_api_url)
        else:
            logger.info("Telegram bot using cloud API (20MB file limit)")

        _application = builder.build()

        _application.add_handler(CommandHandler("start",  _handle_start))
        _application.add_handler(CommandHandler("auth",   _handle_auth))
        _application.add_handler(CommandHandler("help",   _handle_help))
        _application.add_handler(CommandHandler("list",   _handle_list))
        _application.add_handler(CommandHandler("status", _handle_status))
        _application.add_handler(CommandHandler("cancel", _handle_cancel))
        _application.add_handler(CommandHandler("whoami", _handle_whoami))
        _application.add_handler(CommandHandler("unlink", _handle_unlink))
        _application.add_handler(
            MessageHandler(
                filters.Document.ALL | filters.PHOTO | filters.VIDEO | filters.AUDIO | filters.VOICE,
                _handle_media_message,
            )
        )
        _application.add_handler(
            MessageHandler(filters.TEXT & ~filters.COMMAND, _handle_message)
        )
        _application.add_handler(
            CallbackQueryHandler(_handle_destination_callback, pattern=r"^dest:")
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

        # Start weekly trash-warning scheduler
        global _trash_warning_task
        _trash_warning_task = asyncio.create_task(
            _trash_warning_loop(), name="trash_warning_loop"
        )
    except Exception as exc:
        logger.error("Telegram bot failed to start: %s", exc)
        _application = None


async def stop_bot() -> None:
    """Gracefully shut down the Telegram bot."""
    global _application, _trash_warning_task

    # Cancel the trash warning scheduler first
    if _trash_warning_task and not _trash_warning_task.done():
        _trash_warning_task.cancel()
        with suppress(asyncio.CancelledError, Exception):
            await _trash_warning_task
    _trash_warning_task = None

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
