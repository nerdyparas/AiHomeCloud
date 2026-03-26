# Tasks for Production — AiHomeCloud

> Derived from CTO/Co-Founder Review (24 March 2026, branch `v6`).
> Ordered by priority. Each task has a status and recommended AI model.

---

## Priority Legend

| Level | Meaning |
|---|---|
| **P0** | Ship-blocker — must fix before any user touches the device |
| **P1** | Critical — fix in Week 1, before first beta hand-off |
| **P2** | Important — fix in Week 2, before release APK |
| **P3** | Post-launch — address based on user feedback |
| **P4** | v2 — architecture improvements, not v1 scope |

## AI Model Legend

| Model | Best For |
|---|---|
| **Opus 4.6** | Complex multi-file refactors, architecture decisions, subtle bugs, security audits |
| **Sonnet** | Targeted single-file fixes, adding tests, straightforward feature work |
| **GPT-4o** | Documentation, code review, planning, and conversational analysis |
| **Codex / o3** | Rapid small edits, boilerplate generation, repetitive changes |

---

## P0 — Ship-Blockers

| # | Task | File(s) | Status | AI Model |
|---|---|---|---|---|
| 1 | **Fix `document_index.py` `/shared/%` → `family/` prefix** — non-admin users can't search family documents | `backend/app/document_index.py` ~L290 | `DONE` | Sonnet |
| 2 | **Fix `jobs_routes.py` admin check** — change `user.get("role") == "admin"` to `user.get("is_admin")` | `backend/app/routes/jobs_routes.py` L26 | `DONE` | Sonnet |
| 3 | **Add file size limit + blocked extension check to telegram upload** — prevents disk fill and executable upload | `backend/app/routes/telegram_upload_routes.py` L260-304 | `DONE` | Sonnet |
| 4 | **Fix `store.py` double cache invalidation** in `update_user_profile` — second `_set_cached("users", None)` wipes fresh data | `backend/app/store.py` ~L210 | `DONE` | Sonnet |
| 5 | **Fix `monitor_routes.py` `_last_storage_warn` scoping** — add `nonlocal` so warning fires once/hour not every tick | `backend/app/routes/monitor_routes.py` L179 | `DONE` | Sonnet |
| 6 | **Fix `subprocess_runner.py` zombie reaping** — add `await proc.wait()` after `proc.kill()` on timeout | `backend/app/subprocess_runner.py` L39-43 | `DONE` | Sonnet |

---

## P1 — Week 1 (Before Beta Hand-off)

| # | Task | File(s) | Status | AI Model |
|---|---|---|---|---|
| 7 | **Fix global TLS bypass in Flutter** — scope `badCertificateCallback` to device IP only, not all HTTPS | `lib/main.dart` | `DONE` | Opus 4.6 |
| 8 | **Add `sudo -n` to all sudo calls** — prevents hanging on interactive password prompt | `backend/app/routes/storage_routes.py`, `telegram_routes.py`, others | `DONE` | Sonnet |
| 9 | **Deduplicate `_SERVICE_UNITS`** — extract shared mapping from `system_routes.py` and `service_routes.py` | `backend/app/routes/system_routes.py`, `service_routes.py` | `DONE` | Sonnet |
| 10 | **WiFi toggle require admin** — any user can currently disrupt connectivity | `backend/app/routes/network_routes.py` L85-90 | `DONE` | Sonnet |
| 11 | **Add rate limiting to missing endpoints** — file search, sort-now, storage mutations, family mgmt, telegram upload | Multiple route files | `DONE` | Sonnet |
| 12 | **Telegram upload: async file writes** — use `run_in_executor` like main upload, currently blocks event loop | `backend/app/routes/telegram_upload_routes.py` L304-312 | `DONE` | Sonnet |
| 13 | **Remove OTA stub from UI** — half-implemented feature confuses users | Flutter screens/settings | `SKIP — no active OTA UI found` | Sonnet |
| 14 | **Make OCR/Tesseract indexing opt-in** — adds ~20MB RAM + 500MB lang packs, 95% of users won't use it | `backend/app/document_index.py`, settings | `DONE` | Opus 4.6 |
| 15 | **Make auto file sorting manual** — replace 20-second `rglob("*")` poll with "Sort now" button only | `backend/app/file_sorter.py`, `index_watcher.py` | `DONE` | Opus 4.6 |
| 16 | **Fix `config.py` socket leak** in `get_local_ip` — add `with` statement | `backend/app/config.py` L65-68 | `DONE` | Sonnet |
| 17 | **Fix `config.py` secret generation TOCTOU** — use atomic read/write for JWT secret file | `backend/app/config.py` L21-27 | `DONE` | Sonnet |
| 18 | **Add `stdin=DEVNULL` to subprocess_runner** — prevents commands hanging on stdin | `backend/app/subprocess_runner.py` | `SKIP — already implemented` | Sonnet |
| 19 | **Fix `event_routes.py` leaking `/dev/` paths** in `emit_device_mounted` — violates invariant | `backend/app/routes/event_routes.py` L123-131 | `DONE` | Sonnet |

