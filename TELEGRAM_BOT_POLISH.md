# Telegram Bot — Polish, Professional Replies, and New Commands

## What this file is

A full rewrite of `backend/app/telegram_bot.py` with:
- Consistent HTML-formatted messages throughout
- Inline keyboard buttons replacing "reply with 1/2/3" text prompts
- 4 new commands: `/status`, `/cancel`, `/whoami`, `/unlink`
- Typing indicator while processing search and list
- File type emojis in upload messages
- Deduplicated upload success messages (one edit, not edit + new reply)
- Stale brand name "CubieCloud" → "AiHomeCloud" throughout

---

## Architecture rules — never break these

- `run_command()` returns `(rc, stdout, stderr)` — unpack all three
- `logger` not `print()`
- `settings.nas_root`, `settings.personal_path`, `settings.family_path`,
  `settings.entertainment_path` — never hardcode paths
- `friendlyError` is Flutter-only; this is Python — use logger for errors
- No `shell=True` anywhere

---

## Part 1 — Parse mode: HTML throughout

Switch ALL `reply_text`, `edit_text`, and `send_message` calls to use
`parse_mode="HTML"`. Replace all Markdown (`*bold*`, `_italic_`) with
HTML (`<b>bold</b>`, `<i>italic</i>`).

Update the trash warning loop message:
```python
# BEFORE (wrong brand + Markdown)
msg = (
    f"\U0001f5d1 *Trash is getting full!*\n\n"
    f"Total trash: *{total_gb:.1f} GB* (limit: 10 GB)\n\n"
    f"Please clean up your trash to free up space.\n"
    f"Open the CubieCloud app → Files → Trash."  # ← wrong brand
)

# AFTER (correct brand + HTML)
msg = (
    f"🗑 <b>Trash is getting full</b>\n\n"
    f"Total trash: <b>{total_gb:.1f} GB</b> (threshold: 10 GB)\n\n"
    f"Open <b>AiHomeCloud</b> → Files → Trash to free up space."
)
```

Add `parse_mode="HTML"` to every `send_message` call in `_trash_warning_loop`.

---

## Part 2 — Inline keyboard for upload destination

Replace the text-based "Reply with 1, 2, or 3" flow with an inline keyboard.

### 2a — New imports (add at top of function scope inside `start_bot`)

```python
from telegram import InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import CallbackQueryHandler
```

### 2b — Replace `_pending_upload_prompt` function

Delete the old `_pending_upload_prompt(filename)` string function entirely.
Replace with this function that builds an inline keyboard message:

```python
def _file_type_emoji(kind: str) -> str:
    return {
        "document": "📄",
        "video":    "🎬",
        "audio":    "🎵",
        "photo":    "🖼",
        "voice":    "🎙",
    }.get(kind, "📁")


def _make_destination_keyboard(chat_id: int) -> InlineKeyboardMarkup:
    """Return a 3-button inline keyboard for upload destination choice."""
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("👤  My Folder",     callback_data=f"dest:{chat_id}:1")],
        [InlineKeyboardButton("👨‍👩‍👧  Family Shared",  callback_data=f"dest:{chat_id}:2")],
        [InlineKeyboardButton("🎬  Entertainment",  callback_data=f"dest:{chat_id}:3")],
        [InlineKeyboardButton("❌  Cancel",          callback_data=f"dest:{chat_id}:cancel")],
    ])
```

### 2c — Update `_handle_media_message`

Replace the final `await update.message.reply_text(_pending_upload_prompt(...))` call with:

```python
emoji = _file_type_emoji(pending.kind)
size_text = _human_size(pending.file_size) if pending.file_size else "unknown size"
await update.message.reply_text(
    f"{emoji} <b>{pending.filename}</b>\n"
    f"<i>{size_text}</i>\n\n"
    "Where would you like to save this?",
    parse_mode="HTML",
    reply_markup=_make_destination_keyboard(chat_id),
)
```

### 2d — New callback query handler

Add this function:

