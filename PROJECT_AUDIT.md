# PROJECT AUDIT — AiHomeCloud

> Full codebase audit performed 2026-03-16
> Auditor: AI Staff Engineer (Claude Opus 4.6)
> Scope: All backend, frontend, CI/CD, deployment, tests, documentation

---

## 1. Executive Summary

AiHomeCloud is a personal home NAS system running on ARM SBC devices (Radxa Cubie A7Z, Rock Pi 4A) with a Flutter mobile app. The project has **solid architectural foundations** but has accumulated technical debt across several rapid development sessions and is not yet production-ready.

**Overall Grade: B-** — Good bones, needs stabilization.

| Dimension | Score | Notes |
|-----------|-------|-------|
| Architecture | A- | Clean separation of concerns, proper async patterns |
| Security | B | TLS pinning, JWT auth, path sandboxing; gaps in token revocation enforcement |
| Backend Code Quality | B | Well-structured but telegram_bot.py is overweight; missing type hints |
| Frontend Code Quality | B+ | Excellent Riverpod patterns; some localization gaps |
| Test Coverage | C+ | Backend 260+ tests; Flutter ~33% screen coverage |
| CI/CD | B- | Workflows pass; missing coverage metrics, APK build verification |
| Deployment | C | Scripts functional but no rollback, no pre-flight checks |
| Documentation | A- | Excellent kb/ docs; stale task files cluttering root |

---

## 2. Architecture Overview

### System Topology

```
┌─────────────────────────┐     HTTPS/WSS (port 8443)     ┌──────────────────┐
│   Flutter Mobile App     │◄──────────────────────────────►│  FastAPI Backend  │
│   (Android)              │   Self-signed TLS + TOFU       │  (ARM SBC)       │
│                          │                                │                  │
│  Riverpod state mgmt     │   REST: /api/v1/*              │  JSON file store │
│  GoRouter navigation     │   WS:   /ws/monitor            │  SQLite FTS5     │
│  TLS cert pinning        │   WS:   /ws/events             │  Subprocess cmds │
│  mDNS + BLE discovery    │                                │  Systemd managed │
└─────────────────────────┘                                └──────────────────┘
                                                                    │
                                                            ┌───────┴───────┐
                                                            │  Telegram Bot  │
                                                            │  (optional)    │
                                                            └───────────────┘
```

### Backend Architecture Map (22 Python files, ~7,680 lines)

| Layer | Files | Lines | Purpose |
|-------|-------|-------|---------|
| **Entry & Config** | main.py, config.py | 587 | FastAPI app, CORS, 14 router registrations, lifespan, settings |
| **Auth & Security** | auth.py, tls.py, audit.py | 260 | JWT, bcrypt, TLS cert gen, audit logging |
| **Persistence** | store.py, job_store.py, db_stub.py | 676 | JSON-file store with locks, TTL cache, atomic writes |
| **Core Logic** | board.py, subprocess_runner.py, events.py, logging_config.py, limiter.py | 514 | Hardware detection, safe subprocess, event bus, structured logging |
| **Features** | telegram_bot.py, document_index.py, file_sorter.py, index_watcher.py, wifi_manager.py, hygiene.py | 2,583 | Telegram bot, OCR search, auto-sort, file watcher, WiFi mgmt |
| **Routes** | 14 route files | 3,062 | REST endpoints, WebSocket handlers, storage helpers |
| **Models** | models.py | 331 | Pydantic v2 with camelCase aliases |

### Frontend Architecture Map (56 Dart files, ~14,740 lines)

| Layer | Files | Lines | Purpose |
|-------|-------|-------|---------|
| **Core** | main.dart, constants.dart, theme.dart, error_utils.dart | 504 | Bootstrap, config, dark theme, error formatting |
| **Services** | api_service.dart + 6 API parts, discovery, scanner, share_handler | 2,419 | HTTP/WS client, TLS pinning, mDNS/BLE discovery |
| **State** | 5 provider files + barrel | 549 | Riverpod providers for all domains |
| **Navigation** | app_router.dart, main_shell.dart | 613 | GoRouter with ShellRoute, bottom nav, banners |
| **Models** | 6 domain model files + barrel | 668 | Immutable data classes with JSON serialization |
| **Screens** | 15 screen files | 7,938 | Onboarding (4) + Main (11) screens |
| **Widgets** | 8 reusable widgets | 1,700 | Cards, tiles, charts, file browser, notification overlay |
| **Localization** | ARB files + generated | 2,082 | English strings (300+ keys) |

### Dependency Graph

