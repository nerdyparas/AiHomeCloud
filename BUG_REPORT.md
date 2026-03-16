# BUG REPORT — AiHomeCloud

> Systematic bug analysis performed 2026-03-16
> Auditor: AI Staff Engineer (Claude Opus 4.6)
> Scope: UI, API, filesystem, OCR, Telegram, network, concurrency, state management

---

## Severity Definitions

| Level | Meaning |
|-------|---------|
| 🔴 CRITICAL | Data loss, security hole, crash on common path |
| 🟠 HIGH | Feature broken or unusable under normal conditions |
| 🟡 MEDIUM | Degraded experience; workaround exists |
| 🔵 LOW | Cosmetic or minor annoyance; edge case |

---

## UI Issues

### BUG-UI-01: Hardcoded Dialog Strings (50+ instances)
**Severity:** 🟡 MEDIUM
**Files:** more_screen.dart, family_screen.dart, files_screen.dart, telegram_setup_screen.dart, storage_explorer_screen.dart
**Description:** Over 50 user-facing strings in confirmation dialogs and labels are hardcoded English instead of using `AppLocalizations`. Blocks future localization.
**Examples:**
- `'Server Certificate'` (more_screen.dart:418)
- `'Restart AiHomeCloud?'` (more_screen.dart:526)
- `'Shut Down AiHomeCloud?'` (more_screen.dart:576)
- `'Log Out?'` (more_screen.dart:628)
- `'Add Family Member'` (family_screen.dart:130)
- `'Delete permanently?'` (files_screen.dart:415)
- `'Bot Token is required.'` (telegram_setup_screen.dart:242)
**Reproduction:** Open any dialog in the app; strings are visible English.
**Root Cause:** L3 localization task only covered main_shell.dart and more_screen.dart section headers; dialogs were skipped.
**Fix:** Extract all hardcoded `Text('...')` and `'...'` literals in screens to `app_en.arb`.

### BUG-UI-02: Deprecated `.withOpacity()` Usage
**Severity:** 🔵 LOW
**File:** splash_screen.dart:144
**Description:** Uses `AppColors.background.withOpacity(0.5)` which is deprecated in Flutter 3.41+.
**Reproduction:** `flutter analyze` shows info-level warning.
**Root Cause:** Written before Flutter 3.31 deprecation.
**Fix:** Replace with `AppColors.background.withValues(alpha: 0.5)`.

### BUG-UI-03: No Double-Tap Guard on Upload Button
**Severity:** 🔵 LOW
**File:** folder_view.dart
**Description:** Rapidly tapping the upload FAB can trigger multiple file picker sessions simultaneously.
**Reproduction:** Tap upload button very quickly 3-4 times.
**Root Cause:** No debounce or `_isUploading` guard on the button's `onPressed`.
**Fix:** Add `_isPickerOpen` boolean guard; disable button during picker.

### BUG-UI-04: PinEntry Debounce Timer Safety
**Severity:** 🔵 LOW
**File:** pin_entry_screen.dart
**Description:** `_refreshDebounce` timer could be null-accessed if the screen is disposed during debounce.
**Reproduction:** Navigate away from PIN screen during the 300ms debounce window.
**Root Cause:** Timer callback fires after disposal.
**Fix:** Add `if (!mounted) return;` guard in debounce callback.

### BUG-UI-05: Upload Continues After Network Loss
**Severity:** 🟡 MEDIUM
**File:** folder_view.dart
**Description:** If network is lost during a multi-file upload, the upload continues to attempt writes against a dead connection instead of pausing and retrying.
**Reproduction:** Start uploading a large file → disconnect WiFi.
**Root Cause:** Upload stream doesn't check `connectionProvider` status.
**Fix:** Add connection status check in upload loop; abort or queue on disconnect.

