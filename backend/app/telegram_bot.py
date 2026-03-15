"""
Telegram bot for document retrieval from AiHomeCloud.

Bot commands:
  /start â€” welcome + prompt to /auth if not linked
  /auth  â€” link Telegram account to AiHomeCloud
  /list  â€” last 10 indexed documents
  /help  â€” show all commands
  <text> â€” full-text search; 0 results â†’ message; 1 â†’ send file; 2-5 â†’ numbered list
  <num>  â€” send the nth file from the last search

Security: users must send /auth to link their Telegram account before accessing
any data. Linked chat IDs are persisted in the KV store.

The bot is entirely optional â€” it is only started when AHC_TELEGRAM_BOT_TOKEN is
configured.  If python-telegram-bot is not installed the startup silently skips.
"""

import asyncio
from contextlib import suppress
from datetime import datetime
import hashlib
import logging
from dataclasses import dataclass
from pathlib import Path
import shutil
from typing import Optional

logger = logging.getLogger("aihomecloud.telegram_bot")

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

# Per-chat duplicate-detection pending state.
_pending_duplicates: dict[int, dict] = {}


class DuplicateFileError(Exception):
    """Raised when an uploaded file matches an existing MD5 hash."""

    def __init__(self, md5: str, existing: dict, temp_path: Path) -> None:
        self.md5 = md5
        self.existing = existing
        self.temp_path = temp_path

# Module-level Application instance (None when bot is disabled)
_application = None

# Weekly trash-warning scheduler task
_TRASH_WARNING_BYTES = 10 * 1024 * 1024 * 1024  # 10 GB
_trash_warning_task: asyncio.Task | None = None


# ---------------------------------------------------------------------------
# Access control â€” linked chat IDs persisted in KV store
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


# ---------------------------------------------------------------------------
# Pending approval helpers (Task 9)
# ---------------------------------------------------------------------------

async def _get_pending_approvals() -> list[dict]:
    """Return the list of pending Telegram auth approval requests."""
    from .store import get_value
    return await get_value("telegram_pending_approvals", default=[])


async def _add_pending_approval(chat_id: int, username: str, first_name: str) -> None:
    """Add a chat_id to the pending-approval list."""
    from .store import get_value, set_value
    items = await get_value("telegram_pending_approvals", default=[])
    if not any(p["chat_id"] == chat_id for p in items):
        items.append({
            "chat_id": chat_id,
            "username": username,
            "first_name": first_name,
            "requested_at": datetime.now().isoformat(),
        })
        await set_value("telegram_pending_approvals", items)


async def _remove_pending_approval(chat_id: int) -> None:
    """Remove a chat_id from the pending-approval list."""
    from .store import get_value, set_value
    items = await get_value("telegram_pending_approvals", default=[])
    items = [p for p in items if p["chat_id"] != chat_id]
    await set_value("telegram_pending_approvals", items)


async def _get_admin_chat_ids() -> set[int]:
    """Return Telegram chat IDs whose folder owner is an AHC admin user."""
    from .store import get_users, get_value
    users = await get_users()
    admin_names = {
        str(u.get("name", "")).casefold()
        for u in users
        if u.get("is_admin")
    }
    if not admin_names:
        return set()
    mapping = await get_value("telegram_chat_folder_owners", default={})
    result: set[int] = set()
    for str_id, owner_name in mapping.items():
        if str(owner_name).casefold() in admin_names:
            try:
                result.add(int(str_id))
            except ValueError:
                pass
    return result


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
                f"ðŸ“¥ <b>Downloadingâ€¦</b>\n\n"
                f"ðŸ“„ <code>{filename}</code>\n"
                f"ðŸ“¦ {size_text}\n"
                f"ðŸ“‚ {target_label}\n"
                f"â± {elapsed}\n\n"
                "<i>Large files can take a few minutes.</i>"
            ),
        )


