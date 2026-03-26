# CTO/Co-Founder Review — AiHomeCloud

> Full audit conducted 24 March 2026 on branch `v6`.
> Covers backend (8,612 LoC, 40 files), Flutter (14,500 LoC, 54 files), 8,689 lines of tests.

---

## The Product in 30 Seconds

A private home NAS appliance (Radxa SBC + USB/NVMe drive) with a Flutter Android app. Indian families get Google-Drive-like file management, Telegram integration, and media services — no subscription, no cloud, no third-party accounts. Revenue from hardware sales.

---

## A. What's Working Well (Don't Touch)

1. **Value proposition is crystal clear** — "one device, one price, no subscriptions" is a message Indian middle-class families understand immediately. Keep it.

2. **Security posture is surprisingly mature** for a v1 — bcrypt with `run_in_executor`, `_safe_resolve` path sandboxing, `shell=False` enforcement, rate limiting on critical paths, atomic JSON writes. The self-audit culture (kb/critique.md) is excellent.

3. **Backend test coverage is elite** — 8,689 lines of tests (~1:1 ratio), all critical paths covered. This is rare for a pre-revenue product. Protect this.

4. **JSON file storage is the right call for v1** — No SQLite/Postgres saves ~50MB RAM on a 4GB board. With ≤8 users and ≤10K files indexed, JSON + FTS5 is sufficient. Don't "upgrade" this until you have data proving it's a bottleneck.

5. **Telegram integration is a genuine differentiator** — For Indian families already living in Telegram, "forward a file to your bot and it appears on your NAS" is magic. The 2GB local API support doubles down on this correctly.

---

## B. Bugs to Fix Before Any User Touches This (P0)

These are ship-blockers:

| # | Status | Bug | Impact | File |
|---|---|---|---|---|
| 1 | ✅ DONE | **`document_index.py` uses `/shared/%` but migration renamed to `family/`** | Non-admin users can't search family documents at all | `backend/app/document_index.py` ~L290 |
| 2 | ✅ DONE | **`jobs_routes.py` checks `user.get("role")` instead of `user.get("is_admin")`** | Admin job RBAC completely broken — admin can't see other users' jobs | `backend/app/routes/jobs_routes.py` L26 |
| 3 | ✅ DONE | **Telegram upload has no file size limit or blocked extension check** | Disk fill attack + executable upload via any valid upload token | `backend/app/routes/telegram_upload_routes.py` L260-304 |
| 4 | ✅ DONE | **`store.py` `update_user_profile` double-invalidates cache** | Unnecessary disk I/O on every profile update — wipes fresh cache | `backend/app/store.py` ~L210 |
| 5 | ✅ DONE | **`monitor_routes.py` `_last_storage_warn` scoping bug** | Storage warning fires every 1-second tick instead of once per hour | `backend/app/routes/monitor_routes.py` L179 |
| 6 | ✅ DONE | **`subprocess_runner.py` doesn't reap zombies after timeout kill** | Zombie process accumulation over time | `backend/app/subprocess_runner.py` L39-43 |

---

## C. Engineering Changes (Priority Order)

### ✅ C1. Kill the Global TLS Bypass in Flutter (Security — 1 hour)

`main.dart` overrides `badCertificateCallback` to `true` globally. This destroys the careful TLS pinning in `ApiService` for any non-API HTTPS call (image loading, etc.). Fix: scope the override to only the device's IP, not all HTTPS connections.

**Done:** `lib/core/tls_config.dart` holds shared `trustedDeviceHost`; `_CubieHttpOverrides` checks both port AND host. Null during onboarding (port-only), set to device IP on login, cleared on logout.

### ✅ C2. Add `sudo -n` Consistently (Reliability — 30 min)

Several `sudo` calls in `storage_routes.py` and `telegram_routes.py` lack `-n` (no-password). If sudoers isn't configured perfectly, these hang forever waiting for interactive password input inside `run_command()`. Audit every `sudo` call and add `-n`.

**Done:** All sudo calls in both `storage_routes.py` and `telegram_routes.py` now have `-n`. Fixed 8 occurrences in telegram_routes (`cp`, `chmod`, `apt-get install`, `systemctl daemon-reload`, `systemctl enable`, `systemctl start`).

### ✅ C3. Deduplicate `_SERVICE_UNITS` (Maintenance — 15 min)