### BUG-UI-06: Missing Empty State in Some Screens
**Severity:** 🔵 LOW
**Files:** Various screens
**Description:** Some screens show a loading spinner forever or blank space when there's no data, rather than a meaningful "No items" message.
**Reproduction:** Open empty folder; open trash when empty; open services when none configured.
**Root Cause:** `.when()` handlers don't always handle empty-data cases distinct from loading.

### BUG-UI-07: `deprecated_member_use` Warnings
**Severity:** 🔵 LOW
**Files:** main_shell.dart:343, telegram_setup_screen.dart:530
**Description:** `activeColor` on Switch widgets is deprecated since Flutter 3.31. Should use `activeThumbColor`.
**Reproduction:** `flutter analyze` shows info warnings.

---

## API Issues

### BUG-API-01: Missing Security Response Headers
**Severity:** 🟡 MEDIUM
**File:** backend/app/main.py
**Description:** Backend does not set security headers on HTTP responses:
- `Strict-Transport-Security` (HSTS)
- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `X-XSS-Protection: 1; mode=block`
- `Cache-Control: no-store` on auth endpoints
**Reproduction:** Inspect response headers from any API call.
**Root Cause:** No security headers middleware configured.
**Fix:** Add ASGI middleware that sets these headers on every response.

### BUG-API-02: Service ID Not Validated Against Whitelist
**Severity:** 🟡 MEDIUM
**File:** backend/app/routes/service_routes.py
**Description:** `POST /api/v1/services/{service_id}/toggle` accepts any string as `service_id`. The store lookup provides an implicit whitelist, but there's no explicit validation.
**Reproduction:** `POST /api/v1/services/malicious-string/toggle` — would attempt `systemctl start malicious-string`.
**Root Cause:** Route parameter not validated against known service list.
**Fix:** Add explicit `ALLOWED_SERVICES = {"samba", "nfs", "ssh", "dlna", "media"}` set and 400 on unknown.

### BUG-API-03: OTA Update Endpoint is Stub
**Severity:** 🟡 MEDIUM
**File:** backend/app/routes/system_routes.py:54
**Description:** `POST /api/v1/system/update` returns a success response but does nothing. The TODO comment is the only implementation.
**Reproduction:** Call the endpoint; it always returns "update_started" regardless of input.
**Root Cause:** Feature not implemented.
**Fix:** Either implement OTA logic or return 501 Not Implemented with a clear message.

### BUG-API-04: Jobs Not Scoped to User
**Severity:** 🔵 LOW
**File:** backend/app/routes/jobs_routes.py
**Description:** `GET /api/v1/jobs/{job_id}` allows any authenticated user to query any job by ID. While job IDs are UUIDs (low enumeration risk), this violates principle of least privilege.
**Reproduction:** User A starts a format job → User B queries the job ID → sees results.
**Root Cause:** No user_id field on Job model; no ownership check.
**Fix:** Add `user_id` field to Job; check ownership in route handler.

### BUG-API-05: Missing `aiosqlite` in requirements.txt
**Severity:** 🟡 MEDIUM
**File:** backend/requirements.txt
**Description:** `db_stub.py` imports `aiosqlite` but it's not listed in requirements.txt. If `AHC_ENABLE_SQLITE=true` is set, the import will crash.
**Reproduction:** Set `AHC_ENABLE_SQLITE=true` environment variable → start backend → ImportError.
**Root Cause:** Feature was added after initial requirements freeze.
**Fix:** Either add `aiosqlite>=0.20.0` to requirements.txt, or remove db_stub.py if unused.

### BUG-API-06: Health Endpoint Not Validated by Systemd
**Severity:** 🔵 LOW
**File:** backend/aihomecloud.service
**Description:** `/api/health` endpoint exists but systemd doesn't use it. Service reports "running" even if the API is broken.
**Reproduction:** Block port 8443 with iptables → systemctl shows "active (running)" even though API is unreachable.
**Root Cause:** No `ExecStartPost` health check in systemd unit.
**Fix:** Add `ExecStartPost=/usr/bin/curl -sf --retry 5 --retry-delay 2 https://localhost:8443/api/health -k || true`.