async def _download_to_path(bot, file_id: str, dest_path: Path) -> Path:
    """Download a Telegram file to *dest_path*."""
    telegram_file = await bot.get_file(file_id)
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    await telegram_file.download_to_drive(custom_path=str(dest_path))
    return dest_path


# ---------------------------------------------------------------------------
# Duplicate-detection helpers (Task 10)
# ---------------------------------------------------------------------------

def _compute_md5(path: Path) -> str:
    """Return the hex MD5 digest of *path*."""
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


async def _check_duplicate(path: Path) -> Optional[dict]:
    """Return existing file-hash record if MD5 matches, else None."""
    from .store import get_value
    md5 = _compute_md5(path)
    hashes = await get_value("telegram_file_hashes", default={})
    record = hashes.get(md5)
    if record:
        return {**record, "md5": md5}
    return None


async def _record_file_hash(md5: str, filename: str, path: str) -> None:
    """Persist an MD5 → file mapping in the KV store."""
    from .store import get_value, set_value
    hashes = await get_value("telegram_file_hashes", default={})
    hashes[md5] = {
        "filename": filename,
        "path": path,
        "saved_at": datetime.now().isoformat(),
    }
    await set_value("telegram_file_hashes", hashes)


async def _record_recent_file(chat_id: int, filename: str, path: str, size: int) -> None:
    """Prepend an entry to the recent-files list (max 5 entries)."""
    from .store import get_value, set_value
    recent = await get_value("telegram_recent_files", default=[])
    recent.insert(0, {
        "filename": filename,
        "path": path,
        "size": size,
        "chat_id": chat_id,
        "saved_at": datetime.now().isoformat(),
    })
    await set_value("telegram_recent_files", recent[:5])


async def _store_private_or_shared_file(bot, pending: PendingUpload, base_dir: Path, added_by: str) -> Path:
    """Download to .inbox, sort immediately, and index if it lands in Documents/."""
    from .document_index import index_document
    from .file_sorter import _sort_file

    inbox_dir = base_dir / ".inbox"
    inbox_dir.mkdir(parents=True, exist_ok=True)
    temp_name = _sanitize_filename(pending.filename)
    temp_path = inbox_dir / temp_name
    await _download_to_path(bot, pending.file_id, temp_path)

    # Duplicate detection: compare MD5 against known-file index
    existing = await _check_duplicate(temp_path)
    if existing:
        raise DuplicateFileError(md5=existing["md5"], existing=existing, temp_path=temp_path)

    dest = _sort_file(temp_path, base_dir, check_age=False)
    if dest is None:
        raise RuntimeError("Failed to sort downloaded file")

    if dest.parent.name == "Documents":
        await index_document(str(dest), dest.name, added_by)

    # Record hash (MD5 of final file) and return
    await _record_file_hash(_compute_md5(dest), dest.name, str(dest))
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

    # Duplicate detection
    existing = await _check_duplicate(dest_path)
    if existing:
        raise DuplicateFileError(md5=existing["md5"], existing=existing, temp_path=dest_path)

    await _record_file_hash(_compute_md5(dest_path), dest_path.name, str(dest_path))
    return dest_path


def _file_type_emoji(kind: str) -> str:
    """Return an emoji for a given file kind."""
    return {
        "document": "ðŸ“„",
        "video":    "ðŸŽ¬",
        "audio":    "ðŸŽµ",
        "photo":    "ðŸ–¼",
        "voice":    "ðŸŽ™",
    }.get(kind, "ðŸ“")