---

## P2 — Week 2 (Before Release APK)

| # | Task | File(s) | Status | AI Model |
|---|---|---|---|---|
| 20 | **Add Flutter provider tests** — 0/5 provider files tested (grade F), high risk | `test/providers/` (new) | `TODO` | Opus 4.6 |
| 21 | **Add `discovery_service.dart` tests** — onboarding critical path, untested | `test/services/` | `TODO` | Opus 4.6 |
| 22 | **Add `telegram_upload_routes.py` backend tests** — untested security boundary | `backend/tests/test_telegram_upload.py` (new) | `TODO` | Opus 4.6 |
| 23 | **Add `family_routes.py` backend tests** — admin RBAC not directly tested | `backend/tests/test_family.py` (new) | `TODO` | Sonnet |
| 24 | **Add navigation/routing tests** — 13+ routes with guards, redirect logic untested | `test/navigation/` (new) | `TODO` | Opus 4.6 |
| 25 | **Run setup wizard on fresh Cubie A7Z end-to-end** — full hardware QA | `scripts/first-boot-setup.sh` | `TODO` | Manual |
| 26 | **Build release APK** — signed, versioned, ready for hand-off | Flutter build | `TODO` | Manual |
| 27 | **Hand device + APK to 3 test families** — real-world validation | N/A | `TODO` | Manual |
| 28 | **Write 1-page "Getting Started" card** — ships in the box | `docs/` (new) | `TODO` | GPT-4o |
| 29 | **Fix `auth_routes.py` plaintext PIN fallback** — remove legacy migration code | `backend/app/routes/auth_routes.py` L388-391 | `TODO` | Sonnet |
| 30 | **Fix `trash_routes.py` quota edge case** — `sizeBytes=0` items never purge correctly | `backend/app/routes/trash_routes.py` L90-99 | `TODO` | Sonnet |
| 31 | **Fix `models.py` validation gaps** — empty PIN, empty name, no device path validation | `backend/app/models.py` | `TODO` | Sonnet |
| 32 | **Fix `family_routes.py` slow folder size walk** — `_folder_size_gb_sync` walks entire user dir | `backend/app/routes/family_routes.py` L22-37 | `TODO` | Sonnet |
| 33 | **Fix scan cache unbounded growth** in file_routes — add size limit or TTL | `backend/app/routes/file_routes.py` L31-33 | `TODO` | Sonnet |
| 34 | **Fix `store.py` cache invalidation consistency** — all functions should invalidate inside lock | `backend/app/store.py` | `TODO` | Opus 4.6 |
| 35 | **Replace deprecated `asyncio.get_event_loop()`** — use `get_running_loop()` in document_index, file_sorter, index_watcher | Multiple files | `TODO` | Sonnet |
| 36 | **Fix `hygiene.py` using `shared_path`** — should use `family_path` directly | `backend/app/hygiene.py` L24 | `TODO` | Codex / o3 |
| 37 | **Fix Flutter session restore** — check token expiry before blindly restoring from SharedPreferences | `lib/services/auth_session.dart` | `TODO` | Sonnet |
| 38 | **Remove hardcoded `totalStorageGB = 500.0`** — should come from device API | `lib/core/constants.dart` | `TODO` | Sonnet |

---

