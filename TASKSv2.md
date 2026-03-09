# AiHomeCloud — Task Tracker v2

> **Source of truth for all tasks.** Follows MASTER_PROMPT.md phases and priorities.
> Statuses: `⬜ todo` · `🔄 in-progress` · `✅ done` · `⏸ blocked`
> Last updated: 2025-03-10

---

## What's Already Done (Milestones 1–8 from v1)

All of these are ✅ complete and preserved on the `v1` branch:

- **M1** — Core backend (FastAPI + 10 route files) + Flutter app (Riverpod, GoRouter, theme, onboarding, main screens)
- **M2** — External storage management (scan/format/mount/unmount/eject + Flutter UI)
- **M3** — Polish (mDNS, BLE, QR pairing, file preview, download, multi-upload, TLS, permissions, notifications, l10n)
- **M4** — Security foundations (JWT secret auto-gen, asyncio.Lock store, subprocess isolation, API versioning, CORS hardening, systemd hardening)
- **M5** — Reliability (structured logging, 1s read cache, AuthSessionNotifier, connection state machine, pagination, job tracking, deploy script, bcrypt executor)
- **M6** — Auth hardening (refresh tokens + revocation, OTP persistence, TLS cert pinning)
- **M7** — Testing (47 backend tests, 30 Flutter tests, CI pipelines) — *Flutter unit tests 7F.1–7F.7 still todo*
- **M8** — Board abstraction (auto-detect thermal zone, LAN interface, SBC model)

---

## Phase 1 — Security (BLOCKING — before any external testing)

> These MUST be done first. See MASTER_PROMPT.md "Security — Fix In Order".

---

### TASK-P1-01 — JWT Expiry: 720h → 1h
**Priority:** 🔴 Critical
**Status:** ⬜ todo
**Phase:** Phase 1 — Security
**Files:** `backend/app/config.py`
**Depends on:** none

**Goal:**
Change `jwt_expire_hours` from 720 (30 days) to 1 (1 hour). The auto-refresh interceptor in `api_service.dart` is already wired — this just activates short-lived access tokens.

**Acceptance criteria:**
- [ ] `jwt_expire_hours: int = 1` in config.py
- [ ] Backend tests pass: `cd backend && python -m pytest tests/ -q`

**Notes:**
Flutter `_withAutoRefresh()` and `/auth/refresh` endpoint already exist from M6. This is a one-line change that dramatically improves security.

---

### TASK-P1-02 — Rate Limiting on Auth Endpoints
**Priority:** 🔴 Critical
**Status:** ⬜ todo
**Phase:** Phase 1 — Security
**Files:** `backend/requirements.txt`, `backend/app/main.py`, `backend/app/routes/auth_routes.py`
**Depends on:** none

**Goal:**
Add `slowapi` rate limiting to prevent brute-force attacks on pairing and login endpoints. Add account lockout after repeated failures.

**Acceptance criteria:**
- [ ] `slowapi==0.1.9` added to requirements.txt
- [ ] Limiter configured in main.py
- [ ] `@limiter.limit("5/minute")` on `POST /pair/complete`
- [ ] `@limiter.limit("10/minute")` on `POST /auth/login`
- [ ] Account lockout after 10 failures → 15-minute cooldown
- [ ] Backend tests pass

**Notes:**
slowapi uses starlette's Request object. Store failed attempt counter in memory dict keyed by IP.

---

### TASK-P1-03 — Block Executable Uploads
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** Phase 1 — Security
**Files:** `backend/app/routes/file_routes.py`
**Depends on:** none

**Goal:**
Reject uploads of dangerous executable file types with HTTP 415 before the file is written to disk.

**Acceptance criteria:**
- [ ] `BLOCKED_EXTENSIONS` set defined: `.sh, .bash, .zsh, .py, .rb, .pl, .php, .elf, .bin, .exe, .apk, .so, .ko, .deb, .rpm`
- [ ] Upload endpoint checks file extension against blocklist
- [ ] Returns 415 Unsupported Media Type with friendly message
- [ ] Test added to `backend/tests/test_file_routes.py`
- [ ] Backend tests pass

**Notes:**
Check must happen before writing any bytes. Case-insensitive extension matching.

---

### TASK-P1-04 — Remove Pairing Key from /pair/qr JSON
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** Phase 1 — Security
**Files:** `backend/app/routes/auth_routes.py`
**Depends on:** none