```
main.dart
 └─ ProviderScope
     ├─ core_providers.dart
     │   ├─ sharedPreferencesProvider → SharedPreferences
     │   ├─ authSessionProvider → AuthSessionNotifier
     │   ├─ apiServiceProvider → ApiService (singleton)
     │   │   ├─ auth_api.dart (part)
     │   │   ├─ files_api.dart (part)
     │   │   ├─ system_api.dart (part)
     │   │   ├─ storage_api.dart (part)
     │   │   ├─ family_api.dart (part)
     │   │   └─ services_network_api.dart (part)
     │   └─ discoveryServiceProvider → DiscoveryService
     ├─ device_providers.dart
     │   ├─ deviceInfoProvider → FutureProvider
     │   ├─ systemStatsStreamProvider → StreamProvider (WS)
     │   ├─ connectionProvider → StateNotifierProvider
     │   └─ storageStatsProvider / storageDevicesProvider
     ├─ file_providers.dart
     │   ├─ fileListProvider → AsyncNotifierProvider.family
     │   ├─ uploadTasksProvider → StateNotifierProvider
     │   └─ trashItemsProvider / docSearchResultsProvider
     ├─ data_providers.dart
     │   ├─ familyUsersProvider → FutureProvider
     │   ├─ servicesProvider → StateNotifierProvider
     │   └─ notificationStreamProvider → StreamProvider (WS)
     └─ discovery_providers.dart
         ├─ qrPayloadProvider → StateProvider
         └─ discoveryNotifierProvider → StateNotifierProvider
```

### Service Lifecycle

```
                   STARTUP                          RUNTIME                    SHUTDOWN
                   ──────                           ───────                    ────────
1. Board detection                    • REST API handling          1. Cancel background tasks
2. TLS cert generation                • WebSocket streams          2. Stop Telegram bot
3. JWT secret load/gen                • File event publishing      3. Close event subscribers
4. Auto-remount saved disk            • Background file sorting    4. Flush pending writes
5. Telegram bot start                 • Document index watching    5. Close SQLite connections
6. File sorter watcher start          • Telegram message handling  6. Log shutdown
7. Document index watcher start       • Upload processing
8. Token purge (expired/revoked)      • Job tracking
9. PIN migration (legacy)             • Rate limiting
10. Hygiene cleanup                   • Audit logging
11. WiFi auto-disable (if ethernet)
12. Health endpoint ready
```

---

## 3. Backend Audit Findings

### 3.1 Security

| ID | Finding | Severity | File | Status |
|----|---------|----------|------|--------|
| S1 | No `shell=True` anywhere | ✅ GOOD | All subprocess calls | Verified |
| S2 | `_safe_resolve()` path sandboxing | ✅ GOOD | file_routes.py | Null bytes, symlinks, traversal blocked |
| S3 | Timing-safe pairing comparison | ✅ GOOD | auth_routes.py | `hmac.compare_digest()` |
| S4 | Account lockout (10 fails → 15 min) | ✅ GOOD | auth_routes.py | Per-IP tracking |
| S5 | bcrypt via executor (non-blocking) | ✅ GOOD | auth.py | Event loop not blocked |
| S6 | Service ID not validated against whitelist | MEDIUM | service_routes.py | Relies on store lookup as implicit whitelist |
| S7 | `auto_ap.py` referenced but missing | LOW | copilot-instructions.md | Feature not implemented |
| S8 | OTA update endpoint is a stub | LOW | system_routes.py:54 | `TODO: Implement real OTA update logic` |
| S9 | Missing HSTS/X-Frame-Options headers | MEDIUM | main.py | No security headers middleware |
| S10 | Jobs not user-scoped | LOW | jobs_routes.py | Any authenticated user can query any job |

### 3.2 Reliability

| ID | Finding | Severity | File |
|----|---------|----------|------|
| R1 | Startup: 12 try-except blocks; one failure logs but doesn't halt | MEDIUM | main.py |
| R2 | Telegram bot crash → no auto-recovery until restart | MEDIUM | main.py |
| R3 | Job persistence missing — lost on restart | MEDIUM | job_store.py |
| R4 | File sort age check (5s) may catch incomplete uploads | LOW | file_sorter.py |
| R5 | Event subscriber silently dropped when queue full | LOW | events.py |
| R6 | Corrupt JSON renames file, returns `{}` silently | MEDIUM | store.py |
| R7 | Index watcher 20s polling lag | LOW | index_watcher.py |
| R8 | Pending Telegram uploads dict unbounded | LOW | telegram_bot.py |

