# AiHomeCloud — Task Tracker v3.0
> **Source of truth.** Follows MASTER_PROMPT.md v3 phases.
> Statuses: `⬜ todo` · `🔄 in-progress` · `✅ done` · `⏸ blocked`
> Last updated: March 2026

---

## Inherited from v2 (all ✅ complete — DO NOT REDO)

- Phases 1–8 complete: security, core features, upload UX, 4-tab nav,
  trash, auto-sort, document index, Telegram bot, AdGuard, testing,
  board abstraction, refresh tokens, TLS pinning, structured logging.

---

## Phase DRIVE — Drive UX Overhaul
> User's #1 request. Start here. Do not skip.

---

### TASK-DRIVE-01 — Group partitions by disk in build_device_list()
**Priority:** 🔴 Critical
**Status:** ✅ done
**Phase:** DRIVE
**Files:** `backend/app/routes/storage_helpers.py`, `backend/app/models.py`
**Depends on:** none

**Goal:**
`build_device_list()` currently returns one `StorageDevice` per partition
(e.g. sda1, sda2). Users see `/dev/sda1` which is meaningless to them.
Change it to return one entry per physical disk, with the best usable
partition resolved internally. Add `best_partition` field to the model
so the Flutter UI can call smart-activate with the right target.

**Acceptance criteria:**
- [ ] `StorageDevice` model gets new field: `displayName: str`
  (computed from model/size/transport, no /dev/ paths)
- [ ] `build_device_list()` returns ONE entry per physical disk
  (not per partition)
- [ ] Each entry's `path` is the disk path (e.g. `/dev/sda`) not partition
- [ ] `best_partition` field: path of the best usable partition, or None
- [ ] OS disks still filtered out
- [ ] `test_storage.py` tests still pass
- [ ] `pytest -q tests/` passes

**Implementation notes:**
Group `flatten_devices()` output by parent disk name (strip trailing digits).
`_display_name(disk)` → model + size + transport label, no /dev/ path.
Keep `flatten_devices()` unchanged — grouping happens in `build_device_list()`.

---

### TASK-DRIVE-02 — Add POST /api/v1/storage/smart-activate
**Priority:** 🔴 Critical
**Status:** ✅ done
**Phase:** DRIVE
**Files:** `backend/app/routes/storage_routes.py`, `backend/app/routes/storage_helpers.py`, `backend/app/models.py`
**Depends on:** TASK-DRIVE-01

**Goal:**
Single endpoint that hides all partition complexity. Flutter calls this
with a whole disk path. The backend detects what state the drive is in
and does the right thing: mount if ready, format-then-mount if not.

**Acceptance criteria:**
- [ ] `SmartActivateRequest` model: `{device: str}` (whole disk, e.g. /dev/sda)
- [ ] `POST /api/v1/storage/smart-activate` registered in storage_routes.py
- [ ] State A (has ext4 partition): mounts it, returns `action: "mounted"`
- [ ] State B/C (no ext4 / unpartitioned): starts format job, returns
  `action: "formatting", jobId: "..."` — job does mkfs.ext4 then mount
- [ ] State D (already active): returns `action: "already_active"` idempotent
- [ ] Response always includes `display_name` (human-friendly, no /dev/ paths)
- [ ] Requires `require_admin`
- [ ] All existing endpoints (`/format`, `/mount`) unchanged
- [ ] New test: `test_smart_activate_already_active_returns_200()`
- [ ] New test: `test_smart_activate_nonexistent_returns_404()`
- [ ] `pytest -q tests/` passes

**Implementation notes:**
See MASTER_PROMPT.md "Smart-Activate Implementation Guide" for full sketch.
`_smart_format_and_mount()` async job:
  1. `sgdisk -Z /dev/sda && sgdisk -n 1:0:0 -t 1:8300 /dev/sda` — GPT + partition
  2. Wait 2s for udev to settle
  3. `mkfs.ext4 -F -L AiHomeCloud /dev/sda1`
  4. Mount `/dev/sda1` at `settings.nas_root`
  5. `post_mount_setup()` — create dirs, start services
  6. Update job to completed
Use `settings.nas_root` not hardcoded path. Use `run_command()`.

