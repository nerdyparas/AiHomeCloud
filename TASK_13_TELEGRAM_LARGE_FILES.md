# TASK 13 — Telegram Bot: Receive and Store Files up to 2GB
# Model: claude-opus-4-6 via Aider
# Run: aider --model claude-opus-4-6 --no-auto-commit

## Context
AiHomeCloud FastAPI + Flutter home NAS running on ARM SBC (Radxa Cubie).
Telegram bot already exists in backend/app/telegram_bot.py and polls via
python-telegram-bot library. Bot token is stored in kv.json via store.get_value.
/auth command links Telegram accounts. Bot currently handles text search only.

The Telegram Bot API cloud server caps file downloads at 20MB. The fix is to
run Telegram's official Local Bot API Server on the SBC — the bot then
connects to localhost instead of api.telegram.org and the limit becomes 2GB.

## Architecture rules — never break these
- run_command() returns tuple: rc, stdout, stderr = await run_command([...])
- logger not print() in backend
- settings.nas_root / settings.shared_path / settings.personal_path — never hardcode paths
- store.get_value / store.set_value for all persistence
- All new config fields go in backend/app/config.py as Pydantic fields

---

## What this task delivers
1. Local Bot API Server setup script for the SBC (one-time install)
2. Bot code updated to connect to local server when enabled
3. File receive handler — user sends any file to bot, bot saves to NAS
4. Files land in /srv/nas/shared/Inbox/ (visible to whole family in app)
5. Supported file types auto-indexed for Telegram search after saving
6. Flutter setup screen gets api_id + api_hash fields (collapsed behind toggle)
7. Backend config + routes updated for new fields

---

## PART A — SBC setup script (one-time, run manually)

### File to create
scripts/setup-telegram-local-api.sh

### Implementation
Create this shell script. It installs and runs the Telegram Local Bot API
Server as a systemd service using Docker (simplest on ARM64).
If Docker is not available it falls back to building from source.

```bash
#!/usr/bin/env bash
# AiHomeCloud — Telegram Local Bot API Server setup
# Run once on the SBC to enable file uploads larger than 20MB.
# Requires: TELEGRAM_API_ID and TELEGRAM_API_HASH from https://my.telegram.org
#
# Usage:
#   TELEGRAM_API_ID=12345 TELEGRAM_API_HASH=abcdef ./setup-telegram-local-api.sh

set -euo pipefail

API_ID="${TELEGRAM_API_ID:-}"
API_HASH="${TELEGRAM_API_HASH:-}"
DATA_DIR="/var/lib/telegram-bot-api"
SERVICE_NAME="telegram-bot-api"
PORT=8081

if [[ -z "$API_ID" || -z "$API_HASH" ]]; then
  echo "ERROR: Set TELEGRAM_API_ID and TELEGRAM_API_HASH before running."
  echo "Get them at https://my.telegram.org → API development tools"
  exit 1
fi

echo "==> Creating data directory..."
sudo mkdir -p "$DATA_DIR"
sudo chown "$USER:$USER" "$DATA_DIR"

# ── Try Docker first (easiest on ARM64) ──────────────────────────────────────
if command -v docker &>/dev/null; then
  echo "==> Docker found — using container image..."

  sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Telegram Local Bot API Server
After=network.target docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=5
ExecStartPre=-/usr/bin/docker rm -f ${SERVICE_NAME}
ExecStart=/usr/bin/docker run --rm \\
  --name ${SERVICE_NAME} \\
  -p ${PORT}:8081 \\
  -v ${DATA_DIR}:/var/lib/telegram-bot-api \\
  -e TELEGRAM_API_ID=${API_ID} \\
  -e TELEGRAM_API_HASH=${API_HASH} \\
  aiogram/telegram-bot-api:latest \\
  --local
ExecStop=/usr/bin/docker stop ${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

else
  echo "==> Docker not found — building from source (takes ~15 min on ARM)..."
  sudo apt-get install -y cmake g++ libssl-dev zlib1g-dev gperf

  BUILD_DIR="/tmp/telegram-bot-api-build"
  rm -rf "$BUILD_DIR"
  git clone --recursive https://github.com/tdlib/telegram-bot-api.git "$BUILD_DIR"
  cd "$BUILD_DIR"
  mkdir build && cd build
  cmake -DCMAKE_BUILD_TYPE=Release ..
  cmake --build . --target telegram-bot-api -j"$(nproc)"
  sudo cp telegram-bot-api /usr/local/bin/
  cd / && rm -rf "$BUILD_DIR"

  sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Telegram Local Bot API Server
After=network.target

[Service]
User=$USER
Restart=always
RestartSec=5
ExecStart=/usr/local/bin/telegram-bot-api \\
  --api-id=${API_ID} \\
  --api-hash=${API_HASH} \\
  --http-port=${PORT} \\
  --dir=${DATA_DIR} \\
  --local
Environment=HOME=/var/lib/telegram-bot-api

[Install]
WantedBy=multi-user.target
EOF
fi

sudo systemctl daemon-reload
sudo systemctl enable --now ${SERVICE_NAME}

echo ""
echo "==> Waiting for local API server to start..."
sleep 5
if curl -s "http://127.0.0.1:${PORT}/bot<token>/getMe" | grep -q "Unauthorized"; then
  echo "✅ Local Bot API Server is running on port ${PORT}"
else
  echo "⚠️  Server may still be starting — check: systemctl status ${SERVICE_NAME}"
fi

echo ""
echo "==> Done. Now set these in your AiHomeCloud app:"
echo "    API ID:   ${API_ID}"
echo "    API Hash: ${API_HASH}"
echo "    Enable 'Large file uploads' toggle in Telegram Bot settings."
```