**Goal:**
The `GET /api/v1/pair/qr` endpoint currently returns the pairing key both inside the QR image AND as a `"key"` field in the JSON response body. Remove the key from the JSON — it should only be embedded in the QR payload string.

**Acceptance criteria:**
- [ ] `"key"` field removed from `/pair/qr` JSON response
- [ ] QR image still contains the key in its encoded payload
- [ ] Flutter QR scanner still works (it reads from QR, not JSON)
- [ ] Backend tests pass

**Notes:**
Check `auth_routes.py` around the `/pair/qr` handler. The Flutter app reads the key from the scanned QR content, not from the JSON response.

---

### TASK-P1-05 — Plaintext PIN Migration on Startup
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** Phase 1 — Security
**Files:** `backend/app/main.py`, `backend/app/auth.py`, `backend/app/store.py`
**Depends on:** none

**Goal:**
Add a one-time migration at backend startup: scan all users in `users.json`, detect plaintext PINs (not starting with `$2b$`), hash them using `hash_password()`, and save back. Ensures no plaintext PINs remain from early development.

**Acceptance criteria:**
- [ ] Migration function `migrate_plaintext_pins()` created
- [ ] Called from `main.py` lifespan at startup
- [ ] Detects plaintext vs bcrypt-hashed PINs
- [ ] Hashes any plaintext PINs and saves users
- [ ] Logs how many PINs were migrated
- [ ] Test added: create user with plaintext PIN, run migration, verify hashed
- [ ] Backend tests pass

**Notes:**
bcrypt hashes always start with `$2b$`. Safe to check prefix. Use `hmac.compare_digest()` for PIN comparison everywhere (already done in M5).

---

### TASK-P1-06 — Firmware Update Stub + Hide UI
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** Phase 1 — Security
**Files:** `backend/app/routes/system_routes.py`, `lib/screens/main/settings_screen.dart`
**Depends on:** none

**Goal:**
The firmware update endpoint should always return `update_available: false` until a real OTA system is built. Hide the firmware update UI section in Flutter entirely.

**Acceptance criteria:**
- [ ] `/api/v1/system/info` returns `updateAvailable: false` always
- [ ] Flutter settings screen hides/removes firmware update section
- [ ] `flutter analyze` passes
- [ ] Backend tests pass

**Notes:**
Prevents users from seeing a non-functional "Update" button.

---

## Phase 2 — Core New Features

> Backend infrastructure for auto-sort, document search, Telegram bot, and AdGuard.

---

### TASK-P2-01 — InboxWatcher File Auto-Sorter
**Priority:** 🔴 Critical
**Status:** ⬜ todo
**Phase:** Phase 2 — Core New Features
**Files:** `backend/app/file_sorter.py` (new), `backend/app/main.py`, `backend/app/routes/file_routes.py`
**Depends on:** none

**Goal:**
Create `file_sorter.py` with an `InboxWatcher` class that polls `.inbox/` directories every 30 seconds and auto-sorts files into Photos/Videos/Documents/Others based on extension. Document-like photos (small JPGs with keywords like "aadhaar", "pan") go to Documents/.

**Acceptance criteria:**
- [ ] `file_sorter.py` created with `InboxWatcher` class
- [ ] SORT_RULES dict maps extensions to folder names per MASTER_PROMPT.md
- [ ] DOC_KEYWORDS set for document photo detection (size < 800KB OR keyword in filename)
- [ ] Files must be 5+ seconds old (mtime) before moving — prevents mid-upload move
- [ ] Duplicate filename → rename to `file_2.jpg`, never overwrite
- [ ] Sort failure → file stays in .inbox/, log warning, watcher continues
- [ ] Watcher polls every 30 seconds
- [ ] After sorting to Documents/ → trigger `index_document()` (once TASK-P2-02 exists)
- [ ] On new user created → pre-create all 5 folders including .inbox/
- [ ] InboxWatcher started/stopped in `main.py` lifespan
- [ ] Upload endpoint in `file_routes.py` forces upload path to `.inbox/`
- [ ] Test added to `backend/tests/test_file_sorter.py`
- [ ] Backend tests pass

**Notes:**
Watch both `personal/{username}/.inbox/` and `shared/.inbox/`. Use `asyncio.sleep(30)` loop, not filesystem events (low CPU on ARM). Never use `settings.nas_root` hardcoded — always read from config.