## P3 — Post-Launch (User Feedback Driven)

| # | Task | File(s) | Status | AI Model |
|---|---|---|---|---|
| 39 | **Photo gallery view** — grid view of images with thumbnails, Google-Photos-like experience | New screen + API | `TODO` | Opus 4.6 |
| 40 | **Auto-backup from phone** — background sync of camera roll → NAS | New service + API | `TODO` | Opus 4.6 |
| 41 | **Simple sharing links** — temporary URL for "share file with anyone on same network" | New route + Flutter screen | `TODO` | Opus 4.6 |
| 42 | **Drop BLE discovery fallback** — replace with "enter IP manually" form, remove flutter_blue_plus | `lib/services/discovery_service.dart`, `pubspec.yaml` | `TODO` | Sonnet |
| 43 | **Drop NFS service toggle** — keep Samba only, no Indian family uses NFS | `backend/app/routes/service_routes.py`, Flutter UI | `TODO` | Sonnet |
| 44 | **Add WiFi periodic re-check** — currently only checked at startup, Ethernet disconnect leaves WiFi disabled | `backend/app/wifi_manager.py` | `TODO` | Sonnet |
| 45 | **Persist index watcher state** — prevents full re-index on every startup | `backend/app/index_watcher.py` | `TODO` | Sonnet |
| 46 | **Event filtering by user role** — regular users shouldn't see admin events | `backend/app/routes/event_routes.py` | `TODO` | Opus 4.6 |
| 47 | **Add backpressure to event system** — log dropped subscribers instead of silent discard | `backend/app/events.py` | `TODO` | Sonnet |
| 48 | **Fix `lsof +D /srv/nas` performance** — use `fuser` or per-mountpoint check instead | `backend/app/routes/storage_helpers.py` L395-400 | `TODO` | Sonnet |
| 49 | **Persistent job store** — survive restart during format operations | `backend/app/job_store.py` | `TODO` | Sonnet |
| 50 | **Make hardcoded values configurable** — cache TTL, pool size, buffer size, index interval, tesseract langs, bcrypt rounds, etc. | Multiple files | `TODO` | Sonnet |

---

## P4 — v2 Architecture (Not v1 Scope)

| # | Task | File(s) | Status | AI Model |
|---|---|---|---|---|
| 51 | **Extract service layer** — move business logic out of route handlers into `services/` | `backend/app/services/` (new) | `TODO` | Opus 4.6 |
| 52 | **Per-file locks in `store.py`** — replace single global lock with per-data-file locks | `backend/app/store.py` | `TODO` | Opus 4.6 |
| 53 | **Replace lifespan god-function** — startup-task registry pattern instead of 220-line `lifespan()` | `backend/app/main.py` | `TODO` | Opus 4.6 |
| 54 | **Add integration/E2E tests** — full end-to-end flows on real device | `test/integration/` (new) | `TODO` | Opus 4.6 |
| 55 | **Add storage format cleanup on failure** — if partition creation fails after `sgdisk -Z`, restore partition table | `backend/app/routes/storage_routes.py` | `TODO` | Opus 4.6 |
| 56 | **Board detection refactor** — extract 4 repetitive blocks in `detect_board()` to helper | `backend/app/board.py` | `TODO` | Sonnet |
| 57 | **Cert rotation mechanism** — current 10-year self-signed cert has no renewal | `backend/app/tls.py` | `TODO` | Opus 4.6 |

---

## Summary

| Priority | Total | Done | Remaining |
|---|---|---|---|
| P0 (Ship-blockers) | 6 | 6 | 0 |
| P1 (Week 1) | 13 | 11 | 2 skipped (13, 18) |
| P2 (Week 2) | 19 | 0 | 19 |
| P3 (Post-launch) | 12 | 0 | 12 |
| P4 (v2) | 7 | 0 | 7 |
| **Total** | **57** | **17** | **40** |

---

> **Recommended workflow:** Start with all 6 P0 tasks (use Sonnet for speed — they're small targeted fixes). Then move through P1 with a mix of Sonnet and Opus 4.6. Use Opus 4.6 for the P2 testing tasks — writing good tests requires deep codebase understanding. GPT-4o for documentation tasks.
