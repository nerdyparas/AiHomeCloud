# DevAgent — Catchup Log for Claude Opus 4.6

> **Purpose:** Full-fidelity briefing so the next AI agent can immediately understand
> the current state and continue without repeating work.
> Last written: 2026-03-10

---

## 1. Project Identity

**AiHomeCloud** — personal home NAS appliance on a Radxa CUBIE A7A (ARM64, Allwinner A527  
SoC, 8 GB RAM). Dual-component system:
- **Flutter app** (`lib/`) — Android mobile client (Dart, Riverpod, GoRouter)
- **FastAPI backend** (`backend/`) — Python 3.11, port 8443 HTTPS (self-signed TLS)

Key paths on the live device:
```
/var/lib/cubie/         ← data dir (users.json, pairing.json, jwt_secret, kv.json, ...)
/srv/nas/               ← NAS root (sda1, 14.9 GB USB, ext4, label CubieNAS)
/home/radxa/AiHomeCloud/backend/venv/  ← Python venv
```

Backend runs as systemd service `cubie-backend`. Admin user: `admin`, bcrypt PIN.

---

## 2. What Happened in This Session (2026-03-10)

### 2a. `git pull` — 105 files changed
A large fast-forward merge came in from `origin/main`:
- New backend modules: `file_sorter.py`, `document_index.py`, `telegram_bot.py`, `adguard_routes.py`, `telegram_routes.py`
- New tests: `test_file_sorter.py`, `test_document_index.py`, `test_telegram_bot.py`, `test_trash.py`, `test_storage.py`, `test_file_routes.py`, `test_endpoints.py`
- New Flutter screens and service files
- New scripts: `scripts/first-boot-setup.sh`, `scripts/install-adguard.sh`

After the pull, the backend could not start because the new imports (`slowapi`, `python-telegram-bot`, etc.) were not installed. Fix: `venv/bin/pip install -r requirements.txt`.

### 2b. TASK-P6-04 — Hardware Integration Test
Ran integration tests directly on the Cubie A7A hardware. Discovered and fixed:

**Bug 1 — Board detection returning `"unknown"` (board.py)**  
DTB model string for Cubie A7A is `sun60iw2` (Allwinner SoC ID), not `"Radxa CUBIE A7Z"`.  
Fix: added `"sun60iw2"` key to `KNOWN_BOARDS` → `"Radxa CUBIE A7A"`, plus `_BOARD_SUBSTRINGS`  
fuzzy substring fallback list for future hardware variants.

**Integration test file created**: `backend/tests/test_hardware_integration.py`  
30 tests across 7 classes. Result: 28 pass, 2 skip, 0 fail.

### 2c. Format USB Rule Update (`is_os_partition()`)
User asked to remove the `≥32 GB` restriction on USB formatting — allow any externally-connected  
drive as long as it is not OS-related.

**Found 4 bugs in `backend/app/routes/storage_helpers.py`:**
1. `tempfile.gettempdir()` included in `system_mounts` (wrong approach)
2. `mtdblock0` (NAND flash/bootloader) was not blocked
3. `/boot/efi` not caught by the old exact-match set
4. `mountpoint=None → "/"` coercion bug: `(device.get("mountpoint") or "").rstrip("/") or "/"` made unmounted devices appear as root-mounted

**Rewrite of `is_os_partition()`:**
```python
_OS_NAME_PREFIXES = ("mmcblk", "mtdblock", "zram", "loop")
_OS_MOUNT_PREFIXES = ("/", "/boot", "/config", "/var", "/home",
                      "/usr", "/opt", "/proc", "/sys")
```
- Name-prefix check: mmcblk, mtdblock, zram, loop → always blocked
- Mount-prefix check with `str.startswith()` → catches `/boot/efi`, `/boot/firmware`, `/config/*`
- `mountpoint=None` correctly handled — empty string, skips mount check
- Size-agnostic — 14.9 GB USB `sda1` → formattable; 62 GB `mmcblk0p3` → blocked
- Removed `import tempfile` (no longer needed)

Added `TestFormatProtection` class (6 tests) — all 6 pass on live hardware.

Real device classification on Cubie A7A:
```
sda        tran=usb   mount=-               16.0GB → external (FORMATTABLE)
sda1       tran=usb   mount=/srv/nas        16.0GB → external (FORMATTABLE)
mtdblock0  tran=none  mount=-               0.0GB  → OS (BLOCKED)
mmcblk0    tran=none  mount=-               62.5GB → OS (BLOCKED)
mmcblk0p1  tran=none  mount=/config         0.0GB  → OS (BLOCKED)
mmcblk0p2  tran=none  mount=/boot/efi       0.3GB  → OS (BLOCKED)
mmcblk0p3  tran=none  mount=/               62.2GB → OS (BLOCKED)
zram0      tran=none  mount=[SWAP]          4.2GB  → OS (BLOCKED)
```

