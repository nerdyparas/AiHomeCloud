# AiHomeCloud — Production-Grade Audit Tasks

Last updated: 2026-03-16

> **Goal:** Make backend + Flutter app production-grade — fix all bugs, harden security, optimize performance.
> Generated from full codebase audit on 2026-03-16.
> Work through tasks top-to-bottom. Each task is self-contained.

---

## ✅ Already Fixed (This Session)

- [x] **Profile Edit Stale Emoji Race** — `profile_edit_screen.dart` now uses a flag to prevent background updates from overwriting a user's emoji selection.
- [x] **Splash Screen Loading State** - `splash_screen.dart` now shows a loading indicator when connecting to a device.
- [x] **Timing-safe pairing key comparison** — `auth_routes.py` pair + pair/complete now use `hmac.compare_digest()` for serial and key comparisons (prevents timing attacks)
- [x] **friendlyError in services toggle** — `data_providers.dart` `ServicesNotifier.toggle()` now uses `friendlyError(e)` instead of `e.toString()`
- [x] **Family dialog error handling** — `family_screen.dart` add + remove dialogs now have try/catch with `friendlyError()` in snackbars
- [x] **Revoked token cleanup** — `store.py` `purge_expired_tokens()` now also removes revoked tokens (prevents unbounded tokens.json growth)
- [x] **TASK-C1: Admin Promotion / Demotion Endpoint** — `store.update_user_role()`, `PUT /api/v1/users/family/{id}/role`, `SetUserRoleRequest` model, 5 tests (promote, demote, block last admin, 403 for non-admin, 404 for unknown user)
- [x] **TASK-C2: Admin Promotion UI** — `setUserRole()` in `family_api.dart`, long-press bottom sheet on `_MemberCard`, confirmation dialog, `onLongPress` added to `AppCard`
- [x] **TASK-H2: PIN Entry Race Condition** — `pin_entry_screen.dart` background refresh now debounced 300ms; `_pinController.clear()` called when `_selectedUser` nulled
- [x] **TASK-H4: WebSocket Per-User Connection Limit** — `monitor_routes.py` now tracks per-user connection count; limit 3/user, 10 total; returns 4029 on breach
- [x] **TASK-H5: Rate Limiting on File Endpoints** — `file_routes.py` list/mkdir/delete/rename at 60/min, upload at 20/min, download at 120/min
- [x] **TASK-H6: HTTP 429 Detection in Flutter** — `api_service.dart` `_check()` throws specific message on 429; `error_utils.dart` maps rate-limit messages to user-friendly text
- [x] **TASK-H7: Atomic Write Safety in store.py** — `_atomic_write()` sets `fsync_ok` flag; `os.replace()` only called after fsync; logs error with path on fsync failure
- [x] **TASK-H8: Trash Metadata Atomicity** — `delete_file` in `file_routes.py` writes metadata first, then moves file; rolls back metadata on move failure
- [x] **TASK-C3: First-User Admin Race Condition Guard** — `_user_creation_lock` added to `store.py`; `create_user` in `auth_routes.py` re-reads user list inside the lock; bcrypt hashed before lock entry to minimise hold time; `test_concurrent_first_user_exactly_one_admin` added (30 auth tests, 260 total passing)
- [x] **TASK-C4: CORS Hardening** — `main.py` CORS middleware now uses explicit `allow_methods` and `allow_headers` instead of `["*"]`
- [x] **TASK-M1: Pagination Loading Indicator** — `folder_view.dart` sentinel item now shows a standalone 24 px `CircularProgressIndicator` instead of a disabled button while `_loadingMore` is true
- [x] **TASK-M2: File Search Empty State** — already implemented (`_DocSearchResults` widget shows icon + "No documents found for…" when results are empty)
- [x] **TASK-M3: WebSocket Max Retry** — `monitorSystemStats()` in `system_api.dart` refactored to `async*`; reconnects up to 30 times with exponential back-off (2–30 s); calls `ConnectionStatus.disconnected` after max retries and closes the stream
- [x] **TASK-M4: Upload Subscription Cleanup** — already implemented (`_startUpload` has `onError` handler that removes from map and marks upload failed with `friendlyError`)
- [x] **TASK-M5: Storage Label Validation** — `format_device` in `storage_routes.py` validates label: max 16 chars, alphanumeric/hyphens/underscores; returns HTTP 400 on invalid
- [x] **TASK-M6: Document Index Timeout** — `index_documents_under_path` in `document_index.py` wraps each `index_document` call in `asyncio.wait_for(..., timeout=120)`; logs warning and continues on timeout
- [x] **TASK-M7: Telegram SHA-256 Hashing** — `_compute_md5` → `_compute_sha256` in `telegram_bot.py`; uses `hashlib.sha256()`; existing hash cache naturally invalidated
- [x] **TASK-M8: Telegram Download Error Cleanup** — `_store_private_or_shared_file` and `_store_entertainment_file` now wrap downloads in try/except; partial temp files are unlinked on failure with a warning log
- [x] **TASK-M9: Dead Code — trashAutoDeleteProvider** — provider removed from `file_providers.dart`; auto-delete toggle UI removed from `_TrashScreen` in `files_screen.dart` (feature deferred)
- [x] **TASK-M10: Family Folder Size Performance** — `_folder_size_gb_sync` now honours a 5-level depth limit; `_folder_size_gb` wraps executor call in `asyncio.wait_for(timeout=10)`; logs warning and returns -1 on timeout

---

## 🔴 CRITICAL — Must Fix Before Release