---

### TASK-DRIVE-03 — Flutter: One-drive-one-card StorageExplorerScreen
**Priority:** 🔴 Critical
**Status:** ✅ done
**Phase:** DRIVE
**Files:** `lib/screens/main/storage_explorer_screen.dart`, `lib/services/api/storage_api.dart`, `lib/models/storage_models.dart`
**Depends on:** TASK-DRIVE-01, TASK-DRIVE-02

**Goal:**
Rewrite the storage explorer screen so each physical drive shows as one
card. No partition names. No /dev/ paths. One clear action button per drive.

**Acceptance criteria:**
- [ ] `StorageDevice` Dart model updated with `displayName` field
- [ ] `storage_api.dart` calls `/smart-activate` not separate format+mount
- [ ] Each drive shown as ONE card with `displayName` as title
- [ ] Active drive card: green "✓ Active Storage" badge + "Safely Remove" button
- [ ] Ready drive card (has ext4): "Activate" button → calls smart-activate
- [ ] Unready drive card: "Prepare as Storage" button → warning dialog → smart-activate
- [ ] No card shows: /dev/ paths, fstype, partition names, "Unformatted"
- [ ] Busy state: spinner replaces button, "Working…" subtitle
- [ ] After smart-activate (mounting): success snackbar "Storage activated!"
- [ ] After smart-activate (formatting job): poll job → "Preparing your drive…"
  progress card with elapsed time in MM:SS → on complete "Storage ready!"
- [ ] OS disks NOT shown at all (hidden, not greyed out)
- [ ] `flutter analyze` zero new errors
- [ ] `flutter test --exclude-tags golden` passes

**Implementation notes:**
Keep `_showSafeRemoveSheet()` and `_unmountDevice()` flows unchanged.
Keep the scan FAB unchanged.
The "Prepare as Storage" warning dialog text:
  Title: "Prepare this drive?"
  Body: "This will erase all files on [displayName] and set it up for
        AiHomeCloud. This cannot be undone."
  Button: "Prepare" (not "Format")

---

### TASK-DRIVE-04 — Remove technical format dialog, simplify confirm
**Priority:** 🟠 High
**Status:** ✅ done
**Phase:** DRIVE
**Files:** `lib/screens/main/storage_explorer_screen.dart`
**Depends on:** TASK-DRIVE-03

**Goal:**
The current format dialog asks the user to type `/dev/sda1` to confirm.
This is a developer confirmation pattern copied from GitHub, not a consumer
product pattern. Replace with a two-tap confirm dialog.

**Acceptance criteria:**
- [ ] No "Volume label" text field anywhere in the UI
- [ ] No "Type /dev/xxx to confirm" pattern anywhere
- [ ] Confirm is a standard AlertDialog: title "Prepare [displayName]?"
  with Cancel / Prepare buttons
- [ ] Backend still receives a label — hardcode to "AiHomeCloud" in the API call
  (user never sees it)
- [ ] `flutter analyze` zero new errors

---

### TASK-DRIVE-05 — Audit all storage error messages for technical terms
**Priority:** 🟡 Medium
**Status:** ✅ done
**Phase:** DRIVE
**Files:** `lib/core/error_utils.dart`, `lib/screens/main/storage_explorer_screen.dart`
**Depends on:** TASK-DRIVE-03

**Goal:**
Grep the Flutter codebase for technical storage terms that may still
appear in error messages and user-facing strings. Replace all of them.

**Acceptance criteria:**
- [ ] Zero occurrences of "mount" in user-visible strings (except "Safely Remove")
- [ ] Zero occurrences of "/dev/" in user-visible strings
- [ ] Zero occurrences of "ext4", "exFAT", "NTFS", "fstype" in UI strings
- [ ] Zero occurrences of "NAS" in user-visible strings
- [ ] Zero occurrences of "partition" in user-visible strings
- [ ] `friendlyError()` handles HTTP 409 from storage as
  "Another drive is already active. Safely remove it first."
- [ ] `friendlyError()` handles HTTP 500 from storage as
  "Could not activate drive. Check the USB connection and try again."
- [ ] `flutter analyze` zero new errors

---