Make it executable:
```
chmod +x scripts/setup-telegram-local-api.sh
```

---

## PART B — Backend config changes

### File to edit
backend/app/config.py

### Implementation
Add these fields to the Settings class after the existing telegram fields:

```python
# After:
#   telegram_bot_token: str = ""
#   telegram_allowed_ids: str = ""

# Add:
telegram_api_id: int = 0          # from my.telegram.org — needed for local server
telegram_api_hash: str = ""       # from my.telegram.org — needed for local server
telegram_local_api_enabled: bool = False   # True when local server is running
telegram_local_api_url: str = "http://127.0.0.1:8081"  # local server address
```

---

## PART C — Backend routes changes

### File to edit
backend/app/routes/telegram_routes.py

### Implementation

#### Update TelegramConfigIn to include api credentials:

```python
class TelegramConfigIn(BaseModel):
    bot_token: str
    api_id: int = 0
    api_hash: str = ""
    local_api_enabled: bool = False
    # Note: allowed_ids removed — auth is done via /auth command
```

#### Update TelegramConfigOut to include new fields:

```python
class TelegramConfigOut(BaseModel):
    configured: bool
    token_preview: str
    linked_count: int
    bot_running: bool
    local_api_enabled: bool
    api_id: int                    # returned so UI can show it's configured
    max_file_mb: int               # 20 when cloud API, 2000 when local
```

#### Update get_config endpoint:

```python
@router.get("/config", response_model=TelegramConfigOut)
async def get_config(user: dict = Depends(require_admin)):
    saved: dict = await _store.get_value("telegram_config", default={})
    token = saved.get("bot_token", "") or settings.telegram_bot_token
    linked_ids = await _store.get_value("telegram_linked_ids", default=[])
    local_enabled = saved.get("local_api_enabled", False)

    return TelegramConfigOut(
        configured=bool(token),
        token_preview=_mask_token(token) if token else "",
        linked_count=len(linked_ids),
        bot_running=_bot_is_running(),
        local_api_enabled=local_enabled,
        api_id=saved.get("api_id", 0),
        max_file_mb=2000 if local_enabled else 20,
    )
```

#### Update save_config endpoint:

```python
@router.post("/config", status_code=status.HTTP_204_NO_CONTENT)
async def save_config(body: TelegramConfigIn, user: dict = Depends(require_admin)):
    token = body.bot_token.strip()
    if not token:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "bot_token must not be empty",
        )

    await _store.set_value("telegram_config", {
        "bot_token": token,
        "api_id": body.api_id,
        "api_hash": body.api_hash,
        "local_api_enabled": body.local_api_enabled,
    })

    settings.telegram_bot_token = token           # type: ignore[misc]
    settings.telegram_api_id = body.api_id        # type: ignore[misc]
    settings.telegram_api_hash = body.api_hash    # type: ignore[misc]
    settings.telegram_local_api_enabled = body.local_api_enabled  # type: ignore[misc]

    try:
        from ..telegram_bot import stop_bot, start_bot
        await stop_bot()
        await start_bot()
        logger.info("Telegram bot restarted — local_api=%s", body.local_api_enabled)
    except Exception as exc:
        logger.warning("Telegram bot restart failed: %s", exc)
```