---

### TASK-P2-02 — Document Search with SQLite FTS5
**Priority:** 🔴 Critical
**Status:** ⬜ todo
**Phase:** Phase 2 — Core New Features
**Files:** `backend/app/document_index.py` (new), `backend/app/routes/file_routes.py`
**Depends on:** none

**Goal:**
Create `document_index.py` with SQLite FTS5 for full-text search of documents. OCR support for PDFs and images. Database at `settings.data_dir / "docs.db"`.

**Acceptance criteria:**
- [ ] `document_index.py` created with FTS5 virtual table
- [ ] Schema: `doc_index(path, filename, ocr_text, added_by, added_at)`
- [ ] `index_document(path, filename, added_by)` — async, handles OCR
- [ ] `search_documents(query, limit=5)` — returns list of dicts
- [ ] `remove_document(path)` — removes from index
- [ ] OCR strategy: `.pdf` → `pdftotext`, `.jpg/.png/.heic` → `tesseract eng+hin`, `.txt/.md` → read file, else → empty string
- [ ] If tesseract/pdftotext missing → log warning, store empty string, never fail
- [ ] Search scope: admin → all Documents + shared/Documents; member → own + shared only
- [ ] Wire into file_routes.py: after upload to Documents/, `asyncio.create_task(index_document(...))`
- [ ] Add search endpoint `GET /api/v1/files/search?q=...`
- [ ] Test added to `backend/tests/test_document_index.py`
- [ ] Backend tests pass

**Notes:**
OCR is enhancement, not requirement. If binary missing, degrade gracefully. One index, two consumers (API + Telegram bot).

---

### TASK-P2-03 — Telegram Bot Handler
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 2 — Core New Features
**Files:** `backend/app/telegram_bot.py` (new), `backend/app/config.py`, `backend/app/main.py`, `backend/requirements.txt`
**Depends on:** TASK-P2-02

**Goal:**
Create `telegram_bot.py` for document retrieval via Telegram. Bot only starts if `telegram_bot_token` is configured. Uses the same FTS5 index as the API search.

**Acceptance criteria:**
- [ ] `python-telegram-bot==21.3` added to requirements.txt
- [ ] `telegram_bot_token: str = ""` added to config.py (CUBIE_TELEGRAM_BOT_TOKEN)
- [ ] `telegram_allowed_ids: str = ""` added to config.py (CUBIE_TELEGRAM_ALLOWED_IDS)
- [ ] `telegram_bot.py` created with `start_bot()` / `stop_bot()` functions
- [ ] Commands: `/start` (welcome), `/list` (last 10 docs), plain text (search)
- [ ] 0 results → friendly message; 1 result → send file; 2-5 → numbered list
- [ ] Number reply → send corresponding file from last search
- [ ] Security: only respond to allowed chat IDs (if configured)
- [ ] Unauthorized users get "Sorry, this is a private AiHomeCloud."
- [ ] Wired into main.py lifespan (start on startup if token set, stop on shutdown)
- [ ] Backend tests pass

**Notes:**
Bot is optional — if no token configured, skip entirely. Uses `search_documents()` from document_index.py.

---

### TASK-P2-04 — AdGuard Home Proxy Routes
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 2 — Core New Features
**Files:** `backend/app/routes/adguard_routes.py` (new), `backend/app/config.py`, `backend/app/main.py`
**Depends on:** none

**Goal:**
Create proxy routes that wrap AdGuard Home's admin API with authentication. Never expose AdGuard's port 3000 directly.

**Acceptance criteria:**
- [ ] `adguard_enabled: bool = False` added to config.py (CUBIE_ADGUARD_ENABLED)
- [ ] `adguard_password: str = ""` added to config.py (CUBIE_ADGUARD_PASSWORD)
- [ ] `adguard_routes.py` created with 3 endpoints:
  - `GET /api/v1/adguard/stats` → proxy to AdGuard `/control/stats` (any authenticated user)
  - `POST /api/v1/adguard/pause` → body `{minutes: 5|30|60}` (any authenticated user)
  - `POST /api/v1/adguard/toggle` → body `{enabled: bool}` (admin only)
- [ ] Returns `{dns_queries, blocked_today, blocked_percent, top_blocked[]}`
- [ ] Router registered in main.py
- [ ] If `adguard_enabled` is false, endpoints return 503
- [ ] Test added to `backend/tests/test_endpoints.py`
- [ ] Backend tests pass