```python
async def _handle_destination_callback(update, context) -> None:
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
        await query.edit_message_text("❌ Upload cancelled.")
        return

    if choice not in {"1", "2", "3"}:
        return

    # Remove the keyboard so buttons can't be tapped twice
    await query.edit_message_reply_markup(reply_markup=None)

    # Reuse the existing handler — it reads from _pending_uploads[chat_id]
    # We need a minimal update-like object that has message for reply_text.
    # Instead, pass context.bot directly and replicate the logic inline.
    pending = _pending_uploads.get(chat_id)
    if pending is None:
        await query.edit_message_text("⚠️ No pending upload found. Please resend the file.")
        return

    await _process_upload_choice(query, context, chat_id, choice, pending)
```

### 2e — Extract upload processing into `_process_upload_choice`

The existing `_handle_pending_upload_choice` is wired to a text reply.
Rename it to `_process_upload_choice` and update its signature to accept
a `query_or_update` duck-typed object:

```python
async def _process_upload_choice(
    source,  # either update or callback query — both have .message or .message
    context,
    chat_id: int,
    choice: str,
    pending: PendingUpload,
) -> None:
    from .config import settings

    owner_hint = ""
    if hasattr(source, "effective_user") and source.effective_user:
        owner_hint = source.effective_user.username or source.effective_user.first_name or ""
    elif hasattr(source, "from_user") and source.from_user:
        owner_hint = source.from_user.username or source.from_user.first_name or ""

    owner = await _resolve_personal_owner(chat_id, owner_hint)

    dest_labels = {
        "1": f"👤 My Folder ({owner})",
        "2": "👨‍👩‍👧 Family Shared",
        "3": "🎬 Entertainment",
    }
    target_label = dest_labels[choice]
    emoji = _file_type_emoji(pending.kind)
    size_text = _human_size(pending.file_size) if pending.file_size else "unknown size"

    loop = asyncio.get_running_loop()
    started_at = loop.time()

    # Get the message to reply to — works for both update and callback query
    msg_to_reply = (
        source.message
        if hasattr(source, "message")
        else source
    )

    status_message = await context.bot.send_message(
        chat_id=chat_id,
        text=(
            f"📥 <b>Downloading…</b>\n\n"
            f"{emoji} <code>{pending.filename}</code>\n"
            f"📦 {size_text}\n"
            f"📂 {target_label}\n"
            f"⏱ Just started"
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

        # Single success edit — no second reply_text
        await _safe_edit_text(
            status_message,
            (
                f"✅ <b>Saved</b>\n\n"
                f"{emoji} <code>{dest.name}</code>\n"
                f"📂 {target_label}\n"
                f"📦 {_human_size(actual_bytes)}\n"
                f"⚡ {_format_avg_speed(actual_bytes, elapsed_seconds)}  "
                f"⏱ {_format_elapsed(elapsed_seconds)}"
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
                    f"⚠️ <b>File too large</b>\n\n"
                    f"{emoji} <code>{pending.filename}</code>\n"
                    f"⏱ Failed after {elapsed_text}\n\n"
                    "Ask your admin to enable <b>Large File mode</b> in AiHomeCloud:\n"
                    "<i>More → Telegram Bot → Large file mode (up to 2 GB)</i>"
                ),
            )
        elif _is_timeout_error(exc):
            await _safe_edit_text(
                status_message,
                (
                    f"⏱ <b>Download timed out</b>\n\n"
                    f"{emoji} <code>{pending.filename}</code>\n"
                    f"Failed after {elapsed_text}\n\n"
                    "Network may be slow. Please try again."
                ),
            )
        else:
            await _safe_edit_text(
                status_message,
                (
                    f"❌ <b>Save failed</b>\n\n"
                    f"{emoji} <code>{pending.filename}</code>\n"
                    f"⏱ {elapsed_text}\n\n"
                    "Please try again."
                ),
            )
    finally:
        if progress_task is not None:
            progress_task.cancel()
            with suppress(asyncio.CancelledError):
                await progress_task
```

### 2f — Update `_handle_message` to remove dead text-based choice handling

In `_handle_message`, remove the block:
```python
if text in {"1", "2", "3"}:
    handled = await _handle_pending_upload_choice(update, context, text)
    if handled:
        return
```

With inline keyboards, destination choices come through the callback query
handler, not as text messages. This block is dead code once keyboards are live.