---

## Filesystem Issues

### BUG-FS-01: File Sort Age Check May Catch Incomplete Uploads
**Severity:** 🟡 MEDIUM
**File:** backend/app/file_sorter.py
**Description:** Files in `.inbox/` are sorted after 5 seconds (`_MIN_AGE_SECONDS = 5`). Large files uploading over slow connections may still be in-progress at 5s.
**Reproduction:** Upload a 2GB file over slow WiFi → file_sorter moves the incomplete file to Photos/Videos after 5s.
**Root Cause:** Age check only looks at mtime, not whether the file is being written.
**Fix:** Check if file has open handles (fuser/lsof) before sorting, or increase age to 30s, or use a `.uploading` suffix convention.

### BUG-FS-02: Corrupt JSON Silently Returns Empty Data
**Severity:** 🟡 MEDIUM
**File:** backend/app/store.py
**Description:** If a JSON file becomes corrupted (e.g., power loss during write), `_read_json()` renames it to `.corrupt` and returns `{}`. The user is never notified of data loss.
**Reproduction:** Write garbage to `/var/lib/aihomecloud/users.json` → restart → all users gone, no error shown.
**Root Cause:** Error handling returns default instead of raising.
**Fix:** Log at ERROR level; emit event on `/ws/events` with severity=error; attempt recovery from `.corrupt` backup.

### BUG-FS-03: Personal Folder Name Not Fully Sanitized
**Severity:** 🔵 LOW
**File:** backend/app/routes/family_routes.py
**Description:** `_ensure_personal_folder()` uses user name for directory creation. While `Path(name).name` strips directory components, names with special characters (dots, spaces, unicode) could create problematic folder names.
**Reproduction:** Create user with name `"john.doe"` → personal folder is `john.doe/` → `.doe` might be treated as extension.
**Root Cause:** Minimal sanitization beyond path component extraction.
**Fix:** Apply stricter name→folder mapping: alphanumeric + hyphens only, slug-ify.

---

## OCR / Document Indexing Issues

### BUG-OCR-01: Missing OCR Dependencies Fail Silently
**Severity:** 🟡 MEDIUM
**File:** backend/app/document_index.py
**Description:** If `pdftotext` or `tesseract` is not installed, the indexer logs a warning but indexes documents with empty text. Users can't search for these documents.
**Reproduction:** Uninstall tesseract → upload an image → search for text in image → no results.
**Root Cause:** Graceful degradation without user notification.
**Fix:** Check for OCR tools at startup; log ERROR if missing; show status in device info API.

### BUG-OCR-02: Index Watcher 20s Polling Delay
**Severity:** 🔵 LOW
**File:** backend/app/index_watcher.py
**Description:** File changes are detected via 20-second polling. Documents uploaded and immediately searched won't be found.
**Reproduction:** Upload document → immediately search → not found → wait 20s → found.
**Root Cause:** No inotify integration; polling-based design.
**Fix:** Acceptable for v1. Long-term: use `inotify` on Linux for near-instant indexing.

### BUG-OCR-03: Rename Detected as Delete + Add
**Severity:** 🔵 LOW
**File:** backend/app/index_watcher.py
**Description:** When a file is renamed, the watcher sees the old path disappear and a new path appear. The old index entry is removed and a new one created, re-running OCR unnecessarily.
**Root Cause:** File signature is (mtime_ns, size). Rename changes path but not content.
**Fix:** Track content hash alongside mtime/size to detect renames vs new files.

---

## Telegram Bot Issues