def _make_destination_keyboard(chat_id: int):
    """Return a 4-button inline keyboard for upload destination choice."""
    from telegram import InlineKeyboardButton, InlineKeyboardMarkup
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("ðŸ‘¤  My Folder",        callback_data=f"dest:{chat_id}:1")],
        [InlineKeyboardButton("ðŸ‘¨\u200dðŸ‘©\u200dðŸ‘§  Family Shared",   callback_data=f"dest:{chat_id}:2")],
        [InlineKeyboardButton("ðŸŽ¬  Entertainment",   callback_data=f"dest:{chat_id}:3")],
        [InlineKeyboardButton("âŒ  Cancel",            callback_data=f"dest:{chat_id}:cancel")],
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
            "âš ï¸ <i>Unsupported file type.</i>\n\nSend a document, photo, video, or audio.",
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
            "âš ï¸ <i>No pending upload found. Please resend the file.</i>",
            parse_mode="HTML",
        )
        return

    # Delete the "where to save?" message so only the result remains in chat.
    try:
        await query.message.delete()
    except Exception:
        pass  # Message may be too old or already deleted — upload must still proceed.

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

        await _record_recent_file(chat_id, dest.name, str(dest), actual_bytes)

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

    except DuplicateFileError as dup:
        # Keep temp file on disk so /keep can proceed without re-downloading
        _pending_duplicates[chat_id] = {
            "md5": dup.md5,
            "existing": dup.existing,
            "temp_path": dup.temp_path,
            "choice": choice,
            "pending": pending,
            "owner": owner,
        }
        saved_on = dup.existing.get("saved_at", "")[:10]
        await _safe_edit_text(
            status_message,
            (
                f"\u26a0\ufe0f <b>Duplicate detected</b>\n\n"
                f"This file already exists as "
                f"<code>{dup.existing.get('filename', '?')}</code>\n"
                f"Saved on: <i>{saved_on}</i>\n\n"
                "Use /keep to save anyway, or /skip to cancel."
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
            f"ðŸ‘‹ <b>Hi {first_name}!</b>\n\n"
            "This is a private AiHomeCloud. Send /auth to link your account and get access.",
            parse_mode="HTML",
        )
        return

    await update.message.reply_text(
        f"ðŸ  <b>Welcome back, {first_name}!</b>\n\n"
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
            f"âœ… <b>Already linked, {first_name}</b>\n\n"
            f"ðŸ‘¤ Personal folder: <b>{owner}</b>\n\n"
            "To switch folder: <code>/auth &lt;name&gt;</code>",
            parse_mode="HTML",
        )
        return

    username = update.effective_user.username or ""
    await _add_pending_approval(chat_id, username, first_name)
    admin_ids = await _get_admin_chat_ids()
    if admin_ids and _application is not None:
        from telegram import InlineKeyboardButton, InlineKeyboardMarkup
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("✅ Approve", callback_data=f"approval:approve:{chat_id}"),
            InlineKeyboardButton("❌ Deny",    callback_data=f"approval:deny:{chat_id}"),
        ]])
        req_text = (
            f"👤 <b>New pairing request</b>\n\n"
            f"Name: <b>{first_name}</b>\n"
            f"Username: @{username}\n"
            f"Chat ID: <code>{chat_id}</code>\n"
            f"Folder request: <b>{requested_owner or '(default)'}</b>"
        )
        for admin_id in admin_ids:
            with suppress(Exception):
                await _application.bot.send_message(
                    chat_id=admin_id, text=req_text,
                    parse_mode="HTML", reply_markup=kb,
                )
    await update.message.reply_text(
        "⏳ <b>Access request sent.</b>\n\n"
        "An admin will review your request.\n"
        "You'll receive a message here when approved.",
        parse_mode="HTML",
    )

async def _handle_help(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            "ðŸ”’ Send /auth first to link your account.",
            parse_mode="HTML",
        )
        return

    owner = await _get_chat_folder_owner(chat_id) or "admin"
    is_admin = await _is_admin_chat(chat_id)
    admin_section = (
        "\n<b>Admin</b>\n"
        "• /approve &lt;chat_id&gt; — approve a pending request\n"
        "• /deny &lt;chat_id&gt; — deny a pending request\n"
    ) if is_admin else ""
    await update.message.reply_text(
        "🏠 <b>AiHomeCloud Bot</b>\n\n"
        "<b>Commands</b>\n"
        "• /list — last 10 indexed documents\n"
        "• /recent — your last 5 uploaded files\n"
        "• /storage — storage usage\n"
        "• /status — device health\n"
        "• /whoami — your linked profile\n"
        "• /cancel — discard a pending upload\n"
        "• /unlink — disconnect this Telegram account\n"
        "• /help — this message\n\n"
        "<b>Search</b>\n"
        "• Type any word to search files\n"
        "• Reply with a number to receive that file\n\n"
        "<b>Upload</b>\n"
        "• Send any file — tap where to save it\n"
        "• Supports documents, photos, videos, audio\n"
        "• Use /keep or /skip when a duplicate is detected\n"
        f"• Files save to your <b>{owner}</b> folder by default\n\n"
        + admin_section
        + "<i>Examples: aadhaar, pan card, invoice, passport</i>",
        parse_mode="HTML",
    )

