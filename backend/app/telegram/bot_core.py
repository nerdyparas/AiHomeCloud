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

The bot is entirely optional — it is only started when AHC_TELEGRAM_BOT_TOKEN is
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

from .. import store as _store
from .. import document_index as _docidx
from ..file_sorter import _sort_file, _unique_dest
from ..config import settings

try:
    from telegram import InlineKeyboardButton, InlineKeyboardMarkup
except ImportError:
    InlineKeyboardButton = None  # type: ignore[assignment,misc]
    InlineKeyboardMarkup = None  # type: ignore[assignment,misc]


_POLL_TIMEOUT_SECONDS = 2
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
    created_at: float = 0.0  # time.monotonic() timestamp

    def __post_init__(self) -> None:
        if self.created_at == 0.0:
            import time as _time
            self.created_at = _time.monotonic()


_PENDING_MAX_ENTRIES = 100
_PENDING_TTL_SECONDS = 300  # 5 minutes

# Per-chat pending upload selection state.
_pending_uploads: dict[int, PendingUpload] = {}


def _cleanup_pending_uploads() -> None:
    """Remove expired entries and enforce max size."""
    import time as _time
    now = _time.monotonic()
    # Remove expired
    expired = [k for k, v in _pending_uploads.items()
               if now - v.created_at > _PENDING_TTL_SECONDS]
    for k in expired:
        del _pending_uploads[k]
    # Enforce max size — evict oldest
    if len(_pending_uploads) > _PENDING_MAX_ENTRIES:
        by_age = sorted(_pending_uploads.items(), key=lambda x: x[1].created_at)
        for k, _ in by_age[:len(_pending_uploads) - _PENDING_MAX_ENTRIES]:
            del _pending_uploads[k]

# Per-chat duplicate-detection pending state.
_pending_duplicates: dict[int, dict] = {}

# ---------------------------------------------------------------------------
# Per-chat rate limiting — sliding window (30 commands / 60 seconds)
# ---------------------------------------------------------------------------
_RATE_LIMIT_WINDOW = 60  # seconds
_RATE_LIMIT_MAX = 30     # max commands per window
_chat_timestamps: dict[int, list[float]] = {}


def _is_rate_limited(chat_id: int) -> bool:
    """Return True if chat_id has exceeded the per-minute command limit."""
    import time as _time
    now = _time.monotonic()
    cutoff = now - _RATE_LIMIT_WINDOW
    # setdefault returns the same list object every time — mutate in place so
    # concurrent readers always see a consistent view of the same list.
    timestamps = _chat_timestamps.setdefault(chat_id, [])
    timestamps[:] = [t for t in timestamps if t > cutoff]
    if len(timestamps) >= _RATE_LIMIT_MAX:
        return True
    timestamps.append(now)
    return False


class DuplicateFileError(Exception):
    """Raised when an uploaded file matches an existing SHA-256 hash."""

    def __init__(self, sha256: str, existing: dict, temp_path: Path) -> None:
        self.sha256 = sha256
        self.existing = existing
        self.temp_path = temp_path

# Weekly trash-warning scheduler task
_TRASH_WARNING_BYTES = 10 * 1024 * 1024 * 1024  # 10 GB


# ---------------------------------------------------------------------------
# Access control — linked chat IDs persisted in KV store
# ---------------------------------------------------------------------------

async def _get_linked_ids() -> set[int]:
    """Return set of linked Telegram chat IDs from KV store."""
    ids = await _store.get_value("telegram_linked_ids", default=[])
    return {int(i) for i in ids if str(i).lstrip("-").isdigit()}


async def _add_linked_id(chat_id: int) -> None:
    """Persistently link a new chat_id."""
    def _add(ids):
        if chat_id not in ids:
            ids.append(chat_id)
        return ids
    await _store.atomic_update("telegram_linked_ids", _add, default=[])


# ---------------------------------------------------------------------------
# Pending approval helpers (Task 9)
# ---------------------------------------------------------------------------

async def _get_pending_approvals() -> list[dict]:
    """Return the list of pending Telegram auth approval requests."""
    return await _store.get_value("telegram_pending_approvals", default=[])


async def _add_pending_approval(chat_id: int, username: str, first_name: str) -> None:
    """Add a chat_id to the pending-approval list."""
    def _add(items):
        if not any(p["chat_id"] == chat_id for p in items):
            items.append({
                "chat_id": chat_id,
                "username": username,
                "first_name": first_name,
                "requested_at": datetime.now().isoformat(),
            })
        return items
    await _store.atomic_update("telegram_pending_approvals", _add, default=[])