#### Add unlink endpoint (admin use, no UI needed now):

```python
@router.delete("/linked/{chat_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unlink_account(chat_id: int, user: dict = Depends(require_admin)):
    """Remove a linked Telegram account."""
    ids = await _store.get_value("telegram_linked_ids", default=[])
    ids = [i for i in ids if int(i) != chat_id]
    await _store.set_value("telegram_linked_ids", ids)
```

---

## PART D — Bot code changes

### File to edit
backend/app/telegram_bot.py

### D1 — Add linked_ids persistence helpers at top of file

Add these functions after the module-level variables (`_last_results`, `_application`):

```python
async def _get_linked_ids() -> set[int]:
    """Return set of Telegram chat IDs that have sent /auth."""
    from .store import get_value
    ids = await get_value("telegram_linked_ids", default=[])
    return {int(i) for i in ids if str(i).lstrip("-").isdigit()}


async def _add_linked_id(chat_id: int) -> None:
    """Persistently add a chat_id after /auth."""
    from .store import get_value, set_value
    ids = await get_value("telegram_linked_ids", default=[])
    if chat_id not in ids:
        ids.append(chat_id)
        await set_value("telegram_linked_ids", ids)
```

### D2 — Replace _is_allowed with async version

Remove the old synchronous `_is_allowed` function entirely. Replace with:

```python
async def _is_allowed(chat_id: int) -> bool:
    """Return True if this chat_id has linked via /auth."""
    linked = await _get_linked_ids()
    return chat_id in linked
```

### D3 — Update all handlers to await _is_allowed

In `_handle_start`, `_handle_list`, `_handle_message` — change every:
```python
if not _is_allowed(chat_id):
```
to:
```python
if not await _is_allowed(chat_id):
```

### D4 — Add /auth handler

Add this function before start_bot():

```python
async def _handle_auth(update, context) -> None:
    chat_id = update.effective_chat.id
    first_name = update.effective_user.first_name or "there"

    if await _is_allowed(chat_id):
        await update.message.reply_text(
            f"✅ Already linked, {first_name}!\n"
            "Type anything to search files, /list for recent docs, /help for all commands."
        )
        return

    await _add_linked_id(chat_id)
    await update.message.reply_text(
        f"✅ Linked! Welcome, {first_name}.\n\n"
        "Commands:\n"
        "• Type anything — search your documents\n"
        "• /list — recent files\n"
        "• /help — all commands\n\n"
        "💡 You can also send me any file and I'll save it to your AiHomeCloud."
    )
```

### D5 — Add /help handler

```python
async def _handle_help(update, context) -> None:
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("Send /auth first to link your account.")
        return
    await update.message.reply_text(
        "🏠 AiHomeCloud Bot\n\n"
        "Search:\n"
        "• Type any word to search documents\n"
        "• Reply with a number to receive that file\n\n"
        "Files:\n"
        "• Send any file — I'll save it to Shared → Inbox\n\n"
        "Commands:\n"
        "• /list — last 10 documents\n"
        "• /help — this message\n\n"
        "Examples: aadhaar, pan, invoice, passport"
    )
```

### D6 — Update _handle_start

```python
async def _handle_start(update, context) -> None:
    chat_id = update.effective_chat.id
    first_name = update.effective_user.first_name or "there"

    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            f"👋 Hi {first_name}! This is a private AiHomeCloud.\n\n"
            "Send /auth to link your account and get access."
        )
        return

    await update.message.reply_text(
        f"👋 Welcome back, {first_name}!\n"
        "Type anything to search, or /help for all commands."
    )
```

### D7 — Add file receive handler

This is the core of Task 13. Add this function before start_bot():