### TASK-DRIVE-06 — Tests for smart-activate all 4 states
**Priority:** 🟡 Medium
**Status:** ✅ done
**Phase:** DRIVE
**Files:** `backend/tests/test_storage.py`
**Depends on:** TASK-DRIVE-02

**Goal:**
Add mocked unit tests for all 4 smart-activate states. Tests must not
require real hardware — mock lsblk output and subprocess calls.

**Acceptance criteria:**
- [ ] `test_smart_activate_already_active_is_idempotent()` — mocks storage
  state as active, verifies 200 + action=already_active
- [ ] `test_smart_activate_ext4_partition_mounts_without_format()` — mocks
  lsblk showing ext4 partition, verifies mount called, no mkfs
- [ ] `test_smart_activate_unformatted_starts_format_job()` — mocks lsblk
  showing no partition, verifies jobId returned
- [ ] `test_smart_activate_os_disk_blocked()` — mocks mmcblk device,
  verifies 403
- [ ] `test_smart_activate_nonexistent_device_returns_404()`
- [ ] `pytest -q tests/` passes

---

## Phase CI — CI Green

---

### TASK-CI-01 — Ignore hardware tests in CI workflow
**Priority:** 🔴 Critical
**Status:** ⬜ todo
**Phase:** CI
**Files:** `.github/workflows/backend-tests.yml`
**Depends on:** none

**Goal:**
Hardware integration tests require a real device. They should never run
in GitHub Actions. Currently they rely on pytestmark skipif which is fragile.

**Acceptance criteria:**
- [ ] `pytest -q tests/ --ignore=tests/test_hardware_integration.py`
  in the CI workflow
- [ ] CI backend-tests job passes on push
- [ ] `test_hardware_integration.py` unchanged (still runnable on device)

---

### TASK-CI-02 — Remove 500 from all test status_code assertions
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** CI
**Files:** `backend/tests/test_storage.py`, `backend/tests/test_endpoints.py`, `backend/tests/test_file_routes.py`
**Depends on:** none

**Goal:**
A 500 response is always a server crash. No test should treat it as an
acceptable outcome. Find and fix every assertion that includes 500 in
its accepted set.

**Acceptance criteria:**
- [ ] `grep -rn "500" backend/tests/` returns zero results where 500
  appears in an `assert status_code in (...)` list
- [ ] Each fixed test has a comment explaining the valid expected codes
- [ ] `pytest -q tests/` passes

---

### TASK-CI-03 — Fix pytest-asyncio scope mismatch
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** CI
**Files:** `backend/requirements.txt`, `backend/tests/conftest.py`
**Depends on:** none

**Goal:**
`event_loop` is `scope="session"` but `client` is `scope="function"`.
This causes intermittent "event loop closed" test failures. Upgrade
pytest-asyncio and fix the scope.

**Acceptance criteria:**
- [ ] `pytest-asyncio==0.23.8` in requirements.txt (was 0.22.0)
- [ ] `event_loop` fixture changed to `scope="function"` in conftest.py
  OR removed entirely (0.23.x auto-provides it)
- [ ] All tests in `pytest -q tests/ --ignore=tests/test_hardware_integration.py`
  pass with zero "event loop is closed" warnings

---

### TASK-CI-04 — Skip golden tests in Flutter CI
**Priority:** 🟠 High
**Status:** ⬜ todo
**Phase:** CI
**Files:** `.github/workflows/flutter-analyze.yml`, `test/widgets/app_card_test.dart`, `test/widgets/stat_tile_test.dart`, `test/widgets/storage_donut_chart_test.dart`
**Depends on:** none

**Goal:**
Golden pixel tests fail on Linux CI because font rendering differs from
local machines. Mark them with a tag and exclude from CI.

**Acceptance criteria:**
- [ ] Each golden test file has `@Tags(['golden'])` on the test group
- [ ] Flutter CI command changed to `flutter test --exclude-tags golden`
- [ ] CI flutter-analyze job passes
- [ ] Golden tests still runnable locally: `flutter test --tags golden`

---

### TASK-CI-05 — Rewrite dashboard_screen_test.dart
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** CI
**Files:** `test/screens/dashboard_screen_test.dart`
**Depends on:** none

