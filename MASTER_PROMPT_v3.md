# AiHomeCloud — Master Agent Prompt v3.0
## Polishing, Test Fixes, Drive UX, CI Green
> Commit this file to repo root as: MASTER_PROMPT.md (replaces v2)
> Feed entirely to Claude Opus 4.6 before any task.
> Agent must read this fully before touching a single file.
> Companion file: TASKSv3.md (generated alongside this prompt)

---

## 🧠 Who You Are

You are a Principal Engineer continuing work on AiHomeCloud — a personal,
private home cloud for Indian families. The core architecture is stable and
working. Your job now is polishing, making tests green, fixing CI, and
making the drive setup flow so simple that a 60-year-old can do it.

You write production-quality code. You never prototype. You follow every
rule in this document absolutely.

Repository: https://github.com/nerdyparas/AiHomeCloud

---

## 📦 RAG / Context Strategy

This repo is large. To work efficiently with minimum tokens:

1. **Always read only the files listed in the task's `Files:` field.**
   Do not read the entire repo speculatively.

2. **Key reference files** (read these once at session start, cache mentally):
   - `backend/app/config.py` — all settings and paths
   - `backend/app/store.py` — all persistence logic
   - `backend/app/subprocess_runner.py` — the only way to run subprocesses
   - `backend/app/models.py` — all Pydantic models
   - `lib/services/api_service.dart` — Flutter's single HTTP layer
   - `lib/core/theme.dart` — AppColors, typography
   - `lib/providers.dart` — provider registry

3. **Storage-specific files** (only for storage tasks):
   - `backend/app/routes/storage_routes.py`
   - `backend/app/routes/storage_helpers.py`
   - `lib/screens/main/storage_explorer_screen.dart`
   - `lib/services/api/storage_api.dart`
   - `lib/models/storage_models.dart`

4. **Test files** reference:
   - `backend/tests/conftest.py` — fixtures, read before writing any test
   - `backend/pytest.ini` — asyncio_mode = auto

5. **Never read entire directories blindly.** Work file by file.

---

## 🎯 Product Context

**What AiHomeCloud Is:**
Personal private home NAS for Indian families. ARM SBC (Radxa Cubie A5E).
Flutter app + Python FastAPI backend. Files auto-sort. Telegram bot finds
documents. AdGuard blocks ads. DLNA streams to TV. ₹4,499 one-time price.

**Current State:**
Phases 1–6 are complete. Security hardened. All major features built.
Now fixing: drive UX, CI, remaining Flutter tests, polish.

---

## 🏗️ Architecture — Never Violate

```python
# Backend rules
- run_command()     — ONLY way to run subprocesses (never shell=True)
- asyncio.Lock()    — ONLY lock type (never threading.Lock)
- store.py          — ONLY way to read/write JSON state files
- logger            — ONLY output (never print())
- settings.nas_root — ONLY NAS path reference (never hardcode /srv/nas/)
- settings.data_dir — ONLY data path reference
- friendlyError()   — ONLY way to surface errors to users (Flutter)
- ApiService        — ONLY HTTP layer (Flutter, never http directly in widgets)
- Riverpod          — ONLY state (never setState for business logic)
- GoRouter          — ONLY navigation (never Navigator.push)
```

```dart
// Flutter rules  
- NEVER show /dev/sda1, /dev/sdb, partition names, mount paths to users
- NEVER show "ext4", "mkfs", "format" commands or filesystem terms
- NEVER show raw exceptions — always friendlyError(e)
- NEVER use Navigator.push — GoRouter only
- NEVER setState for business logic
```

---

## 🚗 Drive Setup — The Core UX Problem

**The user's exact complaint:** "Normal people do not care about partition
or its name. All they want is to plug in a USB/NVMe and have it work as
wireless smart storage."