async def _remove_pending_approval(chat_id: int) -> None:
    """Remove a chat_id from the pending-approval list."""
    await _store.atomic_update(
        "telegram_pending_approvals",
        lambda items: [p for p in items if p["chat_id"] != chat_id],
        default=[],
    )


async def _get_admin_chat_ids() -> set[int]:
    """Return Telegram chat IDs whose folder owner is an AHC admin user."""
    users = await _store.get_users()
    admin_names = {
        str(u.get("name", "")).casefold()
        for u in users
        if u.get("is_admin")
    }
    if not admin_names:
        return set()
    mapping = await _store.get_value("telegram_chat_folder_owners", default={})
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

    mapping = await _store.get_value("telegram_chat_folder_owners", default={})
    mapping[str(chat_id)] = username
    await _store.set_value("telegram_chat_folder_owners", mapping)


async def _get_chat_folder_owner(chat_id: int) -> Optional[str]:
    """Return preferred personal-folder owner for a Telegram chat if configured."""

    mapping = await _store.get_value("telegram_chat_folder_owners", default={})
    value = mapping.get(str(chat_id))
    return value if isinstance(value, str) and value.strip() else None


async def _resolve_personal_owner(chat_id: int, preferred_name: str = "") -> str:
    """Resolve which AiHomeCloud personal folder this chat should use."""

    explicit = await _get_chat_folder_owner(chat_id)
    if explicit:
        return explicit

    users = await _store.get_users()
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


# ---------------------------------------------------------------------------
# Duplicate-detection helpers (Task 10)
# ---------------------------------------------------------------------------

def _compute_sha256(path: Path) -> str:
    """Return the hex SHA-256 digest of *path*."""
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


async def _check_duplicate(path: Path) -> tuple[str, Optional[dict]]:
    """Return (sha256_hex, record_or_None) for the given file."""
    sha = _compute_sha256(path)
    hashes = await _store.get_value("telegram_file_hashes", default={})
    record = hashes.get(sha)
    if record:
        return sha, {**record, "sha256": sha}
    return sha, None


async def _record_file_hash(sha256: str, filename: str, path: str) -> None:
    """Persist a SHA-256 → file mapping in the KV store."""
    _MAX_HASHES = 10_000

    def _add(hashes):
        hashes[sha256] = {
            "filename": filename,
            "path": path,
            "saved_at": datetime.now().isoformat(),
        }
        if len(hashes) > _MAX_HASHES:
            oldest = sorted(hashes, key=lambda k: hashes[k].get("saved_at", ""))
            for k in oldest[: len(hashes) - _MAX_HASHES]:
                del hashes[k]
        return hashes
    await _store.atomic_update("telegram_file_hashes", _add, default={})


async def _record_recent_file(chat_id: int, filename: str, path: str, size: int) -> None:
    """Prepend an entry to the recent-files list (max 5 entries)."""
    def _add(recent):
        recent.insert(0, {
            "filename": filename,
            "path": path,
            "size": size,
            "chat_id": chat_id,
            "saved_at": datetime.now().isoformat(),
        })
        return recent[:5]
    await _store.atomic_update("telegram_recent_files", _add, default=[])


async def _store_private_or_shared_file(bot, pending: PendingUpload, base_dir: Path, added_by: str) -> Path:
    """Download to .inbox, sort immediately, and index if it lands in Documents/."""

    inbox_dir = base_dir / ".inbox"
    inbox_dir.mkdir(parents=True, exist_ok=True)
    temp_name = _sanitize_filename(pending.filename)
    temp_path = inbox_dir / temp_name
    try:
        await _download_to_path(bot, pending.file_id, temp_path)
    except Exception:
        if temp_path.exists():
            try:
                temp_path.unlink()
                logger.warning("download_cleanup removed partial file temp=%s", temp_path)
            except OSError:
                pass
        raise

    # Duplicate detection: compare SHA-256 against known-file index
    file_sha, existing = await _check_duplicate(temp_path)
    if existing:
        raise DuplicateFileError(sha256=existing.get("sha256", ""), existing=existing, temp_path=temp_path)

    dest = _sort_file(temp_path, base_dir, check_age=False)
    if dest is None:
        raise RuntimeError("Failed to sort downloaded file")

    if dest.parent.name == "Documents":
        await _docidx.index_document(str(dest), dest.name, added_by)

    # Record hash — reuse the SHA-256 computed during duplicate check
    await _record_file_hash(file_sha, dest.name, str(dest))
    return dest