**Goal:**
The current file creates a fake `DashboardScreen` class inline and tests
that. It catches zero real bugs. Rewrite to test the real widget with
mocked Riverpod providers so regressions are actually caught.

**Acceptance criteria:**
- [ ] Test file imports real `DashboardScreen` from `lib/screens/main/`
- [ ] Uses `ProviderScope` with overrides to inject mock `ApiService`
- [ ] Tests: loading state shows CircularProgressIndicator
- [ ] Tests: error state shows error text (not crash)
- [ ] Tests: data state renders without exception
- [ ] `flutter test --exclude-tags golden` passes

---

## Phase FLUTTER — Remaining Flutter Unit Tests

---

### TASK-P7-01 — ApiService unit tests
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** FLUTTER
**Files:** `test/services/api_service_test.dart` (new)
**Depends on:** none

**Goal:**
Unit tests for key `ApiService` methods using a mock HTTP client.
Tests must catch JSON deserialization regressions.

**Acceptance criteria:**
- [ ] `http_mock_adapter` or `mocktail` added to dev_dependencies in pubspec.yaml
- [ ] `test_list_files_deserializes_response_correctly()` — verifies
  `FileListResponse` (items + totalCount) from mock JSON
- [ ] `test_get_storage_stats_returns_model()` — verifies `StorageStats` fields
- [ ] `test_list_files_sends_correct_query_params()` — verifies page/pageSize
- [ ] `test_upload_file_returns_file_info()` — verifies upload response model
- [ ] `flutter test --exclude-tags golden` passes

---

### TASK-P7-02 — AuthSession & ConnectionNotifier tests
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** FLUTTER
**Files:** `test/services/auth_session_test.dart` (new)
**Depends on:** none

**Goal:**
Test the state machines that control authentication and connection status.
These are critical paths that currently have zero test coverage.

**Acceptance criteria:**
- [ ] `test_login_sets_all_session_fields()` — after login(), verifies
  token, username, isAdmin are set
- [ ] `test_logout_clears_all_fields()` — after logout(), all fields null
- [ ] `test_connection_notifier_grace_period()` — uses FakeAsync to verify
  state does NOT emit `disconnected` within first 9 seconds of failure
- [ ] `flutter test --exclude-tags golden` passes

---

## Phase POLISH — UX Language & Small Fixes

---

### TASK-POL-01 — Dashboard: Active storage badge in health row
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** POLISH
**Files:** `lib/screens/main/dashboard_screen.dart`
**Depends on:** TASK-DRIVE-01

**Goal:**
The dashboard health row currently shows a raw GB number for storage.
When a drive is active, show a green "⚡ Active" badge with drive's
displayName so users feel confident the storage is working.

**Acceptance criteria:**
- [ ] If storage device is active: shows "⚡ [displayName] · X GB free"
- [ ] If no storage device: shows "No drive connected" with amber color
- [ ] No /dev/ paths, no "NAS", no filesystem terms
- [ ] `flutter analyze` zero new errors

---

### TASK-POL-02 — Upload sort feedback: "Sorted to Photos"
**Priority:** 🟡 Medium
**Status:** ⬜ todo
**Phase:** POLISH
**Files:** `lib/screens/main/files_screen.dart`, `lib/screens/main/my_folder_screen.dart`
**Depends on:** none

**Goal:**
After upload, the snackbar currently says "Uploaded". Change it to
reflect where the file was auto-sorted. The backend already returns
the destination path in the upload response.

**Acceptance criteria:**
- [ ] Upload response includes `sortedTo` field (if auto-sorted)
- [ ] Snackbar shows: "📸 Sorted to Photos" / "📄 Sorted to Documents"
  / "🎬 Sorted to Videos" / "✅ Uploaded"
- [ ] Falls back to "✅ Uploaded" if sortedTo is absent
- [ ] `flutter analyze` zero new errors

**Backend note:**
`file_routes.py` upload endpoint should include `sortedTo` in response
if the file was auto-sorted by InboxWatcher. Can be done via a short
poll (500ms) or by triggering sort inline and returning the result.

---