**Notes:**
AdGuard API base: `http://localhost:3000/control/`. Use `httpx` async client for proxying.

---

### TASK-P2-05 — Android Share Target
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 2 — Core New Features
**Files:** `lib/services/share_handler.dart` (new), `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`, `lib/main.dart`
**Depends on:** none

**Goal:**
Allow users to share files from other Android apps (Gallery, WhatsApp, etc.) directly to AiHomeCloud. Received files upload to user's `.inbox/` for auto-sorting.

**Acceptance criteria:**
- [ ] `receive_sharing_intent: ^1.8.0` added to pubspec.yaml
- [ ] `share_handler.dart` created — listens for incoming share intents
- [ ] Shared files uploaded to user's `.inbox/` via existing upload endpoint
- [ ] Shows upload progress toast/dialog
- [ ] Handles multiple files in one share
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes

**Notes:**
Intent filter in AndroidManifest.xml for `android.intent.action.SEND` and `SEND_MULTIPLE`.

---

### TASK-P2-06 — First Boot Setup Script
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 2 — Core New Features
**Files:** `scripts/first-boot-setup.sh` (new)
**Depends on:** none

**Goal:**
Create a bash script that sets up a fresh Cubie from scratch: installs deps, creates venv, configures systemd, creates directories.

**Acceptance criteria:**
- [ ] `scripts/first-boot-setup.sh` created
- [ ] Installs Python 3.12+, pip, venv
- [ ] Creates `/var/lib/cubie/` data directory
- [ ] Creates `/srv/nas/` mount point
- [ ] Sets up Python venv at `/opt/cubie/venv`
- [ ] Installs requirements.txt into venv
- [ ] Copies systemd service file and enables it
- [ ] Script is idempotent (safe to run multiple times)
- [ ] Script is executable (`chmod +x`)

**Notes:**
See `kb/setup-instructions.md` for the manual steps this should automate. Target Ubuntu 24 ARM64.

---

### TASK-P2-07 — AdGuard Install Script
**Priority:** 🟢 Low
**Status:** ⬜ todo
**Phase:** Phase 2 — Core New Features
**Files:** `scripts/install-adguard.sh` (new)
**Depends on:** none

**Goal:**
Create a bash script that installs AdGuard Home on the Cubie and configures it for DNS port 5353 (non-privileged).

**Acceptance criteria:**
- [ ] `scripts/install-adguard.sh` created
- [ ] Downloads and installs AdGuard Home
- [ ] Configures DNS to port 5353
- [ ] Creates systemd service for AdGuard
- [ ] Prints instructions for router DNS configuration
- [ ] Script is executable

**Notes:**
Users need to manually point their router's DHCP DNS to the Cubie's LAN IP.

---

## Phase 3 — Upload UX Fix

> Fix upload progress, error handling, and retry behavior.

---

### TASK-P3-01 — Streamed Upload with Real Progress
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** Phase 3 — Upload UX Fix
**Files:** `lib/services/api_service.dart`, `lib/screens/main/my_folder_screen.dart`
**Depends on:** none

**Goal:**
Replace `MultipartRequest` with `StreamedRequest` for real upload progress reporting. Currently upload progress is faked.

**Acceptance criteria:**
- [ ] Upload uses `StreamedRequest` with `onProgress` callback
- [ ] Upload card shows real percentage progress
- [ ] Dismiss/cancel button on upload progress card
- [ ] `flutter analyze` passes

**Notes:**
Dart's `http.StreamedRequest` allows reading bytes sent for progress tracking.

---

### TASK-P3-02 — Error Handling on Upload & FutureProviders
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** Phase 3 — Upload UX Fix
**Files:** `lib/screens/main/my_folder_screen.dart`, `lib/screens/main/shared_folder_screen.dart`, `lib/screens/main/dashboard_screen.dart`
**Depends on:** none

**Goal:**
Add try/catch on all dialog actions (rename, delete, create folder). Add error/retry states on all FutureProviders. Never show raw exceptions.

**Acceptance criteria:**
- [ ] All dialog action callbacks wrapped in try/catch with `friendlyError(e)`
- [ ] Upload failures show retry button, not silent failure
- [ ] FutureProviders show error state with retry button (not just spinner forever)
- [ ] `flutter analyze` passes