async def _store_entertainment_file(bot, pending: PendingUpload) -> Path:
    """Download file directly into shared Entertainment folder."""

    entertainment_dir = settings.entertainment_path
    entertainment_dir.mkdir(parents=True, exist_ok=True)
    safe_name = _sanitize_filename(pending.filename, default_stem="telegram_media")
    dest_path = _unique_dest(entertainment_dir, safe_name)
    try:
        await _download_to_path(bot, pending.file_id, dest_path)
    except Exception:
        if dest_path.exists():
            try:
                dest_path.unlink()
                logger.warning("download_cleanup removed partial file dest=%s", dest_path)
            except OSError:
                pass
        raise

    # Duplicate detection
    file_sha, existing = await _check_duplicate(dest_path)
    if existing:
        try:
            dest_path.unlink()
        except OSError:
            pass
        raise DuplicateFileError(sha256=existing.get("sha256", ""), existing=existing, temp_path=dest_path)

    await _record_file_hash(file_sha, dest_path.name, str(dest_path))
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
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤  My Folder",        callback_data=f"dest:{chat_id}:1")],
        [InlineKeyboardButton("👨\u200d👩\u200d👧  Family Shared",   callback_data=f"dest:{chat_id}:2")],
        [InlineKeyboardButton("🎬  Entertainment",   callback_data=f"dest:{chat_id}:3")],
        [InlineKeyboardButton("❌  Cancel",            callback_data=f"dest:{chat_id}:cancel")],
    ])

# ---------------------------------------------------------------------------
# Module-proxy: resolve the shim module at call-time for test patching.
# ---------------------------------------------------------------------------

import sys as _sys

def _tb():
    """Return app.telegram_bot so test monkey-patches propagate."""
    return _sys.modules["app.telegram_bot"]




async def _is_allowed(chat_id: int) -> bool:
    """Return True if chat_id has linked their account via /auth."""
    linked = await _get_linked_ids()
    return chat_id in linked





async def _check_allowed_and_rate(update) -> bool:
    """Return True if the user is linked AND not rate-limited.

    Sends an appropriate reply if either check fails.
    """
    chat_id = update.effective_chat.id
    if not await _tb()._is_allowed(chat_id):
        await update.message.reply_text(
            "\U0001f512 Send /auth first to link your account.",
            parse_mode="HTML",
        )
        return False
    if _is_rate_limited(chat_id):
        await update.message.reply_text(
            "\u23f3 Please wait a moment \u2014 too many requests.",
        )
        return False
    return True


# ---------------------------------------------------------------------------
# Command + Message handlers
# ---------------------------------------------------------------------------




def _storage_bar(percent: float, width: int = 10) -> str:
    """Return a text progress bar for storage, e.g. \u2593\u2593\u2593\u2593\u2593\u2591\u2591\u2591\u2591\u2591 50%."""
    filled = round(percent / 100 * width)
    bar = "\u2593" * filled + "\u2591" * (width - filled)
    return bar





# ---------------------------------------------------------------------------
# Trash warning scheduler
# ---------------------------------------------------------------------------


async def _trash_warning_loop() -> None:
    """Hourly loop — sends a Telegram notification on Saturday at 10 AM when total
    trash exceeds 10 GB.  Fires at most once per ISO week via the KV store."""

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
                            if linked_ids and _tb()._application is not None:
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
                                        await _tb()._application.bot.send_message(
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
            if not linked_ids or _tb()._application is None:
                continue

            total_gb = total_bytes / (1024 ** 3)
            msg = (
                f"🗑 <b>Trash is getting full</b>\n\n"
                f"Total trash: <b>{total_gb:.1f} GB</b> (threshold: 10 GB)\n\n"
                "Tap <b>Empty Trash</b> to free up space."
            )
            kb = InlineKeyboardMarkup([[
                InlineKeyboardButton("🗑 Empty Trash", callback_data="trash:empty"),
            ]])
            for chat_id in linked_ids:
                with suppress(Exception):
                    await _tb()._application.bot.send_message(
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




# ---------------------------------------------------------------------------
# Admin helpers
# ---------------------------------------------------------------------------

async def _is_admin_chat(chat_id: int) -> bool:
    """Return True if the chat_id belongs to an admin user."""
    return chat_id in await _get_admin_chat_ids()


# ---------------------------------------------------------------------------
# Approval & deny handlers (Task 9)
# ---------------------------------------------------------------------------