### TASK-C1: Admin Promotion / Demotion Endpoint
**Files:** `backend/app/routes/auth_routes.py`, `backend/app/routes/family_routes.py`
**Problem:** No way to promote a user to admin or demote an admin. If the only admin deletes their account (blocked) or becomes unavailable, no one can manage the device. First user auto-becomes admin but there's no transfer mechanism.
**Requirements:**
1. Add `PUT /api/v1/users/{user_id}/role` endpoint (admin-only, body: `{"isAdmin": true/false}`)
2. Prevent demoting the last admin (same guard as delete)
3. Add `store.update_user_role(user_id, is_admin)` in `store.py`
4. Update `kb/api-contracts.md` with the new endpoint
**Test:** Add test in `backend/tests/test_auth.py` — promote user, verify admin flag, try demoting last admin (should 400)

### TASK-C2: Admin Promotion UI in Family Screen
**Files:** `lib/screens/main/family_screen.dart`, `lib/services/api/family_api.dart`
**Problem:** No Flutter UI to promote/demote users. Admin badge shows but is not actionable.
**Requirements:**
1. Add long-press menu on `_MemberCard` with "Make Admin" / "Remove Admin" options (only visible to current admin)
2. Add `setUserRole(String userId, bool isAdmin)` to `family_api.dart`
3. Show confirmation dialog before role change
4. Invalidate `familyUsersProvider` after change
5. Use `friendlyError(e)` for all error display

### TASK-C3: First-User Admin Race Condition Guard
**Files:** `backend/app/routes/auth_routes.py`
**Problem:** Two simultaneous create-user requests could both see `len(existing) == 0` and both become admin.
**Requirements:**
1. Wrap the first-user check + user creation in an async lock (reuse `store._store_lock` or create a dedicated one)
2. Re-check `len(existing)` inside the lock before creating
**Test:** Add concurrent user creation test

### TASK-C4: CORS Hardening
**Files:** `backend/app/main.py`
**Problem:** `allow_methods=["*"]` and `allow_headers=["*"]` is overly permissive for production.
**Requirements:**
1. Change to `allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"]`
2. Change to `allow_headers=["Authorization", "Content-Type", "X-Request-ID"]`
**Test:** Verify CORS headers in response match expected values

---

## 🟠 HIGH — Fix Before Beta

*(All H2–H8 completed — see Done section below.)*

---

## 🟡 MEDIUM — Polish Sprint

*(All M1–M10 completed — see ✅ Already Fixed section above.)*

---

## 🔵 LOW — Nice-to-Have

### ✅ TASK-L1: Onboarding Route Guards *(DONE)*
**Files:** `lib/navigation/app_router.dart`
- Added redirect guard: `/profile-creation` → `/scan-network` when discovery status ≠ `found`
- Fixed null-safety in `/profile-creation` builder

### ✅ TASK-L2: Accessibility Semantics *(DONE)*
**Files:** `lib/widgets/file_list_tile.dart`, `lib/widgets/app_card.dart`, `lib/navigation/main_shell.dart`, `lib/widgets/folder_view.dart`
- `Semantics` wrapping, `semanticLabel`/`tooltip` on nav icons, `liveRegion` on banners

### ✅ TASK-L3: String Localization Audit *(DONE)*
**Files:** `lib/l10n/app_en.arb`, `lib/navigation/main_shell.dart`, `lib/screens/main/more_screen.dart`
- 30+ new ARB keys added; `AppLocalizations` wired in `main_shell.dart` and `more_screen.dart`

### ✅ TASK-L4: Audit Logging for Destructive Operations *(DONE)*
**Files:** `backend/app/audit.py` (new), `backend/app/routes/auth_routes.py`, `backend/app/routes/family_routes.py`, `backend/app/routes/file_routes.py`, `backend/app/routes/storage_routes.py`
- New `audit.py` module; `audit_log()` wired on user deletion (self + admin), family removal, role change, file delete, storage format

### ✅ TASK-L5: File Listing Cache Server-Side *(DONE)*
**Files:** `backend/app/routes/file_routes.py`
- `_scan_cache` dict with 7s TTL; `_invalidate_scan_cache()` called on delete/rename/upload/mkdir

---

## Existing Tasks (Carried Forward)

### From previous TASKS.md — still relevant:

- **Telegram large file receive (Task 13)** — Enable file receive up to 2 GB via Telegram Local Bot API server
- **Fix deploy.sh health check** — `curl` against self-signed cert fails
- **OTA firmware update** — `POST /api/v1/system/update` is a stub
- **Auto AP fallback** — `auto_ap.py` needs integration testing
- **Cursor-based pagination** — Current offset pagination lacks sort stability
- **Incremental document indexing** — FTS5 re-scan is O(library size) on startup

---

## Done (Recent)

- [x] **Backend bring-up on Rock Pi 4A** (2026-03-15)
- [x] **Telegram approval flow (Task 9)** (2026-03-15)
- [x] **Timing-safe pairing comparison** — `hmac.compare_digest()` for serial/key (2026-03-16)
- [x] **friendlyError in services toggle** (2026-03-16)
- [x] **Family dialog error handling** — try/catch with friendlyError (2026-03-16)
- [x] **Revoked token cleanup** — purge_expired_tokens now cleans revoked tokens (2026-03-16)
- [x] **Trash overhaul** (2025-07-25)
- [x] **v5 Sprint Tasks 0–7** (2025-07-25)
- [x] **asyncio.Lock migration** (2025-07-25)
- [x] **bcrypt offloading** (2025-07-25)
- [x] **Profile edit** (2025-07-25)
- [x] **Emoji avatar system** (2025-07-25)
- [x] **KB rebuild** (2025-07-25)