**Notes:**
Pattern: `.when(error: (e, _) => ErrWidget(friendlyError(e), onRetry: () => ref.invalidate(provider)))`.

---

## Phase 4 — UI Language & Structure

> 4-tab navigation, vocabulary cleanup, screen merges.

---

### TASK-P4-01 — Restructure to 4 Tabs
**Priority:** 🔴 Critical
**Status:** ⬜ todo
**Phase:** Phase 4 — UI Language & Structure
**Files:** `lib/navigation/main_shell.dart`, `lib/navigation/app_router.dart`, `lib/screens/main/files_screen.dart` (new), `lib/screens/main/more_screen.dart` (new)
**Depends on:** none

**Goal:**
Change from 5 tabs (Home, MyFiles, Family, Shared, Settings) to 4 tabs (Home, Files, Family, More) per MASTER_PROMPT.md.

**Acceptance criteria:**
- [ ] Bottom nav has exactly 4 tabs: 🏠 Home | 📁 Files | 👨‍👩‍👧 Family | ⚙️ More
- [ ] "Files" tab combines My Files + Shared with segment control: [My Files] [Shared] [Videos]
- [ ] "More" tab created with sections:
  - 🤖 Telegram Bot → setup sub-page
  - 📺 TV Streaming → toggle (label: "Smart TV Streaming", never "DLNA")
  - 🛡️ Ad Blocking → stats + pause buttons + toggle (admin only)
  - 🔒 Change my PIN
  - 💾 Storage Drive → sub-page
  - 📶 Network → sub-page
  - About AiHomeCloud
  - Shut down (danger zone, bottom)
  - Log Out (bottom)
- [ ] GoRouter routes updated
- [ ] Old MyFolder/SharedFolder/Settings screens either merged or removed
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes

**Notes:**
"Videos" segment on Files tab goes directly to `/shared/Videos/`. Storage Explorer becomes sub-page under More. Settings screen items move to More tab.

---

### TASK-P4-02 — Vocabulary Replacements Throughout UI
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** Phase 4 — UI Language & Structure
**Files:** `lib/l10n/app_en.arb`, `lib/screens/**`, `lib/widgets/**`
**Depends on:** TASK-P4-01

**Goal:**
Replace all technical jargon with user-friendly labels per MASTER_PROMPT.md language rules.

**Acceptance criteria:**
- [ ] "CubieCloud" → "AiHomeCloud" everywhere (if any remain)
- [ ] "Samba" → "TV & Computer Sharing"
- [ ] "DLNA" → "Smart TV Streaming"
- [ ] "NFS" → "Network Sharing"
- [ ] "SSH" → "Remote Access (Advanced)"
- [ ] "Services" page title → "Sharing & Streaming"
- [ ] "Format as ext4" → "Prepare drive for use"
- [ ] "Mount" → "Activate"
- [ ] "Unmount" → "Safely Remove"
- [ ] "AdGuard Home" → "Ad Blocking"
- [ ] No raw paths, tokens, DNS, FTS5, SQLite, or OCR terms shown to users
- [ ] ARB strings updated
- [ ] `flutter analyze` passes

**Notes:**
See MASTER_PROMPT.md "Language Rules" table for the complete mapping.

---

### TASK-P4-03 — Home Tab Document Search Bar
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** Phase 4 — UI Language & Structure
**Files:** `lib/screens/main/dashboard_screen.dart`, `lib/services/api_service.dart`, `lib/providers.dart`
**Depends on:** TASK-P2-02

**Goal:**
Add an always-visible document search bar on the Home tab that searches the FTS5 index. Results show on first keypress with debounce.

**Acceptance criteria:**
- [ ] Search bar at top of Home tab, always visible
- [ ] Calls `GET /api/v1/files/search?q=...` with 300ms debounce
- [ ] Results show as a list with filename, who added it, date
- [ ] Tap result → navigate to file preview
- [ ] Empty state: "No documents found for '{query}'"
- [ ] `flutter analyze` passes

**Notes:**
Use a `TextEditingController` with debounce timer. Provider for search results.

---

### TASK-P4-04 — Home Tab Ad Blocking Stats Widget
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 4 — UI Language & Structure
**Files:** `lib/screens/main/dashboard_screen.dart`, `lib/services/api_service.dart`, `lib/providers.dart`
**Depends on:** TASK-P2-04