```python
# Supported extensions for auto-indexing after save
_INDEXABLE_EXTENSIONS = {
    '.pdf', '.doc', '.docx', '.txt', '.md', '.csv',
    '.jpg', '.jpeg', '.png', '.heic', '.heif', '.tiff', '.tif', '.bmp',
}


async def _handle_incoming_file(update, context) -> None:  # type: ignore[type-arg]
    """Receive any file sent to the bot and save it to NAS shared inbox."""
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text("Send /auth first to link your account.")
        return

    from .config import settings

    # Extract file object — handle all Telegram file types
    msg = update.message
    if msg.document:
        tg_file_obj = msg.document
        file_name = tg_file_obj.file_name or f"file_{tg_file_obj.file_unique_id}"
    elif msg.video:
        tg_file_obj = msg.video
        file_name = msg.video.file_name or f"video_{tg_file_obj.file_unique_id}.mp4"
    elif msg.audio:
        tg_file_obj = msg.audio
        file_name = msg.audio.file_name or f"audio_{tg_file_obj.file_unique_id}.mp3"
    elif msg.photo:
        # Telegram sends multiple sizes — take the largest
        tg_file_obj = msg.photo[-1]
        file_name = f"photo_{tg_file_obj.file_unique_id}.jpg"
    elif msg.voice:
        tg_file_obj = msg.voice
        file_name = f"voice_{tg_file_obj.file_unique_id}.ogg"
    else:
        await update.message.reply_text("Unsupported file type.")
        return

    file_size_mb = round(tg_file_obj.file_size / (1024 * 1024), 1) if tg_file_obj.file_size else 0

    # Warn clearly if local API is not enabled and file exceeds cloud limit
    if not settings.telegram_local_api_enabled and file_size_mb > 19:
        await update.message.reply_text(
            f"⚠️ {file_name} is {file_size_mb} MB.\n"
            "The standard bot limit is 20 MB.\n"
            "Ask your admin to enable Large File mode in Telegram Bot settings."
        )
        return

    await update.message.reply_text(
        f"📥 Receiving {file_name} ({file_size_mb} MB)…"
    )

    try:
        # Destination: shared Inbox folder — visible to all family members in app
        dest_dir = settings.shared_path / "Inbox"
        dest_dir.mkdir(parents=True, exist_ok=True)

        # Sanitize filename — strip path components
        from pathlib import Path as _Path
        safe_name = _Path(file_name).name
        if not safe_name or safe_name in (".", ".."):
            safe_name = f"file_{tg_file_obj.file_unique_id}"

        dest_path = dest_dir / safe_name

        # Handle filename collision — append _1, _2 etc.
        counter = 1
        while dest_path.exists():
            stem = _Path(safe_name).stem
            suffix = _Path(safe_name).suffix
            dest_path = dest_dir / f"{stem}_{counter}{suffix}"
            counter += 1

        # Download — when local API is enabled this writes directly to disk
        # without loading the whole file into Python memory
        tg_file = await context.bot.get_file(tg_file_obj.file_id)
        await tg_file.download_to_drive(str(dest_path))

        actual_mb = round(dest_path.stat().st_size / (1024 * 1024), 1)

        await update.message.reply_text(
            f"✅ Saved! ({actual_mb} MB)\n"
            f"📁 Shared → Inbox → {dest_path.name}"
        )

        # Auto-index if it's a searchable document type
        if dest_path.suffix.lower() in _INDEXABLE_EXTENSIONS:
            try:
                from .document_index import index_document
                asyncio.create_task(
                    index_document(str(dest_path), dest_path.name, "telegram")
                )
                logger.info("Queued indexing for telegram upload: %s", dest_path.name)
            except Exception as idx_err:
                logger.warning("Index task failed for %s: %s", dest_path.name, idx_err)

    except Exception as exc:
        logger.error("Telegram file save failed file=%s error=%s", file_name, exc)
        await update.message.reply_text(
            f"❌ Could not save {file_name}.\n"
            f"Error: {str(exc)[:120]}"
        )
```

### D8 — Update start_bot() to use local API when configured and register new handlers

Replace the `ApplicationBuilder` block in `start_bot()`:

```python
async def start_bot() -> None:
    global _application
    from .config import settings

    if not settings.telegram_bot_token:
        logger.info("Telegram bot token not set — bot disabled")
        return

    try:
        from telegram.ext import (
            ApplicationBuilder, CommandHandler, MessageHandler, filters
        )
    except ImportError:
        logger.warning("python-telegram-bot not installed — Telegram bot disabled")
        return

    try:
        builder = ApplicationBuilder().token(settings.telegram_bot_token)

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

        # Command handlers
        _application.add_handler(CommandHandler("start", _handle_start))
        _application.add_handler(CommandHandler("auth", _handle_auth))
        _application.add_handler(CommandHandler("help", _handle_help))
        _application.add_handler(CommandHandler("list", _handle_list))

        # File receive handler — catches all file types
        _application.add_handler(
            MessageHandler(
                filters.Document.ALL
                | filters.VIDEO
                | filters.AUDIO
                | filters.PHOTO
                | filters.VOICE,
                _handle_incoming_file,
            )
        )

        # Text search handler — must be last (catches everything else)
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
```

---

## PART E — Flutter setup screen changes

### File to edit
lib/screens/main/telegram_setup_screen.dart

### E1 — Add new state variables

In `_TelegramSetupScreenState`, add:

```dart
bool _localApiEnabled = false;
int _linkedCount = 0;
int _maxFileMb = 20;
int _apiId = 0;
final _apiIdCtrl = TextEditingController();
final _apiHashCtrl = TextEditingController();
bool _obscureApiHash = true;
```

Remove: `_idsCtrl` and anything referencing `allowed_ids`.

### E2 — Update dispose()

```dart
@override
void dispose() {
  _tokenCtrl.dispose();
  _apiIdCtrl.dispose();
  _apiHashCtrl.dispose();
  super.dispose();
}
```

### E3 — Update _loadConfig()

```dart
Future<void> _loadConfig() async {
  setState(() { _loading = true; _errorMsg = null; });
  try {
    final cfg = await ref.read(apiServiceProvider).getTelegramConfig();
    if (mounted) {
      setState(() {
        _configured = cfg['configured'] as bool? ?? false;
        _botRunning = cfg['bot_running'] as bool? ?? false;
        _localApiEnabled = cfg['local_api_enabled'] as bool? ?? false;
        _linkedCount = cfg['linked_count'] as int? ?? 0;
        _maxFileMb = cfg['max_file_mb'] as int? ?? 20;
        _apiId = cfg['api_id'] as int? ?? 0;
        if (_apiId > 0) _apiIdCtrl.text = _apiId.toString();
        _loading = false;
      });
    }
  } catch (e) {
    if (mounted) setState(() { _errorMsg = friendlyError(e); _loading = false; });
  }
}
```

### E4 — Update _save()

```dart
Future<void> _save() async {
  final token = _tokenCtrl.text.trim();
  if (token.isEmpty && !_configured) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bot Token is required.')));
    return;
  }

  final apiId = int.tryParse(_apiIdCtrl.text.trim()) ?? 0;
  final apiHash = _apiHashCtrl.text.trim();

  if (_localApiEnabled && (apiId == 0 || apiHash.isEmpty)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API ID and API Hash are required for large file mode.')));
    return;
  }

  setState(() { _saving = true; _errorMsg = null; });

  try {
    await ref.read(apiServiceProvider).saveTelegramConfig(
      token.isNotEmpty ? token : '',
      apiId: apiId,
      apiHash: apiHash,
      localApiEnabled: _localApiEnabled,
    );
    if (mounted) {
      _tokenCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telegram Bot configured!')));
      await _loadConfig();
    }
  } catch (e) {
    if (mounted) setState(() { _errorMsg = friendlyError(e); _saving = false; });
  }
}
```

### E5 — Replace build() body content

Keep the Scaffold and AppBar unchanged. Replace the ListView children with:

```dart
// Status card — unchanged, keep existing _StatusCard widget

// Instructions card
AppCard(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Setup in 3 steps', style: GoogleFonts.sora(
          color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      _stepText('1', 'Open Telegram → search @BotFather'),
      _stepText('2', 'Send /newbot and copy the token'),
      _stepText('3', 'Paste below, tap Save, then send /auth to your bot'),
    ],
  ),
),
const SizedBox(height: 24),

// Token input — keep existing TextField unchanged

const SizedBox(height: 24),

// Linked accounts status
if (_configured) ...[
  AppCard(
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (_linkedCount > 0 ? AppColors.success : AppColors.textMuted)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.people_rounded,
              color: _linkedCount > 0 ? AppColors.success : AppColors.textMuted,
              size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _linkedCount == 0
                    ? 'No accounts linked yet'
                    : '$_linkedCount account${_linkedCount == 1 ? '' : 's'} linked',
                style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (_linkedCount == 0)
                Text('Open your bot and send /auth',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  ),
  const SizedBox(height: 24),
],

// File limit info card
AppCard(
  child: Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.upload_file_rounded,
            color: AppColors.primary, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File upload limit: $_maxFileMb MB',
                style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
              _localApiEnabled
                  ? 'Large file mode active — up to 2 GB'
                  : 'Enable large file mode below to upload up to 2 GB',
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    ],
  ),
),
const SizedBox(height: 16),

// Large file mode toggle + api_id/api_hash fields
AppCard(
  child: Column(
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _localApiEnabled,
        onChanged: (v) => setState(() => _localApiEnabled = v),
        activeColor: AppColors.primary,
        title: Text('Large file mode (up to 2 GB)',
            style: GoogleFonts.dmSans(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        subtitle: Text(
          'Requires Telegram API credentials and the local server '
          'setup script to be run on your AiHomeCloud device.',
          style: GoogleFonts.dmSans(
              color: AppColors.textSecondary, fontSize: 12)),
      ),
      if (_localApiEnabled) ...[
        const Divider(color: AppColors.cardBorder, height: 24),
        Text('Get API ID and Hash at my.telegram.org → API development tools',
            style: GoogleFonts.dmSans(
                color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 12),
        // API ID field
        TextField(
          controller: _apiIdCtrl,
          keyboardType: TextInputType.number,
          style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'API ID',
            labelStyle: GoogleFonts.dmSans(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cardBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cardBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),
        // API Hash field
        TextField(
          controller: _apiHashCtrl,
          obscureText: _obscureApiHash,
          style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'API Hash',
            labelStyle: GoogleFonts.dmSans(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cardBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.cardBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            suffixIcon: IconButton(
              icon: Icon(_obscureApiHash
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
                  color: AppColors.textMuted, size: 18),
              onPressed: () => setState(() => _obscureApiHash = !_obscureApiHash),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '⚠️ Run scripts/setup-telegram-local-api.sh on your AiHomeCloud '
          'device before enabling this.',
          style: GoogleFonts.dmSans(
              color: AppColors.primary, fontSize: 11),
        ),
      ],
    ],
  ),
),

const SizedBox(height: 24),
// Save button — keep existing FilledButton unchanged
```

### E6 — Update saveTelegramConfig API call signature

In lib/services/api/services_network_api.dart, update the method:

```dart
/// POST /api/v1/telegram/config
Future<void> saveTelegramConfig(
  String botToken, {
  int apiId = 0,
  String apiHash = '',
  bool localApiEnabled = false,
}) async {
  final body = <String, dynamic>{
    'local_api_enabled': localApiEnabled,
  };
  if (botToken.isNotEmpty) body['bot_token'] = botToken;
  if (apiId > 0) body['api_id'] = apiId;
  if (apiHash.isNotEmpty) body['api_hash'] = apiHash;

  final res = await _withAutoRefresh(
    () => _client
        .post(
          Uri.parse('$_baseUrl${AppConstants.apiVersion}/telegram/config'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(ApiService._timeout),
  );
  _check(res);
}
```

---

## Validation — run all in order

```bash
# Backend
pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py

# Flutter
flutter analyze lib/screens/main/telegram_setup_screen.dart
flutter analyze lib/services/api/services_network_api.dart
flutter analyze

# Build
flutter build apk --debug
```

## Commit when all pass

```bash
git add -A
git commit -m "feat: telegram receive files up to 2GB via local bot API, /auth auto-link, simplified setup"
```

## Manual test on device

```
1. Open Telegram → your bot → send /auth
2. Bot replies: "✅ Linked! Welcome..."
3. Send any file under 20MB to the bot
4. Bot replies: "✅ Saved! Shared → Inbox → filename"
5. Open AiHomeCloud app → Files → Shared → Inbox → file appears
```

## To enable 2GB mode after this task is complete

```bash
# On the SBC via SSH:
TELEGRAM_API_ID=12345 TELEGRAM_API_HASH=abcdef \
  bash /opt/aihomecloud/scripts/setup-telegram-local-api.sh

# Then in the app:
# More → Telegram Bot → enable "Large file mode" toggle → enter api_id + api_hash → Save
```