### 3.3 Code Quality

| ID | Finding | Severity | Scope |
|----|---------|----------|-------|
| Q1 | `telegram_bot.py` is 1,564 lines — needs splitting | MEDIUM | Single file |
| Q2 | Missing type hints on most public functions | LOW | store.py, auth.py, telegram_bot.py |
| Q3 | Missing docstrings on all public functions | LOW | Nearly every module |
| Q4 | Inline imports in telegram_bot.py (~20 instances) | LOW | Performance/readability |
| Q5 | `db_stub.py` (80 lines) — unused feature-flagged code | LOW | Dead code |
| Q6 | Pydantic model alias repetition | LOW | models.py |

### 3.4 Backend Route Inventory (Verified)

| File | Prefix | Endpoints | Auth | Lines |
|------|--------|-----------|------|-------|
| auth_routes.py | `/api/v1` | 14 | Mixed | 474 |
| system_routes.py | `/api/v1/system` | 6 | User/Admin | 121 |
| monitor_routes.py | `/ws` | 1 WS | Token | 216 |
| file_routes.py | `/api/v1/files` | 14 | User | 805 |
| family_routes.py | `/api/v1/users/family` | 4 | User/Admin | 166 |
| service_routes.py | `/api/v1/services` | 2 | User/Admin | 73 |
| storage_routes.py | `/api/v1/storage` | 9 | User/Admin | 543 |
| storage_helpers.py | (internal) | 0 | — | 440 |
| network_routes.py | `/api/v1` | 3 | User | 92 |
| telegram_routes.py | `/api/v1/telegram` | 6 | Admin | 183 |
| telegram_upload_routes.py | `/telegram-upload` | 2 | Token | 359 |
| jobs_routes.py | `/api/v1/jobs` | 1 | User | 27 |
| event_routes.py | `/ws` | 1 WS | Token | 187 |

**Total: 63 endpoints across 13 route files + 1 helper.**

### 3.5 In-Memory State (Resets on Restart)

| Dict | File | Impact |
|------|------|--------|
| `_failed_logins` | auth_routes.py | Login lockout resets — acceptable |
| `_upload_tokens` | telegram_upload_routes.py | Pending upload links lost — 15 min TTL acceptable |
| `_ws_connections_per_user` | monitor_routes.py | Connection tracking resets — acceptable |
| `_pending_uploads` | telegram_bot.py | Unbounded dict — needs TTL |
| `_scan_cache` | file_routes.py | 7s TTL — fine |
| Job store | job_store.py | Active jobs lost — problematic for format operations |

---

## 4. Frontend Audit Findings

### 4.1 Compliance

| Standard | Status | Notes |
|----------|--------|-------|
| `friendlyError(e)` everywhere | ✅ 100% | Zero instances of raw `e.toString()` in lib/ |
| API timeout enforcement | ✅ 100% | All HTTP calls use `.timeout()` |
| Controller disposal | ✅ 95% | All controllers disposed; 1 debounce timer could be safer |
| Riverpod patterns | ✅ 100% | Correct StateNotifier/FutureProvider/StreamProvider usage |
| AppColors/CubieRadii usage | ✅ 100% | No hardcoded color hex literals |
| Path safety (no /dev/ exposed) | ✅ 100% | Backend hides device paths; models filter |

### 4.2 Issues Found

| ID | Finding | Severity | File |
|----|---------|----------|------|
| F1 | Deprecated `.withOpacity()` usage | LOW | splash_screen.dart:144 |
| F2 | 50+ hardcoded English strings in dialogs | MEDIUM | more_screen.dart, family_screen.dart, files_screen.dart |
| F3 | No double-tap guard on upload button | LOW | folder_view.dart |
| F4 | PinEntry debounce timer null-check | LOW | pin_entry_screen.dart |
| F5 | Upload no pause/resume on network loss | LOW | folder_view.dart |
| F6 | Missing empty state messages | LOW | Some screens |
| F7 | `mock_api_service.dart` has 20 TODO placeholders | LOW | Test fixture |

### 4.3 Screen Inventory (Verified)

