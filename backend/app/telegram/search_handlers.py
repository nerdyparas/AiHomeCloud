"""Telegram bot handlers — search handlers."""

import shutil
import urllib.parse
from pathlib import Path

from .bot_core import (
    logger,
    _check_allowed_and_rate, _is_admin_chat,
    _pending_uploads, _last_results,
    _storage_bar,
    _get_chat_folder_owner,
)
from ..config import settings
from .. import store as _store

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




async def _handle_duplicates(update, context) -> None:  # type: ignore[type-arg]
    """Show last duplicate scan results with per-set delete buttons."""
    chat_id = update.effective_chat.id
    if not await _check_allowed_and_rate(update):
        return

    await context.bot.send_chat_action(chat_id=chat_id, action="typing")

    results = await _store.get_value("duplicate_scan_results", default=[])
    ran_at = await _store.get_value("duplicate_scan_ran_at", default=None)

    if not results:
        ran_note = f"\nLast scan: <i>{ran_at}</i>" if ran_at else ""
        is_admin = await _is_admin_chat(chat_id)
        admin_hint = "  Use /scan to run now." if is_admin else ""
        await update.message.reply_text(
            f"✅ <b>No duplicates found.</b>{ran_note}\n"
            f"<i>Scan runs nightly at 2 AM.{admin_hint}</i>",
            parse_mode="HTML",
        )
        return

    ran_note = f"  <i>(scan: {ran_at[:10] if ran_at else 'unknown'})</i>"
    await update.message.reply_text(
        f"🔍 <b>{len(results)} duplicate set{'s' if len(results) != 1 else ''} found</b>{ran_note}\n"
        "<i>Tap a button to delete one copy permanently.</i>",
        parse_mode="HTML",
    )

    for entry in results[:10]:
        size_bytes = entry.get("sizeBytes", 0)
        if size_bytes < 1024 * 1024:
            size_str = f"{size_bytes / 1024:.0f} KB"
        elif size_bytes < 1024 ** 3:
            size_str = f"{size_bytes / (1024 * 1024):.1f} MB"
        else:
            size_str = f"{size_bytes / (1024 ** 3):.2f} GB"

        filename = entry.get("filename", "unknown")
        copies = entry.get("copies", [])
        hash_prefix = entry.get("hash", "")[:16]

        # callback_data: "dupdelete:<hash16>:<copy_idx>" — max ~28 chars (well under 64 limit)
        buttons = [
            [InlineKeyboardButton(
                f"🗑 Delete {c.get('owner', f'copy {i+1}')} copy",
                callback_data=f"dupdelete:{hash_prefix}:{i}",
            )]
            for i, c in enumerate(copies)
        ]
        buttons.append([InlineKeyboardButton("⏭ Skip", callback_data=f"dupskip:{hash_prefix}")])

        await update.message.reply_text(
            f"📄 <code>{filename}</code> — {size_str} × {len(copies)} copies\n"
            + "\n".join(f"  • {c['owner']}: <code>{c['path']}</code>" for c in copies),
            parse_mode="HTML",
            reply_markup=InlineKeyboardMarkup(buttons),
        )

    if len(results) > 10:
        await update.message.reply_text(
            f"<i>…and {len(results) - 10} more duplicate sets not shown.</i>",
            parse_mode="HTML",
        )


async def _handle_scan(update, context) -> None:  # type: ignore[type-arg]
    """Trigger an immediate duplicate scan (admin only)."""
    chat_id = update.effective_chat.id
    if not await _check_allowed_and_rate(update):
        return

    if not await _is_admin_chat(chat_id):
        await update.message.reply_text(
            "🔒 <i>Admin access required to run a scan.</i>",
            parse_mode="HTML",
        )
        return

    from ..duplicate_scanner import get_duplicate_scanner
    import asyncio
    scanner = get_duplicate_scanner()
    if scanner.is_scanning:
        await update.message.reply_text(
            "⏳ <i>A scan is already in progress.</i>",
            parse_mode="HTML",
        )
        return

    asyncio.create_task(scanner._scan_nas_for_duplicates(), name="telegram_dup_scan")
    await update.message.reply_text(
        "🔍 <b>Storage scan started.</b>\n\n"
        "I'll send a summary at 6 PM, or use /duplicates to check anytime.",
        parse_mode="HTML",
    )


async def _handle_dupdelete_callback(update, context) -> None:  # type: ignore[type-arg]
    """Inline keyboard callback: permanently delete one copy from a duplicate set."""
    query = update.callback_query
    await query.answer()

    chat_id = query.message.chat.id
    if not await _is_admin_chat(chat_id):
        await query.edit_message_text("🔒 Admin access required.")
        return

    # "dupdelete:<hash16>:<copy_idx>"
    parts = query.data.split(":")
    if len(parts) != 3:
        await query.edit_message_text("❌ Invalid action.")
        return

    _, hash_prefix, idx_str = parts
    try:
        copy_idx = int(idx_str)
    except ValueError:
        await query.edit_message_text("❌ Invalid copy index.")
        return

    results = await _store.get_value("duplicate_scan_results", default=[])
    entry = next(
        (r for r in results if r.get("hash", "").startswith(hash_prefix)),
        None,
    )
    if entry is None:
        await query.edit_message_text("⚠️ Duplicate set no longer found (already resolved?).")
        return

    copies = entry.get("copies", [])
    if copy_idx >= len(copies):
        await query.edit_message_text("⚠️ Copy index out of range.")
        return

    target_path = Path(copies[copy_idx]["path"])
    if not target_path.exists():
        await query.edit_message_text(
            f"⚠️ File already gone: <code>{target_path.name}</code>",
            parse_mode="HTML",
        )
        return

    try:
        target_path.unlink()
        logger.info("telegram_dupdelete path=%s", target_path)
    except OSError as exc:
        await query.edit_message_text(f"❌ Delete failed: {exc}")
        return

    # Best-effort document index removal
    try:
        nas_rel = "/" + str(target_path.relative_to(settings.nas_root.resolve())).replace("\\", "/")
        await _docidx.remove_document(nas_rel)
    except Exception:
        pass

    # Prune stored results: remove this path, drop sets with <2 copies remaining
    path_str = str(target_path)

    def _prune(stored: list) -> list:
        out = []
        for r in stored:
            remaining = [c for c in r.get("copies", []) if c["path"] != path_str]
            if len(remaining) >= 2:
                out.append({**r, "copies": remaining})
        return out

    await _store.atomic_update("duplicate_scan_results", _prune, default=[])

    await query.edit_message_text(
        f"✅ Deleted: <code>{target_path.name}</code>",
        parse_mode="HTML",
    )


async def _handle_dupskip_callback(update, context) -> None:  # type: ignore[type-arg]
    """Inline keyboard callback: dismiss a duplicate set without deleting."""
    query = update.callback_query
    await query.answer()
    await query.edit_message_reply_markup(reply_markup=None)


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