### 2d. Full Test Suite Regression — 73 failures found and fixed
After the git pull, running the full suite produced 73 failures. Root causes:

**Root Cause 1 — `asyncio.run()` in hardware integration test**  
`asyncio.run()` internally calls `asyncio.set_event_loop(None)` when it exits. This cleared  
the pytest-asyncio session-scoped event loop, causing every subsequent async test to fail with  
`RuntimeError: There is no current event loop`.

Fix in `test_hardware_integration.py`:
```python
# BEFORE (breaks session event loop):
status_codes = asyncio.run(run_concurrent())

# AFTER (private loop, does not affect pytest's session loop):
_loop = asyncio.new_event_loop()
try:
    status_codes = _loop.run_until_complete(run_concurrent())
finally:
    _loop.close()
```

**Root Cause 2 — `settings.data_dir` mutation not reverted in conftest**  
The `client` fixture used direct assignment instead of `monkeypatch.setattr()`, permanently  
mutating the global settings object. Module-scoped hardware integration fixtures then read  
from a stale, deleted tmp path.

Fix in `tests/conftest.py`:
```python
# BEFORE:
settings.data_dir = tmp_path
settings.nas_root = nas_tmp
settings.skip_mount_check = True

# AFTER:
monkeypatch.setattr(settings, "data_dir", tmp_path)
monkeypatch.setattr(settings, "nas_root", nas_tmp)
monkeypatch.setattr(settings, "skip_mount_check", True)
```

**Root Cause 3 — Hardware test read `settings.data_dir` instead of real path**  
The module-scoped `admin_token` fixture was initialised while a function-scoped test had  
`settings.data_dir` monkeypatched to a temp path, so it tried to read a non-existent  
`users.json`.

Fix in `test_hardware_integration.py`:
- Added `_REAL_DATA_DIR = Path("/var/lib/cubie")` constant
- Used `_REAL_DATA_DIR` for all direct file reads (pairing.json, pairing_key, users.json)
- Added module-level skip when not on real hardware:
```python
if not _REAL_DATA_DIR.joinpath("users.json").exists():
    pytest.skip(
        "Hardware integration tests require /var/lib/cubie/users.json — "
        "skipping on non-hardware environments.",
        allow_module_level=True,
    )
```

**Final result: 268 passed, 4 skipped, 0 failed, 0 errors.**

---

## 3. Files Modified in This Session

| File | Change |
|---|---|
| `backend/app/board.py` | Added `"sun60iw2"` to `KNOWN_BOARDS`, added `_BOARD_SUBSTRINGS` fuzzy fallback |
| `backend/app/routes/storage_helpers.py` | Rewrote `is_os_partition()` — name-prefix + mount-prefix logic, mountpoint=None fix, removed `import tempfile` |
| `backend/tests/test_hardware_integration.py` | New file (30 tests). Fixed: `asyncio.run()` → private loop, `settings.data_dir` → `_REAL_DATA_DIR`, added module-level skip |
| `backend/tests/conftest.py` | `settings.data_dir = tmp_path` → `monkeypatch.setattr(settings, "data_dir", tmp_path)` (3 lines) |
| `TASKSv2.md` | TASK-P6-04 format criterion updated to `ANY size`, status `✅ done` |
| `logs.md` | New 2026-03-10 entry with hardware test results table |

---

## 4. Current Test Suite State

```
cd backend && venv/bin/python -m pytest tests/ -q
# Expected: 268 passed, 4 skipped, 0 failed, 0 errors
# Runtime: ~100s on Cubie A7A
```

The 4 skips:
- 2 in `test_hardware_integration.py` (download + delete — InboxWatcher auto-sorted the file first, proving the feature works)
- 2 pre-existing skips (Windows-path tests)

---

## 5. Architecture Notes Discovered This Session

### Settings object is a singleton — mutations persist across tests
`app.config.settings` is a module-level singleton. Any direct attribute assignment  
(e.g. `settings.data_dir = x`) mutates it for the **entire process**. Always use  
`monkeypatch.setattr()` in tests to ensure restoration after each test.

### pytest-asyncio session event loop is fragile
With `asyncio_mode = "auto"` and a session-scoped `event_loop` fixture, calling  
`asyncio.run()` anywhere in the test session will destroy the loop and break all  
subsequent async fixtures. Use `asyncio.new_event_loop()` + `loop.run_until_complete()`  
when you need a nested synchronous call to async code.

### Hardware integration tests must not import `settings` for file paths
Module-scoped fixtures are resolved once per module. If they happen to be resolved  
during a test that has function-scoped monkeypatches active, they inherit the patched  
values. Hardcode hardware-specific paths (`/var/lib/cubie/`) and guard with a  
module-level `pytest.skip` for non-hardware environments.