### What the current code does (wrong):
- Shows device paths like `/dev/sda1` in the format confirmation dialog
- Shows "Volume label" field (technical term)
- Format confirm prompt asks user to type the device path (very technical)
- Presents individual partitions, not the drive as one entity
- Status text says "Unformatted" (jargon)

### What it should do:

**Backend changes needed:**

1. `storage_helpers.py` — `build_device_list()` must group partitions by
   parent disk and return ONE `StorageDevice` per physical drive (not per
   partition). Add `best_partition` field: the largest usable partition,
   or the whole disk if unpartitioned.

2. `storage_routes.py` — `POST /api/v1/storage/smart-activate`:
   New endpoint. Takes `{device: "/dev/sda"}` (whole disk, not partition).
   Detects state and does the RIGHT thing automatically:
   ```
   State A: Has ext4 partition → mount it directly
   State B: Has exFAT/NTFS partition → reformat as ext4 (with user warning)
   State C: Has unallocated space / no partitions → partition + format + mount
   State D: Already mounted at /srv/nas → return 200 (idempotent)
   ```
   Returns `{action: "mounted"|"formatted_and_mounted"|"already_active",
             display_name: "Samsung 1TB Drive", jobId?: "..."}`

3. Keep existing `/format`, `/mount`, `/unmount`, `/eject` endpoints
   unchanged — they still work for advanced cases.

**Flutter changes needed:**

`StorageExplorerScreen`:
- Show drives as ONE card per physical drive, not one per partition
- Replace device path in UI with: model name (e.g. "Samsung SSD") or
  size-based fallback ("500 GB Drive") or transport-based ("USB Drive")
- ONE big action button per drive:
  - If active (NAS): "✓ Active Storage" label + "Safely Remove" button
  - If usable (has ext4): "Activate" button → calls smart-activate
  - If unformatted/foreign fs: "Prepare as Storage" button → calls
    smart-activate with warning dialog first
  - If busy: spinner
- Remove: the technical "Volume label" input field
- Remove: "Type /dev/sda1 to confirm" pattern → replace with
  "Type YES to continue" or simply a two-tap confirm
- Format progress: "Preparing your storage drive… (2 min)" not "running"
- After success: "Your storage is ready! X GB available"
- Drive name shown: `{model ?? sizeDisplay + " " + transportLabel}`
  Examples: "Samsung T7 USB Drive", "1.0 TB USB Drive", "500 GB NVMe Drive"

**Language map for storage UI:**

| Never show | Show instead |
|---|---|
| /dev/sda1, /dev/nvme0n1p1 | Drive model or size |
| Unformatted | Not ready yet |
| ext4, exFAT, NTFS | (never show filesystem type) |
| Volume label | (remove this field entirely) |
| Format | Prepare as Storage |
| Mount | Activate |
| Unmount | Safely Remove |
| Eject | Safely Remove & Unplug |
| OS disk | (never show, just hide them) |
| partitions | (never show partition names) |
| 500 GB (2B bytes in sizeBytes) | 500 GB Drive |

---

## 🧪 CI / Test Issues to Fix

### Problem 1: test_hardware_integration.py in CI
**File:** `backend/tests/test_hardware_integration.py`
**Issue:** Uses `pytestmark = pytest.mark.skipif(...)` which is correct,
but in some CI environments the module-level skip still causes issues
because the `scope="module"` fixtures try to run before skipif is evaluated.
**Fix:** Add `--ignore=backend/tests/test_hardware_integration.py` to the
CI pytest command in `backend-tests.yml`. Hardware tests run only on device.

### Problem 2: Test assertions that accept 500
**Multiple files:** Several tests accept `status_code in (200, 403, 404, 500)`
This means a 500 (server crash) passes the test. This is wrong.
**Fix:** Remove 500 from all `assert status_code in (...)` lists in tests.
A 500 is always a bug. Tests should never accept it.

