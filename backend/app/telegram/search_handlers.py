"""Telegram bot handlers — search handlers."""

import shutil
from pathlib import Path

from .bot_core import (
    logger,
    _check_allowed_and_rate, _is_admin_chat,
    _pending_uploads, _last_results,
    _storage_bar,
    _get_chat_folder_owner,
)
from ..config import settings

from .. import document_index as _docidx

try:
    from telegram import InlineKeyboardButton, InlineKeyboardMarkup
except ImportError:
    InlineKeyboardButton = None  # type: ignore[assignment,misc]
    InlineKeyboardMarkup = None  # type: ignore[assignment,misc]

try:
    import psutil
except ImportError:
    psutil = None  # type: ignore[assignment]



async def _handle_help(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _check_allowed_and_rate(update):
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
    if not await _check_allowed_and_rate(update):
        return

    await context.bot.send_chat_action(chat_id=chat_id, action="typing")
    docs = await _docidx.list_recent_documents(limit=10)
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
    if not await _check_allowed_and_rate(update):
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
    results = await _docidx.search_documents(query=text, limit=5, user_role="admin", username="")

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
    nas_path = doc.get("path", "")
    abs_path = settings.nas_root / nas_path.lstrip("/")
    p = Path(str(abs_path))
    if not p.exists() or not p.is_file():
        if nas_path:
            await _docidx.remove_document(nas_path)
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




# ---------------------------------------------------------------------------
# New commands: /status, /cancel, /whoami, /unlink
# ---------------------------------------------------------------------------


async def _handle_status(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _check_allowed_and_rate(update):
        return

    await context.bot.send_chat_action(chat_id=chat_id, action="typing")

    try:
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




async def _handle_cancel(update, context) -> None:  # type: ignore[type-arg]
    chat_id = update.effective_chat.id
    if not await _check_allowed_and_rate(update):
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
    if not await _check_allowed_and_rate(update):
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




async def _handle_storage_cmd(update, context) -> None:  # type: ignore[type-arg]
    """Show storage usage for the NAS root."""
    if not await _check_allowed_and_rate(update):
        return
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