### TASK-POL-03 — Format progress: human-friendly text
**Priority:** 🟢 Low
**Status:** ⬜ todo
**Phase:** POLISH
**Files:** `lib/screens/main/storage_explorer_screen.dart`
**Depends on:** TASK-DRIVE-03

**Goal:**
The format progress card currently shows "Status: running • Elapsed: 0:23"
which is developer text. Replace with warm, friendly messaging.

**Acceptance criteria:**
- [ ] Progress card shows: "Preparing your storage drive…"
- [ ] Subtext: "This takes about 2 minutes. Please keep the app open."
- [ ] Elapsed time shown as "1 min 23 sec" not "1:23"
- [ ] On complete: brief success animation → "Storage is ready! X GB available"
- [ ] `flutter analyze` zero new errors

---

### TASK-POL-04 — Full language audit: grep for technical terms in UI
**Priority:** 🟢 Low
**Status:** ⬜ todo
**Phase:** POLISH
**Files:** All Flutter files under `lib/`
**Depends on:** TASK-DRIVE-05

**Goal:**
Final pass to ensure no technical terms reach the user. Run grep
and fix every remaining instance.

**Acceptance criteria:**
- [ ] `grep -rn "NAS\|Samba\|DLNA\|ext4\|exFAT\|NTFS\|/dev/\|mount\|unmount\|partition\|fstype" lib/` returns zero results (except in comments)
- [ ] All remaining cases replaced per the Language Rules table
- [ ] `flutter analyze` zero new errors
- [ ] `flutter test --exclude-tags golden` passes

---

## Phase FUTURE — Post-Release Features
> Do NOT start until Phases DRIVE, CI, FLUTTER, POLISH are all ✅ done.

---

### TASK-P8-01 — Remote Access via Tailscale
**Priority:** 🟢 Low
**Status:** ⬜ todo
**Phase:** FUTURE
**Files:** Multiple
**Depends on:** Phase POLISH complete

**Goal:**
Allow remote file access via Tailscale. Zero-config for users — install
Tailscale on phone and Cubie, toggle in app.

**Acceptance criteria:**
- [ ] "Remote Access" section in More tab with Tailscale toggle
- [ ] Tailscale IP stored in SharedPreferences
- [ ] ApiService fallback: LAN first (2s timeout), then Tailscale IP
- [ ] Connection mode indicator ("via Home Network" vs "via Remote")
- [ ] `GET /api/v1/system/tailscale-status` endpoint
- [ ] `POST /api/v1/system/tailscale-up` (admin only)

---

### TASK-P8-02 — Internal Event Bus
**Priority:** 🟢 Low
**Status:** ⬜ todo
**Phase:** FUTURE
**Files:** `backend/app/events.py` (new)
**Depends on:** Phase POLISH complete

**Goal:**
Async publish/subscribe event bus for future AI features (auto-tagging,
smart search). Foundation only — no UI changes.

**Acceptance criteria:**
- [ ] `EventBus` class with subscribe() and publish()
- [ ] `FileEvent` dataclass: path, action, user, timestamp
- [ ] Wire upload and delete routes to publish events
- [ ] In-memory circular buffer (last 1000 events)

---

### TASK-P8-03 — SQLite Schema for File Index (Feature Flagged)
**Priority:** 🟢 Low
**Status:** ⬜ todo
**Phase:** FUTURE
**Files:** `backend/app/config.py`, `backend/app/db_stub.py` (new)
**Depends on:** Phase POLISH complete

**Goal:**
Feature-flagged SQLite schema preparation. Off by default.

**Acceptance criteria:**
- [ ] `enable_sqlite: bool = False` in config.py
- [ ] `db_stub.py` creates `file_index` and `ai_jobs` tables if flag=True
- [ ] Zero impact when flag is False

---

## Task Count Summary

| Phase | Total | Done | Todo |
|---|---|---|---|
| DRIVE | 6 | 6 | 0 |
| CI | 5 | 0 | 5 |
| FLUTTER | 2 | 0 | 2 |
| POLISH | 4 | 0 | 4 |
| FUTURE | 3 | 0 | 3 |
| **Total** | **20** | **6** | **14** |

Previous v2 tasks: 27 done, 5 todo (P7-01, P7-02 migrated above; P8 migrated above)