The same service-name-to-unit mapping exists in both `system_routes.py` and `service_routes.py`. When someone adds a service to one and forgets the other, shutdown misses services. Extract to a shared module.

**Done:** `service_routes.py` now exports `SERVICE_UNITS`; `system_routes.py` imports it as `_SERVICE_UNITS`.

### ✅ C4. WiFi Toggle Should Require Admin (Security — 5 min)

Any authenticated family member can toggle WiFi on/off for the entire device. This should be admin-only.

**Done:** `PUT /network/wifi` now uses `Depends(require_admin)`.

### ✅ C5. Add Rate Limiting to Missing Endpoints (Security — 30 min)

`/files/search`, `/files/sort-now`, all storage mutation endpoints, all family management endpoints, and the telegram upload endpoint have no rate limiting.

**Done:** All listed endpoints decorated with `@limiter.limit(...)`. Rates: search 30/min, sort-now 10/min, storage mutations 5/min, family 20/min, telegram upload 20/min.

### ✅ C6. Telegram Upload — Async Writes (Performance — 30 min)

The telegram upload writes file chunks synchronously, blocking the event loop. For a 2GB file, this blocks the entire backend for the duration of the upload. Use `run_in_executor` like the main file_routes upload does.

**Done:** `telegram_upload_routes.py` now uses `await loop.run_in_executor(None, f.write, chunk)`.

---

## D. Strategic Product Decisions

### D1. SHIP to Real Users ASAP (Most Important)

The codebase is at ~95% feature-complete for v1. The remaining 5% is polish. **The biggest risk isn't code quality — it's never shipping.** Here's what a v1 launch needs:

- Fix the 6 P0 bugs above
- Run the setup wizard on a fresh Cubie A7Z
- Hand the box + app APK to 3 families (friends/relatives)
- Watch them set it up. Take notes. That's your roadmap.

Everything else — OTA updates, iOS app, multi-device, AI categorization — is post-launch.

### D2. Drop Features, Not Add Them

**Things to remove or defer from v1:**

| Status | Feature | Why |
|---|---|---|
| ✅ DONE | **OCR/Tesseract indexing** | Now opt-in: `ocr_enabled: bool = False` in config. Disabled by default. |
| ✅ DONE | **Auto file sorting** | Now opt-in: `auto_sort_enabled: bool = False` in config. Manual "Sort now" button kept. |
| ✅ DONE | **BLE discovery fallback** | Removed `flutter_blue_plus` + `permission_handler` from pubspec. Manual IP entry form added to network scan screen. |
| ✅ DONE | **NFS service toggle** | Removed from `SERVICE_UNITS`, `_DEFAULT_SERVICES`, Flutter UI, and service icon map. |
| ✅ DONE | **OTA firmware stubs** | No OTA action button/route in UI. `firmwareVersion` shown as display-only label in device settings. |

**Things to add for v1:**

| Status | Feature | Why |
|---|---|---|
| ✅ DONE | **Auto-backup from phone** | Background sync of camera roll → NAS via WorkManager. Daily 2:30 AM + manual trigger. Telegram notifications on completion. |
| ❌ TODO | **Photo gallery view** | This is THE use case for Indian families — send photos from phone, view on TV/family devices. A grid view of images with thumbnails would make this feel like Google Photos. |
| ❌ TODO | **Simple sharing links** | "Share this file with anyone on the same network" via a temporary URL. Families share files by URL, not by knowing the folder path. |

### D3. Hardware Strategy

The multi-board support (Cubie A7Z, A7A, Rock Pi 4, RPi4) is engineering overhead without business value right now. **Pick ONE board** (Cubie A7Z), ship it perfect, and support others only if customers ask.

The `board.py` auto-detection code is fine — keep it — but don't test or QA on 4 boards. Your dev/test board (Rock Pi 4A) is good for development, but all QA should happen on the production target.

### D4. Monetization Thought

"One device, one price" is the right v1 positioning, but the long-term business model needs thought:

- **Hardware margin alone won't sustain a company.** A Radxa Cubie A7Z costs ~$50 wholesale. With a case, PSU, and packaging, your COGS is ~$80. Selling at $120-150 gives thin margins.
- **Future revenue options without betraying the "no subscription" promise:**
  - Premium app features (auto-backup, photo gallery, remote access via Tailscale) — one-time IAP
  - Extended warranty / hardware upgrade program
  - Enterprise/office variant with more storage + user seats