### 2g — Register the callback handler in `start_bot`

Add after the existing `_application.add_handler` calls:
```python
_application.add_handler(
    CallbackQueryHandler(_handle_destination_callback, pattern=r"^dest:")
)
```

---

## Part 3 — Rewrite all command reply messages

### 3a — `/start`

```python
async def _handle_start(update, context) -> None:
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
```

### 3b — `/auth`

```python
async def _handle_auth(update, context) -> None:
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
```

### 3c — `/help`

```python
async def _handle_help(update, context) -> None:
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
```

### 3d — `/list`

```python
async def _handle_list(update, context) -> None:
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Send /auth first to link your account.", parse_mode="HTML")
        return

    await context.bot.send_chat_action(chat_id=chat_id, action="typing")

    from .document_index import list_recent_documents
    docs = await list_recent_documents(limit=10)
    if not docs:
        await update.message.reply_text(
            "📂 <i>No documents indexed yet.</i>\n\n"
            "Send a file to start building your library.",
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
```

### 3e — Search in `_handle_message`

```python
    # Show typing indicator while searching
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

    _last_results[chat_id] = results
    lines = [f"{i + 1}. <code>{r['filename']}</code>" for i, r in enumerate(results)]
    await update.message.reply_text(
        f"🔍 <b>Found {len(results)} files</b>\n\n"
        + "\n".join(lines)
        + "\n\n<i>Reply with a number to receive the file.</i>",
        parse_mode="HTML",
    )
```

### 3f — Numeric file selection in `_handle_message`

```python
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
```

### 3g — Update `_send_file` for missing file

```python
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
```

---

## Part 4 — New commands

### 4a — `/status` command

Add this handler:

```python
async def _handle_status(update, context) -> None:
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Send /auth first to link your account.", parse_mode="HTML")
        return

    await context.bot.send_chat_action(chat_id=chat_id, action="typing")

    try:
        import psutil
        import time as _time
        from .board import get_board_info

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

        # Temperature — try reading board-specific thermal path
        temp_str = "n/a"
        try:
            temps = psutil.sensors_temperatures()
            if temps:
                for key in ("cpu_thermal", "soc_thermal", "coretemp"):
                    entries = temps.get(key, [])
                    if entries:
                        temp_str = f"{entries[0].current:.0f}°C"
                        break
        except Exception:
            pass

        # Storage
        from .config import settings
        try:
            usage = psutil.disk_usage(str(settings.nas_root))
            used_gb = round(usage.used / (1024 ** 3), 1)
            total_gb = round(usage.total / (1024 ** 3), 1)
            free_gb = round(usage.free / (1024 ** 3), 1)
            pct = round(usage.used / usage.total * 100, 1)
            storage_bar = _storage_bar(pct)
            storage_str = f"{storage_bar}  {used_gb} / {total_gb} GB ({pct}%)"
        except Exception:
            storage_str = "unavailable"
            free_gb = 0.0

        # Health indicator
        if cpu > 80 or ram_pct > 85:
            health_icon = "🔴"
            health_text = "High load"
        elif cpu > 50 or ram_pct > 70:
            health_icon = "🟡"
            health_text = "Moderate"
        else:
            health_icon = "🟢"
            health_text = "Healthy"

        await update.message.reply_text(
            f"🖥 <b>AiHomeCloud Status</b>  {health_icon} {health_text}\n\n"
            f"⏱ Uptime:  <b>{uptime_str}</b>\n"
            f"🧠 CPU:     <b>{cpu:.0f}%</b>\n"
            f"💾 RAM:     <b>{ram_used_gb} / {ram_total_gb} GB</b>  ({ram_pct}%)\n"
            f"🌡 Temp:    <b>{temp_str}</b>\n\n"
            f"💽 Storage\n{storage_str}\n"
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
    """Return a text progress bar for storage, e.g. ▓▓▓▓▓░░░░░ 50%."""
    filled = round(percent / 100 * width)
    bar = "▓" * filled + "░" * (width - filled)
    return bar
```

### 4b — `/cancel` command