**Goal:**
Show compact ad blocking stats row on Home tab: "🛡️ 1,247 ads blocked today". Only visible if AdGuard is enabled.

**Acceptance criteria:**
- [ ] Compact row showing blocked count
- [ ] Only shown if `/api/v1/adguard/stats` returns data
- [ ] Gracefully hidden if AdGuard not enabled (no error shown)
- [ ] `flutter analyze` passes

**Notes:**
Use a FutureProvider with error suppression — if AdGuard isn't running, just hide the widget.

---

### TASK-P4-05 — More Tab: AdGuard Section
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 4 — UI Language & Structure
**Files:** `lib/screens/main/more_screen.dart`
**Depends on:** TASK-P2-04, TASK-P4-01

**Goal:**
Add Ad Blocking section in More tab: toggle (admin only), stats, and pause buttons.

**Acceptance criteria:**
- [ ] Toggle: On/Off (admin only, uses `POST /api/v1/adguard/toggle`)
- [ ] Stat: "X ads blocked today"
- [ ] Button: "Pause for 5 min" (any user)
- [ ] Button: "Pause for 1 hour" (any user)
- [ ] `flutter analyze` passes

**Notes:**
Pause is useful for banking apps that break with ad blocking.

---

### TASK-P4-06 — More Tab: Telegram Bot Setup
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 4 — UI Language & Structure
**Files:** `lib/screens/main/more_screen.dart` or `lib/screens/main/telegram_setup_screen.dart` (new)
**Depends on:** TASK-P2-03, TASK-P4-01

**Goal:**
Add Telegram Bot setup sub-page accessible from More tab. Admin can enter bot token and allowed chat IDs.

**Acceptance criteria:**
- [ ] Telegram Bot row in More tab → navigates to setup page
- [ ] Setup page has: Bot Token input, Allowed Chat IDs input
- [ ] Save sends config to backend (new endpoint or existing config route)
- [ ] Shows bot status (connected/disconnected)
- [ ] Admin only
- [ ] `flutter analyze` passes

**Notes:**
Consider adding a backend endpoint to save/load telegram config, or use the existing settings mechanism.

---

## Phase 5 — Soft Delete / Trash

> Recoverable file deletion with trash folder.

---

### TASK-P5-01 — Backend Trash Infrastructure
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 5 — Soft Delete / Trash
**Files:** `backend/app/config.py`, `backend/app/models.py`, `backend/app/routes/file_routes.py`
**Depends on:** none

**Goal:**
Replace hard delete with soft delete (move to trash). Add trash listing, restore, and permanent delete endpoints.

**Acceptance criteria:**
- [ ] `trash_dir` property in config.py: `{nas_root}/.cubie_trash/`
- [ ] `TrashItem` Pydantic model: `id`, `original_path`, `deleted_at`, `size_bytes`, `deleted_by`
- [ ] File delete → move to `trash_dir/{user_id}/{timestamp}_{filename}` instead of `os.remove()`
- [ ] `GET /api/v1/files/trash` — list caller's trash items
- [ ] `POST /api/v1/files/trash/{id}/restore` — move back to original path
- [ ] `DELETE /api/v1/files/trash/{id}` — permanent delete
- [ ] Trash quota guard: if trash > 10% of NAS capacity, auto-purge oldest
- [ ] Test added
- [ ] Backend tests pass

**Notes:**
Store trash metadata in `trash.json` via store.py pattern. Keep trash items for 30 days max.

---

### TASK-P5-02 — Flutter Trash UI
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 5 — Soft Delete / Trash
**Files:** `lib/screens/main/my_folder_screen.dart`, `lib/screens/main/more_screen.dart`, `lib/services/api_service.dart`
**Depends on:** TASK-P5-01, TASK-P4-01

**Goal:**
Add swipe-to-delete with undo SnackBar, and "Empty Trash" button in More tab.

**Acceptance criteria:**
- [ ] Swipe-to-delete on file tiles shows Undo SnackBar (30s window)
- [ ] After 30s without undo, file moves to trash
- [ ] "Empty Trash" button in More tab with confirmation dialog
- [ ] Shows trash size ("Trash: 2.3 GB")
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes

**Notes:**
Use `Dismissible` widget with `SnackBarAction` for undo.

---

## Phase 6 — Deployment Readiness

> Final hardening, scripts, and documentation for production deployment.

---