---

## E. Code Architecture — What to Refactor in v2 (Not Now)

These are **NOT v1 priorities**. Listed for awareness:

1. **Extract a service layer** between routes and store. Currently, business logic lives in route handlers (e.g., `_smart_format_and_mount` at 80 lines inside `storage_routes.py`). For v1 this is fine — it ships. For v2, extract to `services/storage_service.py`.

2. **Per-file locks in `store.py`** instead of one global lock. Currently all JSON ops serialize through one lock. With 8 concurrent users this will cause noticeable latency.

3. **Replace the `lifespan()` god-function** in `main.py` (220 lines) with a startup-task registry pattern.

4. ✅ **Persistent job store** — implemented: JSON persistence across restarts; in-progress jobs marked failed on reload; configurable TTL and max count via `AHC_JOB_TTL_HOURS` / `AHC_JOB_MAX_COUNT`.

5. ✅ **Event filtering by user role** — implemented: `admin_only` flag on `AppEvent`; WebSocket handler checks user's admin status and skips admin-only events for non-admin subscribers.

---

## F. Testing Gaps to Close Before Launch

| Status | Gap | Risk | Effort |
|---|---|---|---|
| ✅ DONE | Flutter provider tests (0/5 files tested) | **High** — providers bridge API↔UI, bugs here are invisible until production | 2-3 days |
| ✅ DONE | `discovery_service.dart` (untested) | **High** — this is the onboarding critical path | 1 day |
| ✅ DONE | `telegram_upload_routes.py` backend tests | **High** — untested security boundary with upload + token auth | 1 day |
| ✅ DONE | `family_routes.py` backend tests | **Medium** — admin RBAC not directly tested | Half day |
| ✅ DONE | Navigation/routing tests | **Medium** — 13+ routes with guards, redirect logic untested | 1 day |

---

## G. Backend Audit — Detailed Findings

### Core Module Issues

#### `main.py` (441 lines)
- **Monolithic lifespan function** (L84–L306): ~220 lines with 15+ try/except blocks for independent startup tasks. Each block swallows errors independently. A startup-task registry pattern would be cleaner.
- **Late import anti-pattern**: Multiple `from .module import X` statements scattered inside `lifespan()` (L103, L159, L166, L182, etc.). Makes dependency tracking difficult.
- **Mutable settings object** (L233–L240): Telegram config is loaded from store and mutated directly on the `settings` singleton. Settings state after startup depends on runtime data, not just env vars.
- **Migration code in lifespan** (L108–L127): One-time `shared/ → family/` migration embedded in startup path. Should be standalone. No guard for partial re-migration on failure.
- **Root endpoint exposes info** (L370–L377): `/` returns `deviceName` and `serial` without authentication (minor on LAN).
- **Backward-compat redirect** (L381–L385): `/api/{path:path}` catch-all 308 redirect potentially masks real 404s.

#### `auth.py` (165 lines)
- **No token revocation check** on access tokens: `decode_token()` (L92–L101) only validates JWT signature/expiry, never checks a revocation list. Compromised access token valid for 1 hour.
- **`require_admin` has duplicate store import** (L122): `from . import store` already imported at module level (L15).
- **bcrypt rounds=10** (L24): Reduced from default 12 for ARM performance. Documented trade-off. Acceptable.

#### `store.py` (571 lines)
- **Single lock bottleneck** (L22): `_store_lock` serializes ALL JSON file operations across all data files. Write to `users.json` blocks reads from `services.json`.
- **Cache invalidation inconsistency**: Some functions invalidate cache before acquiring lock (`save_services` L268, `update_device_name` L299), while `save_users` (L131) updates cache inside lock. Creates window for stale reads.
- **Corrupt file recovery questionable** (L55–L87): Recovery renames corrupt file to `.corrupt`, then reads the `.corrupt` copy. If file was corrupt, reading the copy also fails.
- **Event emission in sync code** (L78–L87): `_read_json` creates asyncio task via `loop.create_task()`. Using `loop.is_running()` is fragile from thread executor contexts.
- **`update_user_profile` double cache invalidation** (L210): Calls `save_users` (which sets cache) then `_set_cached("users", None)`. Second call wipes fresh cache — harmful.
- **No `flock()`**: Atomic writes via `tempfile.mkstemp` + `os.replace` (good), but no inter-process file locking.