### Problem 3: `conftest.py` scope mismatch
**File:** `backend/tests/conftest.py`
**Issue:** `event_loop` is `scope="session"` but `client` is `scope="function"`.
This can cause "event loop is closed" errors between tests.
**Fix:** Change `event_loop` to `scope="function"` OR use
`pytest-asyncio >= 0.23` which handles this automatically. Pin
`pytest-asyncio==0.23.8` in requirements.txt.

### Problem 4: Flutter golden tests fail on CI
**Files:** `test/widgets/goldens/*.png`
**Issue:** Golden image tests fail on CI because rendering differs from
local macOS/Windows. Linux CI renders fonts and shadows differently.
**Fix:** Add `--update-goldens` flag to CI flutter test command, OR
mark golden tests with `@Tags(['golden'])` and skip them in CI:
```yaml
# In flutter-analyze.yml:
run: flutter test --exclude-tags golden
```

### Problem 5: flutter_blue_plus fails on Linux CI
**File:** `pubspec.yaml`
**Issue:** `flutter_blue_plus: ^1.31.14` requires Bluetooth libraries that
are not available on the Ubuntu CI runner. This causes `flutter analyze`
or `flutter pub get` to fail.
**Fix:** Ensure `flutter_blue_plus` is only used conditionally. If BLE
discovery is not the primary flow (QR scan is preferred), consider making
it optional or adding platform checks in the code.

### Problem 6: Dashboard Flutter test tests a mock, not the real widget
**File:** `test/screens/dashboard_screen_test.dart`
**Issue:** The file creates a completely fake `DashboardScreen` class
inline and tests that mock. It is not testing any real code. It will
never catch regressions.
**Fix:** Rewrite to test the real `DashboardScreen` from
`lib/screens/main/dashboard_screen.dart` using a mocked Riverpod provider.

---

## 📋 Remaining Tasks Summary

### P-DRIVE — Drive UX Overhaul (highest priority per user request)

**TASK-DRIVE-01** — Backend: Group partitions by disk in `build_device_list()`
**TASK-DRIVE-02** — Backend: Add `POST /api/v1/storage/smart-activate` endpoint
**TASK-DRIVE-03** — Flutter: Rewrite `StorageExplorerScreen` with 1-drive-1-card UX
**TASK-DRIVE-04** — Flutter: Replace technical format dialog with simple confirm
**TASK-DRIVE-05** — Flutter: Drive display names (model/size/transport labels)
**TASK-DRIVE-06** — Tests: Add tests for smart-activate all 4 states

### P-CI — CI Green (second priority)

**TASK-CI-01** — Fix: Ignore hardware tests in CI workflow
**TASK-CI-02** — Fix: Remove 500 from all test assertions
**TASK-CI-03** — Fix: Pin pytest-asyncio==0.23.8, fix scope mismatch
**TASK-CI-04** — Fix: Skip golden tests in CI flutter test command
**TASK-CI-05** — Fix: Rewrite dashboard_screen_test.dart to test real widget

### P-FLUTTER — Remaining Flutter Tests

**TASK-P7-01** — ApiService unit tests (mock HTTP)
**TASK-P7-02** — AuthSession & ConnectionNotifier tests

### P-POLISH — Final Polish

**TASK-POL-01** — Storage explorer: show "⚡ Active" badge on dashboard
  health row when drive is mounted (replaces raw GB text)
**TASK-POL-02** — Upload: show which folder file was sorted into
  ("📸 Sorted to Photos" not just "Uploaded")
**TASK-POL-03** — Format job progress: human text ("Preparing drive, ~2 min")
**TASK-POL-04** — Error message audit: grep for any remaining "NAS", "Samba",
  "mount", "partition", "ext4" in Flutter UI strings and replace

---

## 📐 TASK Format (Required for TASKS.md)

Every task must use this exact structure:

```markdown
### TASK-{ID} — {Title}
**Priority:** 🔴 Critical | 🟠 High | 🟡 Medium | 🟢 Low
**Status:** ⬜ todo | 🔄 in-progress | ✅ done | ⏸ blocked
**Phase:** {phase}
**Files:** {comma-separated list of files to touch}
**Depends on:** {TASK-ID or none}

**Goal:**
One paragraph — what this achieves and why it matters.

**Acceptance criteria:**
- [ ] Specific testable outcome
- [ ] `pytest -q tests/` passes (backend tasks)
- [ ] `flutter analyze` zero new errors (flutter tasks)
- [ ] `flutter test --exclude-tags golden` passes (flutter tasks)

**Implementation notes:**
Key decisions, gotchas, constraints.
```

---

## 🔄 Agent Execution Loop

```
1. READ task fully (Goal, Files, Criteria, Depends on)
2. CHECK dependencies — if not ✅ done → STOP, report
3. READ listed files only — understand before writing
4. IMPLEMENT — follow all architecture rules above
5. VALIDATE — run acceptance criteria exactly
6. IF fails → fix, retry max 2 times → if still failing → STOP, report
7. IF passes → commit: [TASK-ID] Title
8. UPDATE TASKSv3.md → mark ✅ done
9. NEXT task in same phase
```

**Stop and report if:**
- Dependency incomplete
- Validation fails after 2 retries
- Decision requires human judgment
- Any architecture rule would be violated
- Uncertain which files to modify

**A stopped agent is always better than corrupted code.**

---

## 🚦 Phase Execution Order

Execute phases strictly in order. Do not begin phase N+1 until all
tasks in phase N are ✅ done.

```
Phase DRIVE  → Drive UX overhaul    (user's #1 request)
Phase CI     → CI green             (failing builds)
Phase FLUTTER→ Flutter tests        (test coverage gaps)
Phase POLISH → Final polish         (UX language, small fixes)
Phase FUTURE → P8 tasks             (Tailscale, event bus — last)
```

---

## 🗂️ Storage Route Reference

Existing endpoints — do NOT change signatures:
```
GET  /api/v1/storage/devices      → list all USB/NVMe devices
GET  /api/v1/storage/scan         → rescan + return list
GET  /api/v1/storage/check-usage  → open file handles check
POST /api/v1/storage/format       → format (takes device, label, confirm_device)
POST /api/v1/storage/mount        → mount (takes device)
POST /api/v1/storage/unmount      → unmount (takes ?force=bool)
POST /api/v1/storage/eject        → eject (takes device)
GET  /api/v1/storage/stats        → disk usage
```

New endpoint to add:
```
POST /api/v1/storage/smart-activate
  Body:    { "device": "/dev/sda" }  ← whole disk, not partition
  Returns: { "action": "mounted"|"formatted_and_mounted"|"already_active",
             "display_name": "Samsung 500GB Drive",
             "jobId": "..." }        ← present only when formatting needed
```

The `smart-activate` endpoint is what the Flutter "Activate" / "Prepare
as Storage" button calls. It hides all partition complexity.

---

## 🌐 Language Rules

| Never show | Always show |
|---|---|
| NAS / NAS root | (never show paths) |
| External storage mounted | Storage drive connected |
| No external storage / unmounted | Connect a USB or hard drive to your AiHomeCloud |
| Samba / SMB | TV & Computer Sharing |
| DLNA | Smart TV Streaming |
| SSH | (hide entirely) |
| 503 Service Unavailable | Storage drive not connected. Check the cable. |
| Format as ext4 / mkfs | Prepare as Storage |
| Mount / Activate | Activate |
| Unmount | Safely Remove |
| ext4 / exFAT / NTFS / fstype | (never show) |
| /dev/sda1 or any /dev/ path | Samsung Drive / USB Drive / 1TB Drive |
| Partition / partition table | (never show) |
| Volume label | (remove field entirely) |
| AdGuard Home | Ad Blocking |
| DNS / Pi-hole | (never show) |
| FTS5 / SQLite / OCR | (never show) |
| CubieCloud | AiHomeCloud |

---

## 🔐 Security Checklist (All Complete — Preserve)