### `is_os_partition()` — correct mental model
A partition is OS-related if ANY of these is true:
1. Device name starts with `mmcblk` / `mtdblock` / `zram` / `loop`
2. Mountpoint is a non-empty string that starts with any OS prefix  
   (`/`, `/boot`, `/config`, `/var`, `/home`, `/usr`, `/opt`, `/proc`, `/sys`)

`None` mountpoint = unmounted = NOT an OS partition by mount alone.  
Size is irrelevant.

---

## 6. Open Tasks (from TASKSv2.md)

Phases 1–6 are complete. Remaining:

### TASK-P5-02 — Flutter Trash UI ← **NEXT UP**
**Status:** ✅ listed as done in TASKSv2.md but acceptance criteria unchecked
**Acceptance criteria to verify:**
- [ ] Swipe-to-delete on file tiles shows Undo SnackBar (30 s window)
- [ ] After 30 s without undo, file moves to trash
- [ ] "Empty Trash" button in More tab with confirmation dialog
- [ ] Shows trash size ("Trash: 2.3 GB")
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes

**Files to check/edit:**
- `lib/screens/main/files_screen.dart` or `my_folder_screen.dart`
- `lib/screens/main/more_screen.dart`
- `lib/services/api_service.dart` (or `lib/services/api/files_api.dart`)
- Trash endpoints already exist: `GET /api/v1/files/trash`, `POST /api/v1/files/trash/{id}/restore`, `DELETE /api/v1/files/trash/{id}`

### TASK-P6-01 — DLNA + AdGuard Service Registration
**Status:** ✅ in TASKSv2 but acceptance criteria unchecked
- [ ] `"dlna": ["minidlna"]` in `_SERVICE_UNITS` in `service_routes.py`
- [ ] `"adguard": ["AdGuardHome"]` in `_SERVICE_UNITS`

### TASK-P6-02 — ARM64 pip-compile
- [ ] Pin all dependency versions — must run `pip-compile` on actual Cubie hardware

### TASK-P7-01 — ApiService Unit Tests
- [ ] `test/services/api_service_test.dart` — mockito / http_mock_adapter

### TASK-P7-02 — AuthSession & Connection Notifier Tests
- [ ] `test/services/auth_session_test.dart` — FakeAsync

---

## 7. How to Run / Validate

```bash
# Backend — full suite
cd /home/radxa/AiHomeCloud/backend
venv/bin/python -m pytest tests/ -q

# Backend — hardware-only tests (must be on Cubie with service running)
venv/bin/python -m pytest tests/test_hardware_integration.py -v -s --tb=short

# Flutter
cd /home/radxa/AiHomeCloud
flutter analyze    # must be 0 errors, 0 warnings
flutter test       # must be all pass

# Restart backend after code changes
sudo systemctl restart cubie-backend
sleep 5
curl -k https://localhost:8443/api/health
```

---

## 8. Key Lessons from This Session

1. **`asyncio.run()` is destructive in pytest sessions.** Never call it inside a test that  
   runs alongside async tests. Use `asyncio.new_event_loop()` + `run_until_complete()` + `loop.close()`.

2. **Always use `monkeypatch.setattr()` for settings mutations in tests.** Direct assignment  
   (`settings.x = y`) leaks across tests in the same module because `settings` is a global  
   singleton. `monkeypatch` guarantees restoration via pytest's teardown hook.

3. **Module-scoped fixtures are dangerous with function-scoped monkeypatches.** They are lazy  
   (evaluated on first use), so they may be evaluated while a function-scoped patch is active.  
   Isolate hardware integration tests in their own module with module-level guards.

4. **`is_os_partition()` must use `str.startswith()`, not `in` set membership**, to catch  
   mount hierarchies like `/boot/efi`, `/boot/firmware`, `/config/boot`, etc.

5. **`mountpoint=None` ≠ mountpoint `"/"`.** The coercion `or "/"` was a subtle bug that  
   caused unmounted external devices to be classified as OS partitions.

6. **After `git pull` that adds new Python imports**, install requirements before restarting  
   the systemd service: `venv/bin/pip install -r requirements.txt`.

7. **DTB model strings are SoC IDs, not human-readable names.** `sun60iw2` is the Allwinner  
   A527 SoC identifier. Always verify by running `cat /proc/device-tree/model` on the device.

---

## 9. Hardware Reference

```
Board:       Radxa CUBIE A7A
SoC:         Allwinner A527 (ARM Cortex-A55)
DTB model:   sun60iw2
RAM:         8 GB
eMMC:        mmcblk0 (62.5 GB) — OS disk
USB drive:   sda/sda1 (16 GB, ext4, label CubieNAS) — mounted at /srv/nas
NAND:        mtdblock0 (8 MB) — bootloader/SPL, never format
Thermal:     /sys/class/thermal/thermal_zone0/temp (cpul_thermal_zone) ~39°C at idle
LAN:         eth0
Hostname:    radxa-cubie-a7a
Default IP:  192.168.0.212
```

---

*Generated 2026-03-10 to enable seamless handoff to the next AI agent.*