#### `config.py` (236 lines)
- **Secret generation TOCTOU race** (L21–L27): `if secret_file.exists()` followed by read has race window in multi-process startup.
- **No atomic write for secrets** (L25): `secret_file.write_text(secret)` — crash during write corrupts the secret.
- **Hardcoded paths** (L13–L14): `JWT_SECRET_FILE` and `PAIRING_KEY_FILE` hardcoded to `/var/lib/aihomecloud/` before `data_dir` is available.
- **Socket leak in `get_local_ip`** (L65–L68): No `with` statement; `getsockname()` failure leaks socket.
- **Module-level side effects** (L216–L236): Import triggers file I/O (secret generation).

#### `subprocess_runner.py` (68 lines)
- **`_SHELL_DANGERS` regex too restrictive** (L16): Rejects `$` and `|` in tokens — harmless in `shell=False` mode but rejects legitimate filenames containing these characters.
- **No `stdin=DEVNULL`**: Some commands may hang waiting for stdin.
- **Timeout kills without reaping** (L39–L43): No `await proc.wait()` after `proc.kill()`. Zombie processes accumulate.

#### `board.py` (275 lines)
- **Repetitive code**: 4 nearly identical code blocks in `detect_board()` (L208–L275). Should extract to helper.
- **`find_lan_interface` false positives** (L170–L175): Type 1 includes USB ethernet and bridges. First alphabetically sorted wins.

#### `models.py` (331 lines)
- **No validation on `FormatRequest.device`** (L137–L141): Accepts any string for device path.
- **`LoginRequest.pin` default empty string** (L162): Can submit empty PIN.
- **Missing `min_length`** on several string fields: `CreateUserRequest.name` (L171) allows empty names.
- **`StorageDevice` exposes `/dev/` paths** (L117–L131) — violates the "never show /dev/ paths" invariant.

#### `tls.py` (70 lines)
- **No cert rotation**: 10-year validity, no renewal mechanism.
- **Socket leak** (L20–L24): Same no-`with` pattern as config.py.
- **RSA 2048**: Lower end for long-lived self-signed cert. 4096 or Ed25519 more future-proof.

#### `job_store.py` (91 lines)
- **Not persistent**: Jobs lost on restart. Format job started before crash has no status.
- **Purge only on create** (L42): Old jobs accumulate if no new jobs created (bounded by max 100).

#### `events.py` (113 lines)
- **No backpressure**: Full subscriber queue → subscriber silently dropped. No error event, no logging.
- **Queue size hardcoded** (L96): `maxsize=200` not configurable.
- **Subscriber removal O(n²)** (L68–L72): Linear scan on list for each dead subscriber.

#### `document_index.py` (467 lines)
- **`asyncio.get_event_loop()` deprecated pattern**: Used throughout (L117, L120, L307, etc.). Should use `get_running_loop()`.
- **`/shared/%` prefix bug** (L290): Member search scope uses old `/shared/` prefix but migration renamed to `family/`. **Non-admin users can't search family documents.**
- **100KB text truncation** (L146): Silent truncation of long documents.
- **Tesseract `eng+hin` hardcoded** (L160): Language pack not configurable.

#### `file_sorter.py` (300 lines)
- **Document-photo heuristic too aggressive** (L94–L99): Photo under 800KB classified as document. Screenshots/thumbnails misclassified.
- **No file event publishing**: Sorted files not published to `FileEventBus`. UI doesn't see real-time updates.
- **Unnecessary re-import of settings** (L79–L82): Already imported at module level.

#### `wifi_manager.py` (96 lines)
- **No periodic check**: WiFi state only checked at startup. Ethernet disconnect after boot leaves WiFi disabled.
- **Synchronous I/O** (L18–L34): `/sys/` reads in sync function called from async context.

#### `logging_config.py` (52 lines)
- **`root.handlers.clear()`** (L48): Removes all existing handlers including uvicorn's. Could suppress access logs.

#### `hygiene.py` (53 lines)
- **Uses `settings.shared_path`** (L24): Alias for `family_path`. Confusing — should use `family_path` directly.
- **`remove_missing_documents` on every startup** (L41): Full document scan — slow with large indexes.