### TASK-P6-01 — DLNA + AdGuard Service Registration
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 6 — Deployment Readiness
**Files:** `backend/app/routes/service_routes.py`
**Depends on:** none

**Goal:**
Add `dlna` (minidlna) and `adguard` (AdGuardHome) to `_SERVICE_UNITS` mapping so they can be started/stopped via the existing service management API.

**Acceptance criteria:**
- [ ] `"dlna": ["minidlna"]` added to `_SERVICE_UNITS`
- [ ] `"adguard": ["AdGuardHome"]` added to `_SERVICE_UNITS`
- [ ] Backend tests pass

**Notes:**
These are systemd unit names. The existing service start/stop infrastructure handles the rest.

---

### TASK-P6-02 — ARM64 pip-compile for Requirements
**Priority:** 🟢 Low
**Status:** ⬜ todo
**Phase:** Phase 6 — Deployment Readiness
**Files:** `backend/requirements.txt`
**Depends on:** none

**Goal:**
Pin all dependency versions for reproducible builds on ARM64. Run pip-compile on the Cubie to generate locked requirements.

**Acceptance criteria:**
- [ ] `requirements.txt` has pinned versions for all packages
- [ ] All packages install cleanly on ARM64 Ubuntu 24

**Notes:**
Must be done on the actual Cubie hardware or an ARM64 VM.

---

### TASK-P6-03 — Security Audit Pass
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** Phase 6 — Deployment Readiness
**Files:** `backend/app/**`, `lib/**`
**Depends on:** All Phase 1 tasks

**Goal:**
Run bandit, pip-audit, flutter analyze and fix all findings. Verify all security invariants.

**Acceptance criteria:**
- [ ] `bandit -r backend/app -ll` — 0 HIGH+ findings
- [ ] `pip-audit -r requirements.txt` — 0 known vulnerabilities
- [ ] `flutter analyze` — 0 errors, 0 warnings
- [ ] CORS wildcard confirmed removed (test with evil Origin header)
- [ ] JWT secret is ≥32 bytes, not default
- [ ] Cert pinning rejects wrong fingerprint
- [ ] All 6 Phase 1 security tasks verified

**Notes:**
This is a verification milestone, not a code-writing task.

---

### TASK-P6-04 — Hardware Integration Test
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 6 — Deployment Readiness
**Files:** none (manual testing)
**Depends on:** All previous phases

**Goal:**
Run end-to-end tests on actual Cubie hardware.

**Acceptance criteria:**
- [ ] `detect_board()` returns correct model name
- [ ] Thermal zone reads correct CPU temperature
- [ ] 10 concurrent file list requests — no deadlock
- [ ] Format 32GB+ USB drive via job API — completes successfully
- [ ] Restart service — OTP from pairing.json still valid
- [ ] App pairs via QR, uploads, downloads, searches, deletes

**Notes:**
Manual testing on the Cubie. Document results in logs.md.

---

## Phase 7 — Remaining Flutter Tests (from v1 M7)

> Complete the unfinished Flutter unit tests from Milestone 7.

---

### TASK-P7-01 — ApiService Unit Tests
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 7 — Flutter Tests
**Files:** `test/services/api_service_test.dart` (new)
**Depends on:** none

**Goal:**
Create unit tests for ApiService with mock HTTP client.

**Acceptance criteria:**
- [ ] Mock HTTP client setup (mockito or http_mock_adapter)
- [ ] Test: `listFiles()` deserializes `FileListResponse` correctly (including `totalCount`)
- [ ] Test: `getStorageStats()` deserializes `StorageStats` correctly
- [ ] Test: `listFiles(page: 1, pageSize: 50)` sends correct query params
- [ ] `flutter test` passes

**Notes:**
Tests 7F.1, 7F.2, 7F.3, 7F.7 from old tasks.md.

---

### TASK-P7-02 — AuthSession & Connection Notifier Tests
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** Phase 7 — Flutter Tests
**Files:** `test/services/auth_session_test.dart` (new)
**Depends on:** none

**Goal:**
Test AuthSessionNotifier and ConnectionNotifier state machines.

**Acceptance criteria:**
- [ ] Test: `AuthSessionNotifier.login()` sets all fields correctly
- [ ] Test: `AuthSessionNotifier.logout()` clears all fields
- [ ] Test: `ConnectionNotifier` does NOT emit `disconnected` within first 9 seconds (use `FakeAsync`)
- [ ] `flutter test` passes