| Screen | File | Lines | Route | Tested |
|--------|------|-------|-------|--------|
| Splash | splash_screen.dart | 427 | `/` | No |
| Network Scan | network_scan_screen.dart | 339 | `/scan-network` | No |
| PIN Entry | pin_entry_screen.dart | 702 | `/user-picker` | ✅ |
| Profile Creation | profile_creation_screen.dart | 256 | `/profile-creation` | ✅ |
| Dashboard | dashboard_screen.dart | 1,113 | `/dashboard` | ✅ |
| Files | files_screen.dart | 694 | `/files` | ✅ |
| More | more_screen.dart | 873 | `/more` | ✅ |
| Family | family_screen.dart | 398 | `/family` | No |
| Storage Explorer | storage_explorer_screen.dart | 761 | `/storage-explorer` | No |
| Telegram Setup | telegram_setup_screen.dart | 730 | `/telegram-setup` | No |
| File Preview | file_preview_screen.dart | 299 | `/file-preview` | No |
| Folder View | folder_view_screen.dart | 43 | `/folder-view` | No |
| Profile Edit | profile_edit_screen.dart | 683 | `/profile-edit` | No |
| Device Settings | device_settings_screen.dart | 145 | `/settings/device` | No |
| Services Settings | services_settings_screen.dart | 162 | `/settings/services` | No |

**Test coverage: 5/15 screens (33%)**

### 4.4 Widget Inventory (Verified)

| Widget | File | Lines | Tested |
|--------|------|-------|--------|
| AppCard | app_card.dart | 60 | ✅ |
| StatTile | stat_tile.dart | 102 | ✅ |
| FileListTile | file_list_tile.dart | 101 | ✅ |
| FolderView | folder_view.dart | 936 | No |
| StorageDonutChart | storage_donut_chart.dart | 122 | ✅ |
| UserAvatar | user_avatar.dart | 84 | No |
| EmojiPickerGrid | emoji_picker_grid.dart | 219 | No |
| NotificationOverlay | notification_listener.dart | 176 | No |

**Test coverage: 4/8 widgets (50%)**

---

## 5. CI/CD Audit

### 5.1 Workflows

| Workflow | Trigger | Status | Issues |
|----------|---------|--------|--------|
| backend-tests.yml | Push/PR on `backend/**`, `scripts/**` | ✅ Passing | No coverage metrics |
| flutter-analyze.yml | Push/PR on `lib/**`, `test/**` | ✅ Passing | No APK build verification |

### 5.2 CI Gaps

| Gap | Impact |
|-----|--------|
| No pytest coverage metrics (pytest-cov) | Cannot track regression |
| No APK build in CI | Build failures caught only on dev machine |
| No JUnit XML artifact upload | Cannot correlate test failures in PR |
| No Dart security scanning (pub audit equivalent) | Dependency vulnerabilities undetected |
| No pre-commit hooks | Tests only run on PR push |

### 5.3 Test Metrics

| Suite | Pass | Skip | Fail |
|-------|------|------|------|
| Backend (pytest) | 260 | 47 | 0 |
| Flutter (flutter test) | All pass | Golden excluded | 0 |

---

## 6. Deployment Audit

### 6.1 Scripts

| Script | Purpose | Status | Issues |
|--------|---------|--------|--------|
| first-boot-setup.sh | Production install | Works | No rollback, no pre-flight |
| dev-setup.sh | Dev install on SBC | Works | Similar gaps |
| deploy.sh | Remote deploy via SSH | Works | Insecure default (`curl -k`), no rollback |
| setup-telegram-local-api.sh | Telegram local API | Works | No version pinning |
| aihomecloud.service | Systemd unit | Works | Missing resource limits |

### 6.2 Missing: Universal Installer

No single `install.sh` exists. Current setup requires running `first-boot-setup.sh` which:
- ✅ Detects architecture
- ✅ Installs system deps
- ✅ Creates venv + installs Python deps
- ✅ Configures systemd
- ✅ Creates NAS directories
- ❌ Does not configure mDNS (handled by dev-setup.sh only)
- ❌ No health check validation
- ❌ No rollback on failure

### 6.3 Systemd Service Hardening

Current unit has good security (ProtectSystem=strict, NoNewPrivileges, SystemCallFilter). Missing:
- `LimitNOFILE=65536`
- `MemoryMax=1G`
- `CPUQuota=80%`

---

## 7. Documentation Audit

### 7.1 Excellent Documentation

| File | Status |
|------|--------|
| kb/architecture.md | ✅ Comprehensive |
| kb/api-contracts.md | ✅ All endpoints documented |
| kb/engineering-blueprint.md | ✅ Design decisions |
| kb/setup-instructions.md | ✅ Hardware + first-boot |
| kb/hardware.md | ✅ Board specs |
| kb/storage-architecture.md | ✅ Mount/unmount design |
| kb/flutter-patterns.md | ✅ Widget/state patterns |
| kb/backend-patterns.md | ✅ Route/store patterns |
| copilot-instructions.md | ✅ Detailed invariants |