#### `index_watcher.py` (150 lines)
- **Full filesystem scan every 20 seconds** (L31): `root.rglob("*")` across all Documents directories. Significant I/O on USB with large file trees.
- **State not persisted** (L130): Lost on restart → full re-index every startup.

---

### Route File Issues

#### `auth_routes.py` (538 lines, 14 endpoints)
- **Missing rate limiting** on: `GET /pair/qr`, `GET /auth/users/names`, `PUT /users/me`, `DELETE /users/me`, `DELETE /users/pin`
- **`GET /auth/users/names` is public** (L227–L241): Returns all usernames and PIN status. By design for login picker but enables user enumeration.
- **`change_pin` plaintext fallback** (L388–L391): Legacy migration code compares plaintext PINs if not bcrypt-prefixed. Should be removed once all PINs migrated.
- **`login` allows empty PIN bypass** (L332–L334): If user has no PIN, login succeeds with any input. Intentional but worth highlighting.
- **`delete_my_profile` doesn't use `_safe_resolve`** (L484): Uses `Path(name).name` for traversal protection but differs from file_routes pattern.

#### `file_routes.py` (649 lines, 9 endpoints)
- **TOCTOU in `_safe_resolve` symlink check** (L89–L90): Symlink could be created between check and resolve. The `resolve()` + `relative_to()` check (L96–L98) provides real safety net.
- **Scan cache unbounded** (L31–L33): `_scan_cache` grows without size limit. Many unique directory listings accumulate forever.
- **`upload_file` doesn't explicitly close `UploadFile`** (L369–L413): Relies on FastAPI cleanup (usually fine).

#### `storage_routes.py` (543 lines, 9 endpoints)
- **No rate limiting** on any endpoint.
- **`sudo` missing `-n` flag** in `format_device` (L258): Could hang waiting for password.
- **`eject_device` writes to sysfs directly** (L357): Bypasses `run_command()`, blocks event loop.
- **No cleanup on format failure**: If `sgdisk -Z` succeeds but partition creation fails, disk left with no partition table.

#### `telegram_routes.py` (624 lines, 6 endpoints)
- All admin-only — good.
- Health check fix already applied (curl `-sf` → `-s`).

#### `telegram_upload_routes.py` (359 lines, 2 endpoints)
- **No file size enforcement** (L278–L304): Bypasses `settings.max_upload_bytes`. Disk fill possible.
- **No blocked extension check** (L260–L269): Accepts `.sh`, `.py`, `.exe` etc. Main file_routes has `BLOCKED_EXTENSIONS`.
- **Synchronous file writes** (L304–L312): `f.write(chunk)` blocks event loop. Main upload uses `run_in_executor`.

#### `monitor_routes.py` (215 lines, 1 WS endpoint)
- **`_last_storage_warn` scoping bug** (L179): Local variable in loop body (no `nonlocal`). Resets every iteration → warning fires every tick.

#### `jobs_routes.py` (33 lines, 1 endpoint)
- **Admin check uses `role` instead of `is_admin`** (L26): `user.get("role") == "admin"` — but JWTs use `is_admin` boolean. RBAC completely broken.

#### `system_routes.py` (149 lines, 6 endpoints)
- **`_SERVICE_UNITS` duplicated** with `service_routes.py` (L98–L103). Divergence risk.

#### `service_routes.py` (78 lines, 2 endpoints)
- **`_SERVICE_UNITS` duplicated** with `system_routes.py` (L22–L27).

#### `network_routes.py` (92 lines, 3 endpoints)
- **WiFi toggle doesn't require admin** (L85–L90): Any user can toggle WiFi.
- No rate limiting.

#### `trash_routes.py` (204 lines, 5 endpoints)
- **Quota enforcement edge case** (L90–L99): If a trash item has `sizeBytes=0`, subtraction never brings total below quota, purging everything.

#### `family_routes.py` (166 lines, 4 endpoints)
- **`_folder_size_gb_sync` walks entire user directory** (L22–L37): With many files, `GET /family` becomes very slow.
- New family members have no PIN (unlike main `POST /users` flow).

#### `event_routes.py` (187 lines, 1 WS endpoint)
- **`emit_device_mounted` leaks `/dev/` paths** (L123–L131): Violates invariant.
- **No event filtering by user role**: All clients see all events.

#### `storage_helpers.py` (458 lines, internal)
- **`check_open_handles` uses `lsof +D /srv/nas`** (L395–L400): Recursively walks entire NAS tree. Could take minutes on large storage.
- **Structured error detail** (L434): Only place using dict detail in HTTPException. All others use plain strings.