### BUG-TG-01: Pending Uploads Dict Unbounded
**Severity:** 🟡 MEDIUM
**File:** backend/app/telegram_bot.py
**Description:** `_pending_uploads` module-level dict grows without bound. If users send many files without completing or cancelling uploads, memory grows.
**Reproduction:** Send 1000 files to bot without completing the destination selection.
**Root Cause:** No TTL or max-size on the pending dict.
**Fix:** Add 5-minute TTL; cap at 100 entries; evict oldest on overflow.

### BUG-TG-02: Bot Crash Not Auto-Recovered
**Severity:** 🟡 MEDIUM
**File:** backend/app/main.py
**Description:** If the Telegram bot coroutine crashes after startup, it stays dead until the entire backend is restarted.
**Reproduction:** Force an unhandled exception in bot handler → bot stops responding → service still reports healthy.
**Root Cause:** No watchdog or health check for the bot task.
**Fix:** Wrap bot run in a supervisory task with exponential backoff restart.

### BUG-TG-03: No Per-Chat Rate Limiting
**Severity:** 🔵 LOW
**File:** backend/app/telegram_bot.py
**Description:** A single linked Telegram user can spam search/upload commands without throttling.
**Reproduction:** Rapid-fire `/search` commands from linked chat.
**Root Cause:** No rate limiting in bot handler.
**Fix:** Add per-chat_id rate limiter (e.g., 30 commands/minute).

### BUG-TG-04: File Download Timeout 600s Hardcoded
**Severity:** 🔵 LOW
**File:** backend/app/telegram_bot.py
**Description:** 10-minute timeout for file downloads. Very large files on slow connections may timeout.
**Reproduction:** Upload a 1.5GB file via slow mobile data.
**Root Cause:** Hardcoded constant.
**Fix:** Make configurable via `AHC_TELEGRAM_DOWNLOAD_TIMEOUT` env var.

---

## Network Discovery Issues

### BUG-NET-01: mDNS Not Configured by Production Installer
**Severity:** 🟠 HIGH
**File:** scripts/first-boot-setup.sh
**Description:** The production `first-boot-setup.sh` script does not configure Avahi mDNS service. Only `dev-setup.sh` deploys the Avahi service file. Without mDNS, the Flutter app's primary discovery mechanism fails.
**Reproduction:** Run `first-boot-setup.sh` on clean device → Flutter app → Scan → mDNS times out → falls back to BLE → may also fail if BLE not configured.
**Root Cause:** mDNS setup was only added to dev-setup.sh.
**Fix:** Merge Avahi mDNS deployment into first-boot-setup.sh.

### BUG-NET-02: BLE Discovery Error Handling
**Severity:** 🔵 LOW
**File:** lib/services/discovery_service.dart
**Description:** All BLE exceptions are caught with empty catch blocks. If BLE hardware is faulty, no error message is shown.
**Reproduction:** Use a device with broken BLE → mDNS fails → BLE fails → generic "not found" message.
**Root Cause:** Catch-all BLE error handling.
**Fix:** Log BLE errors; show "BLE unavailable" in discovery UI.

---

## Concurrency Issues

### BUG-CONC-01: Cache Stampede on Store TTL Expiry
**Severity:** 🔵 LOW
**File:** backend/app/store.py
**Description:** When TTL cache expires, multiple concurrent async tasks can all miss the cache and hit disk simultaneously, doing redundant reads.
**Reproduction:** 10 concurrent `/api/v1/files/list` requests after cache expiry.
**Root Cause:** No lock on cache re-population.
**Fix:** Use a per-key lock or "dog-pile" prevention (first reader refreshes, others wait).

### BUG-CONC-02: Concurrent Renames Can Collide
**Severity:** 🔵 LOW
**File:** backend/app/routes/file_routes.py
**Description:** Two simultaneous rename operations on the same source file could race. `_safe_resolve()` prevents path escape but doesn't prevent TOCTOU on the rename itself.
**Reproduction:** Two clients rename `photo.jpg` to different names simultaneously.
**Root Cause:** No file-level locking on rename operations.
**Fix:** Acceptable for v1 (home use, 1-5 users). Document behavior.