### 7.2 Stale Root Files (Cleanup Needed)

These files in the project root are stale session artifacts:

| File | Age | Action |
|------|-----|--------|
| SESSIONS_1_TO_4_PROMPT.md | Old | Archive or delete |
| FIX_USER_PICKER_PIN.md | Old | Archive or delete |
| FIX_TELEGRAM_SBC_ONLY.md | Old | Archive or delete |
| FIX_EMOJI_AVATAR.md | Old | Archive or delete |
| FIX_DASHBOARD_STORAGE_TILES.md | Old | Archive or delete |
| PROFILE_EDIT_SCREEN.md | Old | Archive or delete |
| OPUS_REBUILD_KB.md | Old | Archive or delete |
| OPUS_AUDIT_PROMPT.md | Old | Archive or delete |
| ALL_AGENT_TASKS.md | Old | Archive or delete |
| TELEGRAM_BOT_POLISH.md | Old | Archive or delete |
| REDESIGN_MORE_SCREEN.md | Old | Archive or delete |
| REDESIGN_DASHBOARD.md | Old | Archive or delete |
| backendAudit.md | Old | Archive or delete |
| _patch_telegram.py | Old | Delete (one-shot patch) |
| _patch2_telegram.py | Old | Delete (one-shot patch) |

### 7.3 Documentation Discrepancies

| Discrepancy | Details |
|-------------|---------|
| copilot-instructions.md references `auto_ap.py` | File does not exist |
| copilot-instructions.md lists 13 route files | Actual: 14 (includes storage_helpers.py) |
| copilot-instructions.md says "61 endpoints" | Verified: 63 endpoints |
| architecture.md family_routes shows 3 endpoints | Actual: 4 (includes PUT role) |

---

## 8. Dead Code & Unused Dependencies

### 8.1 Dead Code

| File | Lines | Issue |
|------|-------|-------|
| db_stub.py | 80 | Feature-flagged SQLite schema, never used |
| mock_api_service.dart | 400 | 20 TODO stubs, partially implemented |
| _patch_telegram.py | — | One-shot migration script |
| _patch2_telegram.py | — | One-shot migration script |

### 8.2 Unused Dependencies

| Package | File | Issue |
|---------|------|-------|
| slowapi | limiter.py | Instantiated but rate limits already applied inline via decorators in routes |
| aiosqlite | Not in requirements.txt | Required by db_stub.py but missing — would crash if `AHC_ENABLE_SQLITE=true` |

---

## 9. Race Conditions Identified

| ID | Description | Severity | File | Mitigation |
|----|-------------|----------|------|------------|
| RC1 | Concurrent file renames on same path | LOW | file_routes.py | `_safe_resolve()` catches most; document behavior |
| RC2 | Trash item collision counter | LOW | file_routes.py | Sequential counter with rename fallback |
| RC3 | Two rapid POSTs to same upload token | LOW | telegram_upload_routes.py | Dict pop is atomic in CPython |
| RC4 | WebSocket connection count tracking | LOW | monitor_routes.py | In-memory, resets on restart |
| RC5 | Cache stampede on TTL expiry | LOW | store.py | Multiple readers hit disk simultaneously |

---

## 10. Performance Observations

| Observation | Impact | File |
|-------------|--------|------|
| Polling-based watchers (20-30s intervals) | Higher CPU on ARM vs inotify | index_watcher.py, file_sorter.py |
| GC runs per job creation (O(n)) | Negligible at current scale | job_store.py |
| Inline imports in telegram_bot.py | ~1ms per handler call | telegram_bot.py |
| SQLite FTS5 opens new connection per query | No connection pooling | document_index.py |
| No gzip compression on API responses | Larger payloads over LAN | main.py |

---

## 11. Conclusion

AiHomeCloud has a **well-designed, modular architecture** with proper security fundamentals (path sandboxing, timing-safe comparisons, TLS pinning, JWT auth). The main areas needing improvement are:

1. **Stability** — Telegram bot resilience, job persistence, startup error handling
2. **Testing** — Flutter screen coverage (33%) needs expansion
3. **Deployment** — Universal installer with rollback and validation
4. **Security hardening** — HSTS headers, service ID whitelist, resource limits
5. **Code quality** — Split telegram_bot.py, add type hints, complete localization
6. **Repository hygiene** — Archive 15 stale root files

The product's core value — simple, private home cloud — is well-served by the current architecture. The path to production readiness is clear and achievable.
