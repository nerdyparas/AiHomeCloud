# TASK ROADMAP — AiHomeCloud

> Generated from PROJECT_AUDIT.md and BUG_REPORT.md on 2026-03-16
> Priority: stability → security → UX → polish
> Each task is self-contained with clear acceptance criteria.

---

## Phase 1: Critical Stability Fixes ✅

> Goal: Make the system reliable enough for daily home use.

### TASK-S1: Telegram Bot Crash Recovery ✅ DONE
**Bug Ref:** BUG-TG-02
**Files:** `backend/app/main.py`, `backend/app/telegram_bot.py`
**Problem:** If the Telegram bot coroutine crashes, it stays dead until full backend restart.
**Requirements:**
1. Wrap bot startup in a supervisor task
2. Exponential backoff restart: 5s, 10s, 30s, 60s, max 5 attempts
3. Log each restart attempt at WARNING level
4. After max attempts, log ERROR and stop retrying (don't crash the backend)
5. Emit event on `/ws/events` when bot goes down/recovers
**Test:** Kill bot task → verify automatic restart within 10s. Kill 5 times → verify supervisor gives up.

### TASK-S2: Corrupt JSON Recovery & Notification ✅ DONE
**Bug Ref:** BUG-FS-02
**Files:** `backend/app/store.py`, `backend/app/events.py`
**Problem:** Corrupt JSON files silently return `{}`, potentially losing all users.
**Requirements:**
1. On corrupt JSON detection, log at ERROR level (not just warning)
2. Emit event on `/ws/events` with type `data_corruption`, severity `error`
3. Attempt to recover from `.corrupt` file if it's valid JSON
4. If recovery fails, emit event with affected file name
5. Keep current backup behaviour (rename to `.corrupt`)
**Test:** Write corrupt JSON → restart → verify event emitted → verify recovery attempted.

### TASK-S3: File Sort Incomplete Upload Protection ✅ DONE
**Bug Ref:** BUG-FS-01
**Files:** `backend/app/file_sorter.py`
**Problem:** Files in `.inbox/` sorted after 5s — may catch mid-upload files.
**Requirements:**
1. Increase `_MIN_AGE_SECONDS` from 5 to 30
2. Add `.uploading` suffix check — skip files ending in `.uploading`
3. Backend upload should write to `filename.uploading` then rename on completion
4. File sorter skips any file with `.uploading` or `.part` suffix
**Test:** Create `.uploading` file → verify sorter skips it. Wait 30s → verify normal files sorted.

### TASK-S4: Pending Telegram Uploads TTL ✅ DONE
**Bug Ref:** BUG-TG-01
**Files:** `backend/app/telegram_bot.py`
**Problem:** `_pending_uploads` dict grows without bound.
**Requirements:**
1. Add timestamp to each pending entry
2. Expire entries older than 5 minutes
3. Cap at 100 entries; evict oldest on overflow
4. Run cleanup every 60s via background task or on each new entry
**Test:** Add 150 entries → verify only 100 remain → wait 5 min → verify all expired.

---

## Phase 2: Backend Reliability ✅

> Goal: Harden the backend against edge cases and improve observability.

### TASK-R1: Security Response Headers ✅ DONE
**Bug Ref:** BUG-API-01
**Files:** `backend/app/main.py`
**Problem:** No HSTS, X-Frame-Options, or CSP headers on responses.
**Requirements:**
1. Add ASGI middleware that applies these headers to every response:
   - `Strict-Transport-Security: max-age=31536000; includeSubDomains`
   - `X-Frame-Options: DENY`
   - `X-Content-Type-Options: nosniff`
   - `X-XSS-Protection: 0` (modern recommendation)
   - `Cache-Control: no-store` on `/api/v1/auth/*` endpoints
2. Skip HSTS when `TLS_ENABLED=false` (dev mode)
**Test:** Call any endpoint → verify headers present. Call auth endpoint → verify `Cache-Control: no-store`.

### TASK-R2: Service ID Whitelist ✅ DONE
**Bug Ref:** BUG-API-02
**Files:** `backend/app/routes/service_routes.py`
**Problem:** Service toggle accepts arbitrary service_id strings.
**Requirements:**
1. Define `ALLOWED_SERVICES = {"samba", "nfs", "ssh", "dlna", "media"}`
2. Return HTTP 400 if `service_id not in ALLOWED_SERVICES`
3. Check before any systemctl call
**Test:** Toggle `samba` (200 OK). Toggle `evil-service` (400).

### TASK-R3: OTA Endpoint Returns 501 ✅ DONE
**Bug Ref:** BUG-API-03
**Files:** `backend/app/routes/system_routes.py`
**Problem:** OTA stub returns success, misleading clients.
**Requirements:**
1. Return `501 Not Implemented` with body `{"detail": "OTA updates not yet available"}`
2. Remove `TODO` comment
**Test:** Call endpoint → verify 501 status.

### TASK-R4: Systemd Resource Limits ✅ DONE
**Bug Ref:** BUG-DEPLOY-03
**Files:** `backend/aihomecloud.service`
**Problem:** No CPU, RAM, or FD limits.
**Requirements:**
1. Add `LimitNOFILE=65536`
2. Add `MemoryMax=1G`
3. Add `CPUQuota=80%`
4. Add `TasksMax=256`
**Test:** Verify `systemctl show aihomecloud.service -p LimitNOFILE,MemoryMax,CPUQuota,TasksMax`.

### TASK-R5: OCR Tool Startup Check ✅ DONE
**Bug Ref:** BUG-OCR-01
**Files:** `backend/app/document_index.py`, `backend/app/routes/system_routes.py`
**Problem:** Missing OCR tools fail silently.
**Requirements:**
1. At startup, check `which pdftotext` and `which tesseract`
2. Store availability as boolean flags in module state
3. If missing, log WARNING with install instructions
4. Include OCR tool status in `GET /api/v1/system/info` response
**Test:** Remove tesseract from PATH → verify warning logged and system/info shows `ocrAvailable: false`.

### TASK-R6: Job Store User Scoping ✅ DONE
**Bug Ref:** BUG-API-04
**Files:** `backend/app/job_store.py`, `backend/app/routes/jobs_routes.py`
**Problem:** Any user can query any job.
**Requirements:**
1. Add `user_id` field to Job dataclass
2. Pass `user_id` when creating jobs
3. In `GET /api/v1/jobs/{job_id}`, verify `job.user_id == current_user.sub`
4. Admin can query any job
**Test:** User A creates job → User B queries → 404.

---

## Phase 3: Flutter UI Fixes ✅

> Goal: Polish the mobile app for non-technical users.

### TASK-F1: Complete Localization ✅ DONE
**Bug Ref:** BUG-UI-01
**Files:** `lib/l10n/app_en.arb`, all screen files
**Problem:** 50+ hardcoded English strings in dialogs.
**Requirements:**
1. Extract all hardcoded `Text('...')` and dialog title/body strings to `app_en.arb`
2. Wire `AppLocalizations.of(context)!.keyName` in each screen
3. Focus on: more_screen.dart, family_screen.dart, files_screen.dart, telegram_setup_screen.dart, storage_explorer_screen.dart, profile_edit_screen.dart
4. Use consistent naming: `screenActionDescription` (e.g., `moreLogOutTitle`, `familyAddTitle`)
**Test:** `flutter analyze` passes; grep for `Text('` in screens shows zero hardcoded strings.

### TASK-F2: Fix Deprecated API Usage ✅ DONE
**Bug Ref:** BUG-UI-02, BUG-UI-07
**Files:** splash_screen.dart, main_shell.dart, telegram_setup_screen.dart
**Problem:** `.withOpacity()` and `activeColor` are deprecated.
**Requirements:**
1. Replace `.withOpacity(x)` with `.withValues(alpha: x)` in splash_screen.dart
2. Replace `activeColor` with `activeThumbColor` on Switch widgets
**Test:** `flutter analyze --no-fatal-infos` shows 0 deprecated_member_use warnings.

### TASK-F3: Upload Button Debounce ✅ DONE
**Bug Ref:** BUG-UI-03
**Files:** `lib/widgets/folder_view.dart`
**Problem:** Rapid taps on upload button open multiple file pickers.
**Requirements:**
1. Add `_isPickerOpen` boolean state variable
2. Set to `true` before opening file picker; `false` after picker returns
3. Disable upload button when `_isPickerOpen` is true
**Test:** Tap button rapidly → only one picker opens.

### TASK-F4: PinEntry Timer Safety ✅ DONE
**Bug Ref:** BUG-UI-04
**Files:** `lib/screens/onboarding/pin_entry_screen.dart`
**Problem:** Debounce timer callback may fire after widget disposal.
**Requirements:**
1. Add `if (!mounted) return;` guard at start of debounce callback
2. Cancel timer in `dispose()` method
**Test:** Navigate away during debounce → no exception.

### TASK-F5: Upload Network Loss Handling ✅ DONE
**Bug Ref:** BUG-UI-05
**Files:** `lib/widgets/folder_view.dart`, `lib/providers/file_providers.dart`
**Problem:** Upload continues against dead connection.
**Requirements:**
1. Check `connectionProvider` status before each chunk upload
2. If disconnected, mark upload as `failed` with message "Connection lost"
3. Show snackbar with retry option
**Test:** Start upload → disconnect → upload marked failed → reconnect → retry works.

---

## Phase 4: Telegram Bot Improvements ✅

> Goal: Make the Telegram integration reliable for daily document management.

### TASK-T1: Bot Supervisor (see TASK-S1)
Already covered in Phase 1.

### TASK-T2: Per-Chat Rate Limiting ✅ DONE
**Bug Ref:** BUG-TG-03
**Files:** `backend/app/telegram_bot.py`
**Problem:** No rate limit on bot commands.
**Requirements:**
1. Track per-chat_id command count with 1-minute sliding window
2. Limit: 30 commands/minute
3. Reply with "Please wait a moment" when exceeded
**Test:** Send 35 commands in 1 minute → only 30 processed; 5 get rate-limit message.

### TASK-T3: Configurable Download Timeout ✅ DONE
**Bug Ref:** BUG-TG-04
**Files:** `backend/app/telegram_bot.py`, `backend/app/config.py`
**Problem:** 600s hardcoded timeout.
**Requirements:**
1. Add `telegram_download_timeout: int = 600` to Settings
2. Use `settings.telegram_download_timeout` in download handler
**Test:** Set `AHC_TELEGRAM_DOWNLOAD_TIMEOUT=120` → verify timeout used.

### TASK-T4: Split telegram_bot.py ✅ DONE
**Bug Ref:** PROJECT_AUDIT Q1
**Files:** `backend/app/telegram_bot.py` → split into sub-modules
**Problem:** 1,564 lines in one file.
**Requirements:**
1. Create `backend/app/telegram/` package
2. Split into: `__init__.py`, `auth_handlers.py`, `search_handlers.py`, `upload_handlers.py`, `bot_core.py`
3. Keep public API identical (same function signatures callable from main.py)
4. Move module-level dicts to bot_core.py
5. All imports at module level (remove inline imports)
**Test:** All 29 existing telegram tests pass unchanged.

---

## Phase 5: CI Pipeline Repair & Enhancement ✅

> Goal: CI passes reliably and catches regressions.

### TASK-CI1: Backend Coverage Metrics ✅ DONE
**Files:** `.github/workflows/backend-tests.yml`, `backend/pytest.ini`
**Problem:** No coverage tracking.
**Requirements:**
1. Add `pytest-cov` to dev dependencies
2. Run `pytest --cov=app --cov-report=xml tests/`
3. Upload coverage XML as artifact (or to Codecov if configured)
4. Set minimum coverage threshold: 70%
**Test:** CI run produces coverage-report.xml artifact.

### TASK-CI2: APK Build Verification ✅ DONE
**Files:** `.github/workflows/flutter-analyze.yml`
**Problem:** CI doesn't verify Android build compiles.
**Requirements:**
1. Add `flutter build apk --debug` step after tests
2. Don't upload artifact (just verify it builds)
3. This catches import errors, manifest issues, plugin version mismatches
**Test:** CI run includes successful APK build step.

### TASK-CI3: Add pytest Markers ✅ DONE
**Files:** `backend/pytest.ini`, test files
**Problem:** No test categorization.
**Requirements:**
1. Add markers: `slow`, `integration`, `security`
2. Mark path safety tests as `security`
3. Mark hardware tests as `integration`
4. Add `markers =` section to pytest.ini
**Test:** `pytest -m security` runs only security-tagged tests.

---

## Phase 6: Universal Installer ✅

> Goal: One command installs and starts the server on any ARM Linux device.

### TASK-INST1: Create install.sh ✅ DONE
**Bug Ref:** BUG-NET-01
**Files:** `install.sh` (new)
**Problem:** No single installer; first-boot-setup.sh missing mDNS.
**Requirements:**
1. Detect architecture (`uname -m`): aarch64, armv7l, x86_64
2. Detect OS: Ubuntu 22+, Debian 12+, Armbian
3. Install system dependencies: Python 3.12+, avahi-daemon, tesseract-ocr, poppler-utils, samba, minidlnad
4. Create `aihomecloud` system user
5. Create directories: `/opt/aihomecloud`, `/srv/nas/{personal,family,entertainment}`, `/var/lib/aihomecloud`
6. Create Python venv and install requirements
7. Deploy Avahi mDNS service file
8. Install and enable systemd service
9. Generate device serial + pairing key
10. Configure sudoers whitelist
11. Start service and validate via `/api/health` endpoint
12. Print QR code URL and next steps
13. On failure: log error, clean up partial install, exit non-zero
**Test:** Run on clean Ubuntu 24.04 ARM64 → service starts → Flutter app discovers device.

### TASK-INST2: Pre-Flight Checks ✅ DONE
**Files:** `install.sh`
**Problem:** No validation before install.
**Requirements:**
1. Check root/sudo access
2. Verify disk space (>500MB free)
3. Verify internet connectivity (ping)
4. Check for conflicting services (Apache, Nginx on port 8443)
5. Verify Python 3.12+ available or installable
**Test:** Run on system with <100MB free → clear error message.

### TASK-INST3: Uninstall Script ✅ DONE
**Files:** `uninstall.sh` (new)
**Problem:** No way to cleanly remove the system.
**Requirements:**
1. Stop and disable systemd service
2. Remove `/opt/aihomecloud` (code only, not data)
3. Remove Avahi service file
4. Optionally remove data dirs (`--purge` flag)
5. Remove sudoers rules
6. Remove system user (`--purge` flag)
7. Print confirmation of what was removed
**Test:** Install → uninstall → verify no traces (except data dirs without `--purge`).

---

## Phase 7: Performance & Code Quality

> Goal: Professional engineering standards.

### TASK-PQ1: Add Type Hints to Core Modules ✅ DONE
**Files:** `backend/app/store.py`, `backend/app/auth.py`, `backend/app/config.py`
**Problem:** Missing return types and parameter types.
**Requirements:**
1. Add type hints to all public functions in store.py (20+ functions)
2. Add type hints to auth.py (create_token, decode_token, hash/verify functions)
3. Add type hints to config.py property methods
4. Run `mypy --strict` on modified files (may need `mypy.ini` config)
**Test:** `mypy backend/app/store.py backend/app/auth.py` → 0 errors.

### TASK-PQ2: Cleanup Repository Root ✅ DONE
**Files:** 15 stale files in project root
**Problem:** Stale session artifacts cluttering the repo.
**Requirements:**
1. Create `docs/archive/` directory
2. Move these files to `docs/archive/`:
   - SESSIONS_1_TO_4_PROMPT.md, FIX_USER_PICKER_PIN.md, FIX_TELEGRAM_SBC_ONLY.md
   - FIX_EMOJI_AVATAR.md, FIX_DASHBOARD_STORAGE_TILES.md, PROFILE_EDIT_SCREEN.md
   - OPUS_REBUILD_KB.md, OPUS_AUDIT_PROMPT.md, ALL_AGENT_TASKS.md
   - TELEGRAM_BOT_POLISH.md, REDESIGN_MORE_SCREEN.md, REDESIGN_DASHBOARD.md
   - backendAudit.md
3. Delete: `_patch_telegram.py`, `_patch2_telegram.py`
4. Update `.gitignore` if needed
**Test:** Root directory contains only: README.md, TASKS.md, LICENSE, PROJECT_AUDIT.md, BUG_REPORT.md, TASK_ROADMAP.md, pubspec.yaml, analysis_options.yaml, config files.

### TASK-PQ3: Remove Dead Code
**Files:** `backend/app/db_stub.py`, `lib/services/mock_api_service.dart`
**Problem:** Unused code.
**Requirements:**
1. If `db_stub.py` is truly unused and `AHC_ENABLE_SQLITE` is never set: delete the file and remove import from main.py
2. If keeping: add `aiosqlite>=0.20.0` to requirements.txt
3. For `mock_api_service.dart`: Either complete the 20 TODO stubs or document it as test-only fixture
**Test:** Backend starts without db_stub.py. Flutter tests still pass.

### TASK-PQ4: Connection Pool for FTS5
**Files:** `backend/app/document_index.py`
**Problem:** New SQLite connection per query.
**Requirements:**
1. Create a connection pool (2-3 connections for FTS5 reads)
2. Return connections on request completion
3. Close pool on shutdown
**Test:** 100 concurrent search requests → no "database is locked" errors.

### TASK-PQ5: Expand Flutter Test Coverage
**Files:** `test/` directory
**Problem:** 33% screen coverage, 50% widget coverage.
**Requirements:**
1. Add tests for untested screens: family_screen, storage_explorer_screen, telegram_setup_screen, file_preview_screen, profile_edit_screen
2. Add tests for untested widgets: FolderView, EmojiPickerGrid, UserAvatar, NotificationOverlay
3. Target: 80% screen coverage, 75% widget coverage
**Test:** `flutter test` → all pass; coverage report shows targets met.

---

## Implementation Schedule

| Phase | Tasks | Priority | Estimated Effort |
|-------|-------|----------|-----------------|
| **Phase 1: Stability** | S1–S4 | 🔴 CRITICAL | 4 tasks |
| **Phase 2: Backend** | R1–R6 | 🟠 HIGH | 6 tasks |
| **Phase 3: Flutter UI** | F1–F5 | 🟡 MEDIUM | 5 tasks |
| **Phase 4: Telegram** | T2–T4 | 🟡 MEDIUM | 3 tasks |
| **Phase 5: CI** | CI1–CI3 | 🟡 MEDIUM | 3 tasks |
| **Phase 6: Installer** | INST1–INST3 | 🟠 HIGH | 3 tasks |
| **Phase 7: Quality** | PQ1–PQ5 | 🔵 LOW | 5 tasks |
| **Total** | | | **29 tasks** |

---

## Dependencies

```
TASK-S1 (bot recovery) ← TASK-T4 (split telegram_bot.py)
TASK-S3 (upload protection) ← TASK-F5 (upload network loss)
TASK-R1 (headers) ← no deps
TASK-R4 (systemd) ← TASK-INST1 (installer)
TASK-F1 (localization) ← no deps (can start immediately)
TASK-CI1 (coverage) ← no deps
TASK-INST1 (installer) ← TASK-R4 (resource limits)
TASK-T4 (split bot) ← TASK-S4 (pending uploads TTL)
```

---

## Acceptance Criteria (Per Phase)

| Phase | Definition of Done |
|-------|-------------------|
| Phase 1 | Backend survives Telegram crash, corrupt JSON, incomplete upload; 260+ tests pass |
| Phase 2 | Security headers present; service whitelist enforced; systemd hardened |
| Phase 3 | Zero hardcoded UI strings; zero deprecated API usage; upload has debounce |
| Phase 4 | Bot survives crash; rate limited; split into 4 files |
| Phase 5 | CI reports coverage; APK builds verified; test markers working |
| Phase 6 | `sudo ./install.sh` on clean ARM device → service running in <5 min |
| Phase 7 | Type hints on core modules; stale files archived; FTS5 connection pooled |