async def _handle_list(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("ðŸ”’ Send /auth first to link your account.", parse_mode="HTML")
        return

    await context.bot.send_chat_action(chat_id=chat_id, action="typing")

    from .document_index import list_recent_documents
    docs = await list_recent_documents(limit=10)
    if not docs:
        await update.message.reply_text(
            "ðŸ“‚ <i>No documents indexed yet.</i>\n\nSend a file to start building your library.",
            parse_mode="HTML",
        )
        return

    _last_results[chat_id] = docs
    lines = []
    for i, d in enumerate(docs, 1):
        added_by = d.get("added_by", "?")
        lines.append(f"{i}. <code>{d['filename']}</code>  <i>({added_by})</i>")

    await update.message.reply_text(
        "ðŸ“„ <b>Recent documents</b>\n\n"
        + "\n".join(lines)
        + "\n\n<i>Reply with a number to receive the file.</i>",
        parse_mode="HTML",
    )


async def _handle_message(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            "ðŸ”’ Send /auth first to link your account.",
            parse_mode="HTML",
        )
        return

    text = (update.message.text or "").strip()

    # Numeric reply â†’ send file from previous search / list
    if text.isdigit():
        prev = _last_results.get(chat_id, [])
        idx = int(text) - 1
        if 0 <= idx < len(prev):
            await _send_file(update, prev[idx])
        else:
            await update.message.reply_text(
                "â“ <i>Invalid number.</i> Search for something first or use /list.",
                parse_mode="HTML",
            )
        return

    # Full-text search (admin-scope â€” bot has unrestricted access to the index)
    await context.bot.send_chat_action(chat_id=chat_id, action="typing")

    from .document_index import search_documents
    results = await search_documents(query=text, limit=5, user_role="admin", username="")

    if not results:
        await update.message.reply_text(
            f"ðŸ” <i>No documents found for</i> <b>{text}</b>.\n\n"
            "Try a different word or /list to browse recent files.",
            parse_mode="HTML",
        )
        return

    if len(results) == 1:
        _last_results[chat_id] = results
        await _send_file(update, results[0])
        return

    # 2-5 results â†’ numbered list
    _last_results[chat_id] = results
    lines = [f"{i + 1}. <code>{r['filename']}</code>" for i, r in enumerate(results)]
    await update.message.reply_text(
        f"ðŸ” <b>Found {len(results)} files</b>\n\n"
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
            f"âš ï¸ <b>File not found</b>\n\n"
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
        await update.message.reply_text("ðŸ”’ Send /auth first to link your account.", parse_mode="HTML")
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
            health_icon, health_text = "ðŸ”´", "High load"
        elif cpu > 50 or ram_pct > 70:
            health_icon, health_text = "ðŸŸ¡", "Moderate"
        else:
            health_icon, health_text = "ðŸŸ¢", "Healthy"

        await update.message.reply_text(
            f"ðŸ–¥ <b>AiHomeCloud Status</b>  {health_icon} {health_text}\n\n"
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
            "âš ï¸ <i>Could not read device status.</i>",
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
        await update.message.reply_text("ðŸ”’ Send /auth first to link your account.", parse_mode="HTML")
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
        await update.message.reply_text("ðŸ”’ Send /auth first to link your account.", parse_mode="HTML")
        return

    owner = await _get_chat_folder_owner(chat_id) or "admin"
    first_name = update.effective_user.first_name or "there"
    tg_username = update.effective_user.username
    tg_line = f"@{tg_username}" if tg_username else f"ID: {chat_id}"

    await update.message.reply_text(
        f"ðŸ‘¤ <b>{first_name}</b>  ({tg_line})\n\n"
        f"Personal folder: <b>{owner}</b>\n\n"
        "<i>To switch folder: /auth &lt;name&gt;</i>",
        parse_mode="HTML",
    )


async def _handle_unlink(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("ðŸ”’ Not linked. Nothing to unlink.", parse_mode="HTML")
        return

    from .store import get_value, set_value
    ids = await get_value("telegram_linked_ids", default=[])
    ids = [i for i in ids if int(i) != chat_id]
    await set_value("telegram_linked_ids", ids)

    _pending_uploads.pop(chat_id, None)
    _last_results.pop(chat_id, None)

    await update.message.reply_text(
        "ðŸ”“ <b>Account unlinked.</b>\n\n"
        "<i>Your Telegram account has been removed from AiHomeCloud.\n"
        "Send /auth to link again.</i>",
        parse_mode="HTML",
    )


# ---------------------------------------------------------------------------
# Trash warning scheduler
# ---------------------------------------------------------------------------


async def _trash_warning_loop() -> None:
    """Hourly loop â€” sends a Telegram notification on Saturday at 10 AM when total
    trash exceeds 10 GB.  Fires at most once per ISO week via the KV store."""
    from . import store as _store
    from .config import settings

    while True:
        try:
            await asyncio.sleep(3600)

            now = datetime.now()

            # ── 85 % storage check (daily at hour 9) ────────────────────
            if now.hour == 9:
                storage_warn_day = f"{now.date()}"
                if await _store.get_value("storage_warn_day", default="") != storage_warn_day:
                    try:
                        usage = shutil.disk_usage(settings.nas_root)
                        pct   = usage.used / usage.total * 100 if usage.total else 0
                        if pct >= 85:
                            linked_ids = await _get_linked_ids()
                            if linked_ids and _application is not None:
                                used_gb  = usage.used  / (1024 ** 3)
                                total_gb = usage.total / (1024 ** 3)
                                bar      = _storage_bar(int(pct))
                                smsg = (
                                    f"💾 <b>Storage almost full</b>\n\n"
                                    f"{bar} {pct:.0f}%\n"
                                    f"Used: <b>{used_gb:.1f} GB</b> / {total_gb:.1f} GB\n\n"
                                    "Free up space by emptying the Trash or removing files."
                                )
                                for cid in linked_ids:
                                    with suppress(Exception):
                                        await _application.bot.send_message(
                                            chat_id=cid, text=smsg, parse_mode="HTML"
                                        )
                                await _store.set_value("storage_warn_day", storage_warn_day)
                    except Exception as _se:
                        logger.warning("storage 85%% check error: %s", _se)

            # ── Saturday 10 AM trash check ──────────────────────────────
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
                "Tap <b>Empty Trash</b> to free up space."
            )
            from telegram import InlineKeyboardButton, InlineKeyboardMarkup
            kb = InlineKeyboardMarkup([[
                InlineKeyboardButton("🗑 Empty Trash", callback_data="trash:empty"),
            ]])
            for chat_id in linked_ids:
                with suppress(Exception):
                    await _application.bot.send_message(
                        chat_id=chat_id, text=msg, parse_mode="HTML", reply_markup=kb
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
# Admin helpers
# ---------------------------------------------------------------------------

async def _is_admin_chat(chat_id: int) -> bool:
    """Return True if the chat_id belongs to an admin user."""
    return chat_id in await _get_admin_chat_ids()


# ---------------------------------------------------------------------------
# Approval & deny handlers (Task 9)
# ---------------------------------------------------------------------------

async def _handle_approval_callback(update, context) -> None:  # type: ignore[type-arg]
    """Handle Approve/Deny inline-button presses from admin chat."""
    query = update.callback_query
    await query.answer()
    parts = query.data.split(":")
    action         = parts[1]
    target_chat_id = int(parts[2])

    if action == "approve":
        pendings = await _get_pending_approvals()
        info = next((p for p in pendings if p["chat_id"] == target_chat_id), {})
        first_name = info.get("first_name", "User")
        await _add_linked_id(target_chat_id)
        owner = await _resolve_personal_owner(target_chat_id, first_name)
        await _set_chat_folder_owner(target_chat_id, owner)
        await _remove_pending_approval(target_chat_id)
        if _application is not None:
            with suppress(Exception):
                await _application.bot.send_message(
                    chat_id=target_chat_id,
                    text=(
                        f"✅ <b>Access approved! Welcome, {first_name}.</b>\n\n"
                        f"👤 Personal folder: <b>{owner}</b>\n\n"
                        "• Type anything to <b>search documents</b>\n"
                        "• Send a file to <b>save it to your cloud</b>\n"
                        "• /help — all commands"
                    ),
                    parse_mode="HTML",
                )
        await query.edit_message_text(
            f"✅ Approved <b>{first_name}</b> (chat_id: <code>{target_chat_id}</code>)",
            parse_mode="HTML",
        )
    else:
        await _remove_pending_approval(target_chat_id)
        if _application is not None:
            with suppress(Exception):
                await _application.bot.send_message(
                    chat_id=target_chat_id,
                    text="❌ <b>Access denied.</b>\n\nContact the device owner to request access.",
                    parse_mode="HTML",
                )
        await query.edit_message_text(
            f"❌ Denied request from chat_id <code>{target_chat_id}</code>",
            parse_mode="HTML",
        )


async def _handle_approve_command(update, context) -> None:  # type: ignore[type-arg]
    """Admin command: /approve <chat_id>"""
    chat_id = update.effective_chat.id
    if not await _is_admin_chat(chat_id):
        await update.message.reply_text("🔒 Admin only.", parse_mode="HTML")
        return
    args = context.args or []
    if not args or not args[0].lstrip("-").isdigit():
        await update.message.reply_text("Usage: /approve &lt;chat_id&gt;", parse_mode="HTML")
        return
    target = int(args[0])
    pendings = await _get_pending_approvals()
    info = next((p for p in pendings if p["chat_id"] == target), {})
    first_name = info.get("first_name", "User")
    await _add_linked_id(target)
    owner = await _resolve_personal_owner(target, first_name)
    await _set_chat_folder_owner(target, owner)
    await _remove_pending_approval(target)
    if _application is not None:
        with suppress(Exception):
            await _application.bot.send_message(
                chat_id=target,
                text=f"✅ <b>Access approved! Welcome, {first_name}.</b>\n\n/help to see commands.",
                parse_mode="HTML",
            )
    await update.message.reply_text(f"✅ Approved <code>{target}</code>", parse_mode="HTML")


async def _handle_deny_command(update, context) -> None:  # type: ignore[type-arg]
    """Admin command: /deny <chat_id>"""
    chat_id = update.effective_chat.id
    if not await _is_admin_chat(chat_id):
        await update.message.reply_text("🔒 Admin only.", parse_mode="HTML")
        return
    args = context.args or []
    if not args or not args[0].lstrip("-").isdigit():
        await update.message.reply_text("Usage: /deny &lt;chat_id&gt;", parse_mode="HTML")
        return
    target = int(args[0])
    await _remove_pending_approval(target)
    if _application is not None:
        with suppress(Exception):
            await _application.bot.send_message(
                chat_id=target,
                text="❌ <b>Access denied.</b>\n\nContact the device owner.",
                parse_mode="HTML",
            )
    await update.message.reply_text(f"❌ Denied <code>{target}</code>", parse_mode="HTML")


# ---------------------------------------------------------------------------
# Duplicate file handlers (Task 10)
# ---------------------------------------------------------------------------

async def _handle_keep(update, context) -> None:  # type: ignore[type-arg]
    """Keep (save) a file that was flagged as a duplicate."""
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Send /auth first.", parse_mode="HTML")
        return
    dup = _pending_duplicates.pop(chat_id, None)
    if not dup:
        await update.message.reply_text("No duplicate pending. Send a file first.", parse_mode="HTML")
        return
    temp_path = Path(dup["temp_path"])
    dest_path = Path(dup["dest_path"])
    try:
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(temp_path), str(dest_path))
        await _record_file_hash(dup["md5"], dest_path.name, str(dest_path))
        await _record_recent_file(chat_id, dest_path.name, str(dest_path), dup.get("file_size", 0))
        await update.message.reply_text(
            f"✅ <b>Saved</b> <code>{dest_path.name}</code>", parse_mode="HTML"
        )
    except Exception as exc:
        logger.warning("keep handler error: %s", exc)
        await update.message.reply_text(f"❌ Save failed: {exc}", parse_mode="HTML")


async def _handle_skip(update, context) -> None:  # type: ignore[type-arg]
    """Skip (discard) a file that was flagged as a duplicate."""
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Send /auth first.", parse_mode="HTML")
        return
    dup = _pending_duplicates.pop(chat_id, None)
    if not dup:
        await update.message.reply_text("No duplicate pending.", parse_mode="HTML")
        return
    try:
        temp_path = Path(dup["temp_path"])
        if temp_path.exists():
            temp_path.unlink()
    except Exception:
        pass
    await update.message.reply_text(
        "🗑 Duplicate skipped — file discarded.", parse_mode="HTML"
    )


async def _handle_recent(update, context) -> None:  # type: ignore[type-arg]
    """Show the user's last 5 uploaded files with delete buttons."""
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Send /auth first.", parse_mode="HTML")
        return
    from .store import get_value
    all_recent = await get_value("telegram_recent_files", default=[])
    mine = [r for r in all_recent if r.get("chat_id") == chat_id][-5:]
    if not mine:
        await update.message.reply_text("📂 No recent uploads yet.", parse_mode="HTML")
        return
    from telegram import InlineKeyboardButton, InlineKeyboardMarkup
    rows = []
    for i, r in enumerate(reversed(mine), 1):
        sz     = r.get("size", 0)
        sz_str = f"{sz/(1024*1024):.1f} MB" if sz >= 1024*1024 else f"{sz//1024} KB"
        rows.append([InlineKeyboardButton(
            f"🗑 Delete {r['filename']} ({sz_str})",
            callback_data=f"delrecent:{i-1}:{chat_id}",
        )])
    lines_txt = [f"{i}. <code>{r['filename']}</code>" for i, r in enumerate(reversed(mine), 1)]
    await update.message.reply_text(
        "📂 <b>Recent uploads</b>\n\n" + "\n".join(lines_txt),
        parse_mode="HTML",
        reply_markup=InlineKeyboardMarkup(rows),
    )


async def _handle_storage_cmd(update, context) -> None:  # type: ignore[type-arg]
    """Show storage usage for the NAS root."""
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Send /auth first.", parse_mode="HTML")
        return
    from .config import settings
    try:
        usage    = shutil.disk_usage(settings.nas_root)
        pct      = int(usage.used / usage.total * 100) if usage.total else 0
        used_gb  = usage.used  / (1024 ** 3)
        total_gb = usage.total / (1024 ** 3)
        free_gb  = usage.free  / (1024 ** 3)
        bar      = _storage_bar(pct)
        await update.message.reply_text(
            f"💾 <b>Storage</b>\n\n"
            f"{bar} {pct}%\n"
            f"Used:  <b>{used_gb:.1f} GB</b>\n"
            f"Free:  <b>{free_gb:.1f} GB</b>\n"
            f"Total: <b>{total_gb:.1f} GB</b>",
            parse_mode="HTML",
        )
    except Exception as exc:
        await update.message.reply_text(f"❌ Failed to read storage: {exc}", parse_mode="HTML")


async def _handle_delete_recent_callback(update, context) -> None:  # type: ignore[type-arg]
    """Handle delete-button press from /recent list."""
    query = update.callback_query
    await query.answer()
    parts     = query.data.split(":")
    idx       = int(parts[1])
    owner_cid = int(parts[2])
    from .store import get_value, set_value
    all_recent = await get_value("telegram_recent_files", default=[])
    mine       = [r for r in all_recent if r.get("chat_id") == owner_cid]
    rev_mine   = list(reversed(mine))
    if idx >= len(rev_mine):
        await query.edit_message_text("❌ File not found.", parse_mode="HTML")
        return
    target = rev_mine[idx]
    p = Path(target.get("path", ""))
    try:
        if p.exists():
            p.unlink()
    except Exception as exc:
        await query.edit_message_text(f"❌ Delete failed: {exc}", parse_mode="HTML")
        return
    key        = target.get("path", "")
    all_recent = [r for r in all_recent if r.get("path") != key]
    await set_value("telegram_recent_files", all_recent)
    await query.edit_message_text(
        f"✅ Deleted <code>{target['filename']}</code>", parse_mode="HTML"
    )


async def _handle_empty_trash_callback(update, context) -> None:  # type: ignore[type-arg]
    """Handle Empty Trash inline-button press from trash warning."""
    query = update.callback_query
    await query.answer()
    from . import store as _st
    from .routes.file_routes import _unlink_trash_item
    items  = await _st.get_trash_items()
    errors = 0
    for item in items:
        try:
            _unlink_trash_item(item)
        except Exception:
            errors += 1
    await _st.save_trash_items([])
    if errors:
        await query.edit_message_text(
            f"⚠️ Trash emptied with {errors} error(s).", parse_mode="HTML"
        )
    else:
        await query.edit_message_text("✅ <b>Trash emptied.</b>", parse_mode="HTML")

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

async def start_bot() -> None:
    """Initialise and start the Telegram bot.  No-op if token is not configured."""
    global _application
    from .config import settings

    if not settings.telegram_bot_token:
        logger.info("Telegram bot token not set â€” bot disabled")
        return

    try:
        from telegram.ext import (
            ApplicationBuilder, CommandHandler, MessageHandler,
            CallbackQueryHandler, filters,
        )
    except ImportError:
        logger.warning("python-telegram-bot not installed â€” Telegram bot disabled")
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

        # Use local Bot API server if configured â€” removes 20MB file limit
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

        _application.add_handler(CommandHandler("start",   _handle_start))
        _application.add_handler(CommandHandler("auth",    _handle_auth))
        _application.add_handler(CommandHandler("help",    _handle_help))
        _application.add_handler(CommandHandler("list",    _handle_list))
        _application.add_handler(CommandHandler("status",  _handle_status))
        _application.add_handler(CommandHandler("cancel",  _handle_cancel))
        _application.add_handler(CommandHandler("whoami",  _handle_whoami))
        _application.add_handler(CommandHandler("unlink",  _handle_unlink))
        _application.add_handler(CommandHandler("recent",  _handle_recent))
        _application.add_handler(CommandHandler("storage", _handle_storage_cmd))
        _application.add_handler(CommandHandler("keep",    _handle_keep))
        _application.add_handler(CommandHandler("skip",    _handle_skip))
        _application.add_handler(CommandHandler("approve", _handle_approve_command))
        _application.add_handler(CommandHandler("deny",    _handle_deny_command))
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
        _application.add_handler(
            CallbackQueryHandler(_handle_approval_callback, pattern=r"^approval:")
        )
        _application.add_handler(
            CallbackQueryHandler(_handle_delete_recent_callback, pattern=r"^delrecent:")
        )
        _application.add_handler(
            CallbackQueryHandler(_handle_empty_trash_callback, pattern=r"^trash:empty$")
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
