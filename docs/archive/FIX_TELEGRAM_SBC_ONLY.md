# FIX: Telegram bot handles ALL files entirely on SBC — no phone redirect

## The problem

When a file is >20MB and `telegram_local_api_enabled=False`, the bot sends the
user a one-time browser link and waits for them to re-upload from their phone.
This is wrong — the SBC should download everything itself.

The fix has two parts:
1. Remove the upload-link fallback from the bot entirely
2. Make the local API server mandatory — if it's not running, tell the user
   to enable it in settings, not to open a browser link

The `_store_private_or_shared_file` and `_store_entertainment_file` functions
already handle direct download correctly. We just need to stop routing large
files away from them.

---

## Part A — backend/app/telegram_bot.py

### A1 — Remove the size-warning note in `_handle_media_message`

Find and delete this entire block (around line 258-267):
```python
    # For oversized files when NOT using local API, note the size in the prompt
    # so the user knows it will be handled via a direct upload link.
    size_note = ""
    if (pending.file_size > _TELEGRAM_FILE_DOWNLOAD_LIMIT_BYTES
            and not settings.telegram_local_api_enabled):
        size_note = (
            f"\n⚠️ This file ({_human_size(pending.file_size)}) is too large "
            "for Telegram bot download. After you choose a destination, "
            "I'll send you a direct upload link.\n"
        )
    await update.message.reply_text(size_note + _pending_upload_prompt(pending.filename))
```

Replace with just:
```python
    await update.message.reply_text(_pending_upload_prompt(pending.filename))
```

### A2 — Remove the upload-link branch in `_handle_pending_upload_choice`

Find and delete this entire block (around line 294-319):
```python
    # ── Large file without local API → generate one-time upload link ──
    if (pending.file_size > _TELEGRAM_FILE_DOWNLOAD_LIMIT_BYTES
            and not settings.telegram_local_api_enabled):
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
```

### A3 — Replace the download try/except in `_handle_pending_upload_choice`

After removing the upload-link block, update the download section.

Find:
```python
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
```

Replace with:
```python
    # ── Download file directly on SBC ──
    # If the bot is connected to the local API server (telegram_local_api_enabled=True),
    # files up to 2GB are downloaded directly. If the local API server is not enabled,
    # files over 20MB will fail here — the user is told to enable it in settings.
    size_mb = round(pending.file_size / (1024 * 1024), 1) if pending.file_size else 0
    if size_mb > 0.5:
        await update.message.reply_text(
            f"📥 Saving {pending.filename} ({size_mb} MB) to {target_label}…"
        )

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
        actual_mb = round(dest.stat().st_size / (1024 * 1024), 1)
        await update.message.reply_text(
            f"✅ Saved to {target_label}: {dest.name} ({actual_mb} MB)"
        )

    except Exception as exc:
        logger.warning(
            "telegram_upload_store_failed chat_id=%s file=%s error=%s",
            chat_id, pending.filename, exc,
        )
        if _is_too_large_telegram_file_error(exc):
            # File is too large for the cloud Bot API — local server not enabled
            await update.message.reply_text(
                f"⚠️ {pending.filename} is too large for standard bot download.\n\n"
                "Ask your admin to enable Large File mode in the AiHomeCloud app:\n"
                "More → Telegram Bot → Large file mode (up to 2 GB)"
            )
        else:
            await update.message.reply_text(
                f"⚠️ Failed to save {pending.filename}. Please try again."
            )
    return True
```

### A4 — Also fix the hardcoded IP bug from the audit (if not already fixed)

In `_handle_pending_upload_choice`, if the upload-link block was already removed
in A2, this is already gone. If for any reason it remains, replace:
```python
host = settings.host if settings.host != "0.0.0.0" else "192.168.0.212"
```
with:
```python
from .config import get_local_ip
host = get_local_ip()
```

---

## Part B — Remove the module-level constant (cleanup only)

In `telegram_bot.py`, find and delete this line near the top:
```python
_TELEGRAM_FILE_DOWNLOAD_LIMIT_BYTES = 20 * 1024 * 1024
```

It's only used by the upload-link logic being removed. If `_is_too_large_telegram_file_error`
still uses it indirectly, keep it — but check: that function only reads the exception
message string, not this constant, so it's safe to remove.

---

## Part C — scripts/setup-telegram-local-api.sh

The local API server is now the REQUIRED component for any file over 20MB.
Make the script messaging reflect this.

Find the final echo block:
```bash
echo ""
echo "==> Done. Now set these in your AiHomeCloud app:"
echo "    API ID:   ${API_ID}"
echo "    API Hash: ${API_HASH}"
echo "    Enable 'Large file uploads' toggle in Telegram Bot settings."
```

Replace with:
```bash
echo ""
echo "==> Done!"
echo ""
echo "    The local Bot API server is now running on port ${PORT}."
echo "    All files sent to your bot will be downloaded directly on this device."
echo "    No phone or browser needed — the SBC handles everything."
echo ""
echo "    Final step in the AiHomeCloud app:"
echo "    More → Telegram Bot → Large file mode → enter API ID and Hash → Save"
echo ""
echo "    API ID  : ${API_ID}"
echo "    API Hash: ${API_HASH}"
```

---

## Part D — Update _help command in telegram_bot.py

Find `_handle_help` and update the Upload section to remove the upload-link
mention:

Find:
```python
        "Upload:\n"
        "• Send a document, photo, video, or audio\n"
        "• Reply 1 for private personal, 2 for shared, 3 for entertainment\n\n"
```

Replace with:
```python
        "Upload:\n"
        "• Send any file (up to 2 GB with Large File mode)\n"
        "• Reply 1 = private, 2 = shared, 3 = entertainment\n"
        "• The device saves it directly — no other steps needed\n\n"
```

---

## Validation

```bash
# Check no syntax errors
python3 -m py_compile backend/app/telegram_bot.py && echo "OK"

# Check upload-link code is gone
grep -n "create_upload_token\|direct upload link\|open this link on your phone" \
  backend/app/telegram_bot.py && echo "FAIL — upload link code still present" \
  || echo "OK — upload link code removed"

# Check get_local_ip reference is gone (since we removed the block that had it)
grep -n "192.168.0.212" backend/app/telegram_bot.py && echo "FAIL — hardcoded IP" \
  || echo "OK"

# Backend tests
pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py
```

## Commit

```bash
git add -A
git commit -m "fix: telegram bot downloads all files on SBC — remove phone upload-link fallback"
```

---

## How it works after this fix

```
User sends 500MB video to bot
  ↓
Bot asks: 1. Private  2. Shared  3. Entertainment
  ↓
User replies: 3
  ↓
Bot: "📥 Saving video.mp4 (500 MB) to entertainment…"
  ↓
Local API server on SBC downloads from Telegram servers directly to /tmp/telegram-bot-api/
  ↓
Bot moves file to /srv/nas/shared/Entertainment/Videos/video.mp4
  ↓
Bot: "✅ Saved to entertainment: video.mp4 (500 MB)"
  ↓
TV opens minidlna → sees video.mp4 → plays
```

No phone. No browser. No link. SBC does everything after the user picks a category.

---

## One-time setup on the SBC to enable this

```bash
# Get API credentials from https://my.telegram.org → API development tools
# Takes 2 minutes, it's free

TELEGRAM_API_ID=12345 TELEGRAM_API_HASH=abcdef \
  sudo bash scripts/setup-telegram-local-api.sh

# Then in app: More → Telegram Bot → Large file mode → enter ID + Hash → Save
```

After that, every file sent to the bot — any size up to 2GB — is handled
entirely by the SBC without any other device involved.