**Notes:**
Tests 7F.4, 7F.5, 7F.6 from old tasks.md.

---

## Phase 8 — Future Features (Post-Release)

> Nice-to-have features. Do NOT start before Phases 1–6 are complete.

---

### TASK-P8-01 — Remote Access via Tailscale
**Priority:** 🟢 Low
**Status:** ⬜ todo
**Phase:** Phase 8 — Future
**Files:** Multiple (Flutter settings UI, ApiService dual-IP, backend status endpoint)
**Depends on:** Phase 6 complete

**Goal:**
Allow remote file access via Tailscale VPN overlay. Zero-config for users — just install Tailscale on phone and Cubie.

**Acceptance criteria:**
- [ ] "Remote Access" section in More tab with toggle and setup guide
- [ ] Tailscale IP input field, stored in SharedPreferences
- [ ] ApiService fallback: try LAN IP first (2s), then Tailscale IP
- [ ] Connection mode indicator ("via LAN" vs "via Tailscale")
- [ ] `GET /api/v1/system/tailscale-status` endpoint
- [ ] `POST /api/v1/system/tailscale-up` endpoint (admin only)
- [ ] TLS cert handles both IPs in SAN

**Notes:**
See old tasks.md Milestone 11 for detailed subtasks. Tailscale handles CGNAT traversal common with Indian ISPs.

---

### TASK-P8-02 — Internal Event Bus
**Priority:** 🟢 Low
**Status:** ⬜ todo
**Phase:** Phase 8 — Future
**Files:** `backend/app/events.py` (new)
**Depends on:** Phase 6 complete

**Goal:**
Create internal async event bus for publish/subscribe pattern. Foundation for future AI features (auto-tagging, smart search).

**Acceptance criteria:**
- [ ] `EventBus` class with `subscribe(event_type, callback)` and `publish(event_type, payload)`
- [ ] `FileEvent` dataclass: `path`, `action`, `user`, `timestamp`
- [ ] Wire file upload and delete routes to publish events
- [ ] In-memory circular buffer (last 1000 events)

**Notes:**
From old tasks.md Milestone 9A. Future-proofing only.

---

### TASK-P8-03 — SQLite Schema for File Index
**Priority:** 🟢 Low
**Status:** ⬜ todo
**Phase:** Phase 8 — Future
**Files:** `backend/app/config.py`, `backend/app/db_stub.py` (new)
**Depends on:** Phase 6 complete

**Goal:**
Feature-flagged SQLite database for file metadata indexing. Preparation for AI-powered file search.

**Acceptance criteria:**
- [ ] `enable_sqlite: bool = False` in config.py (CUBIE_ENABLE_SQLITE)
- [ ] `db_stub.py` creates SQLite with `file_index` and `ai_jobs` tables
- [ ] Only initializes if feature flag is true
- [ ] Schema documented in `kb/storage-architecture.md`

**Notes:**
From old tasks.md Milestone 9B. Not needed until AI features are built.

---

## Priority Order Summary

**Work in this exact sequence — each phase unblocks the next:**

| Order | Phase | Priority | Task Count | Focus |
|-------|-------|----------|------------|-------|
| 1 | Phase 1 | 🔴 BLOCKING | 6 tasks | Security fixes (MUST DO FIRST) |
| 2 | Phase 2 | 🔴 HIGH | 7 tasks | Core new features (auto-sort, search, bot, AdGuard) |
| 3 | Phase 3 | 🟠 HIGH | 2 tasks | Upload UX (streamed upload, error handling) |
| 4 | Phase 4 | 🟠 HIGH | 6 tasks | UI restructure (4 tabs, vocabulary, search bar) |
| 5 | Phase 5 | 🟡 MEDIUM | 2 tasks | Soft delete / trash |
| 6 | Phase 6 | 🟡 MEDIUM | 4 tasks | Deployment readiness (audit, hardware test) |
| 7 | Phase 7 | 🟡 MEDIUM | 2 tasks | Remaining Flutter tests |
| 8 | Phase 8 | 🟢 LOW | 3 tasks | Future features (Tailscale, events, AI prep) |

**Total: 32 tasks across 8 phases.**

---

*AiHomeCloud TASKSv2 — Generated 2025-03-10*
*Reference: v1 branch preserves all completed work from Milestones 1–8.*