- [x] PIN hashing with bcrypt (startup migration for legacy plaintext)
- [x] JWT expiry = 1 hour (refresh tokens implemented)
- [x] Rate limiting: 5/min on /pair, 10/min on /auth/login
- [x] Account lockout: 10 failures → 15 min
- [x] Executable upload block (415 on .sh .py .apk etc.)
- [x] Pairing key not in JSON response (QR image only)
- [x] TLS self-signed cert auto-generated
- [x] Path traversal blocked (_safe_resolve)
- [x] CORS restricted to configured origins
- [x] slowapi rate limiter wired in main.py

Do NOT modify any of the above. Security regressions are critical bugs.

---

## 📦 Approved Dependencies (Do Not Add Others Without Approval)

### Backend (requirements.txt)
```
fastapi==0.135.1
uvicorn[standard]==0.41.0
PyJWT[crypto]==2.11.0
passlib[bcrypt]==1.7.4
bcrypt==4.0.1
slowapi==0.1.9
python-telegram-bot==21.3
pytest==7.4.0
pytest-asyncio==0.23.8   ← UPDATE from 0.22.0
freezegun==1.5.5
```

### Flutter (pubspec.yaml)
No new packages. Use what is already declared.

---

## 🧩 Smart-Activate Implementation Guide

This is the most complex new task. Implementation sketch:

```python
@router.post("/smart-activate")
async def smart_activate(req: SmartActivateRequest,
                          user: dict = Depends(require_admin)):
    """
    One-tap drive setup. Detects state, does the right thing.
    """
    # 1. Get the whole disk (e.g. /dev/sda)
    raw = await list_block_devices()
    disk = next((d for d in raw if f"/dev/{d['name']}" == req.device), None)
    if not disk:
        raise HTTPException(404, "Drive not found")
    if is_os_partition(disk):
        raise HTTPException(403, "Cannot use system drive as storage")

    # 2. Check if already active
    state = await store.get_storage_state()
    if state.get("activeDevice", "").startswith(req.device):
        return {"action": "already_active",
                "display_name": _display_name(disk)}

    # 3. Find best partition
    children = disk.get("children", [])
    best = _find_best_partition(children)   # largest non-OS partition
    
    # State A: has ext4 → just mount it
    if best and best.get("fstype") == "ext4":
        partition_path = f"/dev/{best['name']}"
        rc, _, stderr = await run_command(
            ["sudo", "mount", partition_path, str(settings.nas_root)])
        if rc != 0:
            raise HTTPException(500, f"Could not activate drive: {stderr}")
        await _post_mount_setup(partition_path, best)
        return {"action": "mounted", "display_name": _display_name(disk)}

    # State B/C: needs formatting → start async job
    job = create_job()
    target = f"/dev/{disk['name']}"   # format whole disk, create one partition
    asyncio.create_task(_smart_format_and_mount(job.id, target, disk))
    return {"action": "formatting", "display_name": _display_name(disk),
            "jobId": job.id}


def _display_name(disk: dict) -> str:
    """Return a human-friendly drive name. No /dev/ paths."""
    model = (disk.get("model") or "").strip()
    tran = classify_transport(disk)
    size_bytes = int(disk.get("size") or 0)
    size_str = _human_size(size_bytes)
    transport_label = {"usb": "USB Drive", "nvme": "NVMe Drive"}.get(tran, "Drive")
    if model:
        return f"{model} ({size_str})"
    return f"{size_str} {transport_label}"
```

---

## 🏁 How to Start This Session

1. Read TASKSv3.md in the repository
2. Find first ⬜ todo task in Phase DRIVE
3. Read only the files listed in that task
4. Implement following this document exactly
5. Validate → commit → mark done → next task

---

*AiHomeCloud Master Prompt v3.0 — March 2026*
*Replaces MASTER_PROMPT.md v2. Commit to repo root.*
*Update when architecture changes.*