```python
async def _handle_cancel(update, context) -> None:
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("🔒 Send /auth first to link your account.", parse_mode="HTML")
        return

    had_pending = chat_id in _pending_uploads
    _pending_uploads.pop(chat_id, None)
    _last_results.pop(chat_id, None)

    if had_pending:
        await update.message.reply_text(
            "❌ <b>Upload cancelled.</b>\n\n<i>Send a new file whenever you're ready.</i>",
            parse_mode="HTML",
        )
    else:
        await update.message.reply_text(
            "✅ <i>Nothing to cancel.</i>",
            parse_mode="HTML",
        )
```

### 4c — `/whoami` command

```python
async def _handle_whoami(update, context) -> None:
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
```

### 4d — `/unlink` command

```python
async def _handle_unlink(update, context) -> None:
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
```

---

## Part 5 — Update `_upload_progress_heartbeat`

```python
async def _upload_progress_heartbeat(
    message, filename: str, size_text: str, target_label: str, started_at: float
) -> None:
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
```

Add `parse_mode="HTML"` to the `_safe_edit_text` call. Update `_safe_edit_text`:

```python
async def _safe_edit_text(message, text: str, parse_mode: str = "HTML") -> None:
    if message is None:
        return
    try:
        await message.edit_text(text, parse_mode=parse_mode)
    except Exception:
        return
```

---

## Part 6 — Register all new handlers in `start_bot`

In the `start_bot` function, add these handler registrations after the
existing ones:

```python
_application.add_handler(CommandHandler("status",  _handle_status))
_application.add_handler(CommandHandler("cancel",  _handle_cancel))
_application.add_handler(CommandHandler("whoami",  _handle_whoami))
_application.add_handler(CommandHandler("unlink",  _handle_unlink))
_application.add_handler(
    CallbackQueryHandler(_handle_destination_callback, pattern=r"^dest:")
)
```

Also add `CallbackQueryHandler` to the import line:
```python
from telegram.ext import (
    ApplicationBuilder, CommandHandler, MessageHandler,
    CallbackQueryHandler, filters,
)
```

And add to the `InlineKeyboardButton` import:
```python
from telegram import InlineKeyboardButton, InlineKeyboardMarkup
```

Move both of these imports to the top of `start_bot` (they're only available
when `python-telegram-bot` is installed, so they must stay inside the try block).

---

## Validation

```bash
python3 -m py_compile backend/app/telegram_bot.py && echo OK
pytest -q backend/tests/test_telegram_bot.py \
  --ignore=backend/tests/test_hardware_integration.py
```

## Manual test checklist

**Auth and linking:**
- `/start` unlinked → "Hi [name]! Send /auth..." ✅
- `/start` linked → "Welcome back, [name]!" ✅
- `/auth` new → linked, shows folder name ✅
- `/auth Paras` → switches to Paras folder, confirms ✅
- `/auth` already linked → shows current folder ✅
- `/whoami` → shows name, TG handle, linked folder ✅
- `/unlink` → removed, next `/start` shows setup message ✅

**File upload:**
- Send a document → shows filename, size, 4-button inline keyboard ✅
- Tap "My Folder" → spinner dismissed, progress message appears ✅
- Tap "Cancel" → "Upload cancelled" message ✅
- `/cancel` with pending file → "Upload cancelled" ✅
- `/cancel` without pending → "Nothing to cancel" ✅
- Large file (>5MB) → progress heartbeat updates every 15s ✅
- Upload complete → single edit to success (no duplicate reply) ✅
- Too large error → HTML-formatted error with Large File mode instructions ✅

**Search:**
- Type "invoice" → typing action shown → results with HTML formatting ✅
- 0 results → "No documents found for invoice" with tip ✅
- 1 result → file sent directly ✅
- Multiple results → numbered list in code blocks ✅
- Reply "2" → correct file sent ✅
- Reply "99" → "Invalid number" message ✅

**New commands:**
- `/status` → shows uptime, CPU, RAM, temp, storage bar ✅
- `/status` with high CPU → red dot and "High load" ✅
- `/list` → recent docs with added_by in italic ✅
- `/help` → all 7 commands listed, personalised folder name ✅

**Trash warning:**
- Message uses "AiHomeCloud" (not "CubieCloud") ✅
- Message uses HTML bold not Markdown asterisks ✅