---

## H. Flutter Audit — Key Findings

### App Size
- 54 `.dart` files, ~14,500 hand-written LoC
- Largest files: `dashboard_screen.dart` (1,114), `telegram_setup_screen.dart` (1,044), `folder_view.dart` (981)

### Good Patterns
- Clean `part`/`part of` separation for API service extensions
- Immutable `AuthSession` with `copyWith` — correct Riverpod pattern
- TLS pinning with SHA-256 certificate fingerprint validation
- Centralized constants, `friendlyError()` enforced everywhere
- Token auto-refresh with mutex (`_isRefreshing`) prevents concurrent refresh storms

### Concerns
1. ✅ **Global TLS bypass**: Fixed — `_CubieHttpOverrides` now scopes cert bypass to device IP + API port only. See C1.
2. **`totalStorageGB = 500.0` hardcoded** in constants — should come from device API.
3. **No integration/E2E tests** — only unit and widget tests.
4. ✅ **Session restore has no token expiry check**: Fixed — `_restorePersistedSession()` now checks JWT expiry; attempts refresh on expired token; clears session and sends to onboarding if refresh fails.

### Test Coverage
| Area | Score | Detail |
|---|---|---|
| Backend tests | **A** | ~1:1 source:test ratio, all critical paths |
| Flutter widget tests | **A** | 8/8 widgets tested |
| Flutter screen tests | **B-** | 11/15 screens tested |
| Flutter service tests | **A** | 5/5 services tested |
| Flutter provider tests | **B** | 4/5 provider files tested (core, discovery, file, data); `device_providers.dart` untested |
| Flutter integration tests | **F** | None exist |

### Dependency Watch List
| Package | Version | Concern |
|---|---|---|
| ~~`flutter_blue_plus`~~ | ~~^1.31.14~~ | ✅ Removed — BLE discovery replaced with manual IP entry |
| `multicast_dns` | ^0.3.2+1 | Low version, niche package |
| `receive_sharing_intent` | ^1.8.0 | v1.x, check for v2 compatibility |
| `percent_indicator` | ^4.2.3 | Unmaintained recently |

---

## I. Cross-Cutting Concerns

### Inconsistent Patterns
| Pattern | Correct Usage | Incorrect Usage |
|---|---|---|
| `asyncio.get_running_loop()` | store.py, auth.py | document_index, file_sorter, index_watcher use deprecated `get_event_loop()` |
| Cache invalidation inside lock | store.py `save_users` | store.py `save_services`, `update_device_name` invalidate before lock |
| Late imports | main.py (for circular import avoidance) | auth.py L122, file_sorter.py L79 (unnecessary) |

### Hardcoded Values That Should Be Configurable
| Value | File | Line |
|---|---|---|
| `_CACHE_TTL = 5.0` | store.py | 33 |
| `_POOL_SIZE = 3` | document_index.py | 76 |
| `_BUFFER_SIZE = 1000` | events.py | 36 |
| `_DEFAULT_INTERVAL_SECONDS = 20` | index_watcher.py | 31 |
| `eng+hin` tesseract languages | document_index.py | 160 |
| `_MIN_AGE_SECONDS = 30` | file_sorter.py | 67 |
| `_DOC_PHOTO_MAX_BYTES = 800KB` | file_sorter.py | 68 |
| `bcrypt__rounds=10` | auth.py | 24 |

---

## J. Summary: If I Had 2 Weeks to Ship

**Week 1:**
- Fix the 6 P0 bugs
- Fix global TLS bypass in Flutter
- Add `sudo -n` everywhere
- Add rate limiting to missing endpoints
- Remove OTA stub from UI
- Make OCR/auto-sort opt-in (not always-on)

**Week 2:**
- Close the 5 testing gaps
- Run setup wizard on fresh Cubie A7Z end-to-end
- Build release APK, hand to 3 families
- Write a 1-page "Getting Started" card that ships in the box

**Post-launch (based on user feedback):**
- Photo gallery view
- Auto-backup from phone
- Sharing links

---

> The product vision is strong, the engineering is disciplined, and the codebase is in better shape than most funded startups at this stage. The risk isn't technical — it's shipping paralysis. Fix the bugs, close the test gaps, and get it in front of real families.