---

## State Management Issues

### BUG-STATE-01: WebSocket Reconnect Backoff Resets on Success
**Severity:** 🔵 LOW
**File:** lib/providers/device_providers.dart
**Description:** `ConnectionNotifier` exponential backoff `[2, 4, 8, 16, 30]` resets to 0 on successful reconnect. If connection is flaky (connects briefly then drops), backoff never reaches higher values.
**Reproduction:** Network that drops every 3 seconds → reconnect backoff never exceeds 2s → rapid reconnect attempts.
**Root Cause:** Backoff counter reset on any successful connect.
**Fix:** Track recent connect/disconnect rate; only reset backoff after sustained connection (e.g., 30s stable).

### BUG-STATE-02: Optimistic Service Toggle Rollback Delay
**Severity:** 🔵 LOW
**File:** lib/providers/data_providers.dart
**Description:** `ServicesNotifier.toggle()` optimistically updates UI then calls API. On failure, it rolls back. Users see a brief flash of the toggled state before rollback.
**Reproduction:** Toggle Samba service → API returns 500 → briefly shows "ON" → rolls back to "OFF".
**Root Cause:** Optimistic update pattern with network delay.
**Fix:** Acceptable UX pattern. Could add a "pending" state indicator.

---

## Deployment Issues

### BUG-DEPLOY-01: deploy.sh Insecure TLS Default
**Severity:** 🟠 HIGH
**File:** deploy.sh
**Description:** Health check uses `curl -k` (disable TLS verification) as the default. Only warns about insecurity.
**Reproduction:** Run `deploy.sh` without `AHC_CERT` → health check passes even with MITM.
**Root Cause:** Convenience over security for self-signed cert scenario.
**Fix:** Default to fail-closed; require `AHC_CERT` or `--insecure` explicit flag.

### BUG-DEPLOY-02: No Deployment Rollback
**Severity:** 🟡 MEDIUM
**Files:** deploy.sh, first-boot-setup.sh
**Description:** If a deploy breaks the service, there's no automated way to revert to the previous version.
**Reproduction:** Deploy broken code → service crashes → manual SSH required to fix.
**Root Cause:** No snapshot/backup mechansim.
**Fix:** Backup current code before rsync; add `--rollback` flag to restore backup.

### BUG-DEPLOY-03: Systemd Missing Resource Limits
**Severity:** 🟡 MEDIUM
**File:** backend/aihomecloud.service
**Description:** No CPU, memory, or file descriptor limits. A runaway process could consume all system resources.
**Reproduction:** OOM condition → backend consumes all 8GB RAM → device becomes unresponsive.
**Root Cause:** Resource limits not configured in unit file.
**Fix:** Add `LimitNOFILE=65536`, `MemoryMax=1G`, `CPUQuota=80%`.

---

## Summary

| Category | 🔴 Critical | 🟠 High | 🟡 Medium | 🔵 Low | Total |
|----------|-------------|---------|-----------|--------|-------|
| UI | 0 | 0 | 2 | 5 | 7 |
| API | 0 | 0 | 3 | 2 | 5 |
| Filesystem | 0 | 0 | 2 | 1 | 3 |
| OCR | 0 | 0 | 1 | 2 | 3 |
| Telegram | 0 | 0 | 2 | 2 | 4 |
| Network | 0 | 1 | 0 | 1 | 2 |
| Concurrency | 0 | 0 | 0 | 2 | 2 |
| State | 0 | 0 | 0 | 2 | 2 |
| Deployment | 0 | 1 | 2 | 0 | 3 |
| **Total** | **0** | **2** | **12** | **17** | **31** |

**Note:** No critical bugs found. The 2 HIGH severity bugs (mDNS not in production installer, insecure deploy default) are deployment-level, not code-level. The previous audit session (2026-03-16) fixed all previously-identified critical bugs (C1-C4).
