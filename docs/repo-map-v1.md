# Repository Map — CubieCloud v1

> **Generated:** 2026-03-06 | **Commit:** post-Milestone 8 | **Status:** V1 prototype, deployed on hardware

---

## 1. Project Summary

CubieCloud is a personal home NAS appliance built on the Radxa Cubie A7Z (ARM, 8 GB RAM). It consists of a Flutter Android app that pairs with a FastAPI backend running on the device over the local network.

**Active codebase:** ~10,000 lines (Dart + Python)
**Test coverage:** 47 backend tests (passing), 5 Flutter widget tests
**Deployment:** systemd service on ARM SBC, Android APK (63.7 MB)

---

## 2. Directory Tree

```
AiHomeCloud/
│
├── .github/
│   └── copilot-instructions.md        # AI coding rules (loaded by Copilot)
│
├── backend/                            # ── Python/FastAPI backend ──
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py                     # FastAPI entry, lifespan hooks, router registration
│   │   ├── config.py                   # Pydantic Settings (CUBIE_* env vars)
│   │   ├── auth.py                     # JWT create/decode, password hashing, auth deps
│   │   ├── store.py                    # JSON-file persistence, async locks, TTL cache
│   │   ├── models.py                   # Pydantic models (camelCase aliases)
│   │   ├── subprocess_runner.py        # Safe command execution (shell=False, validation)
│   │   ├── job_store.py                # In-memory async job tracking
│   │   ├── logging_config.py           # JSON structured logging, contextvars
│   │   ├── tls.py                      # Self-signed cert generation (openssl)
│   │   ├── board.py                    # Hardware detection (thermal zones, SoC info)
│   │   └── routes/
│   │       ├── auth_routes.py          # /api/v1 — pairing, login, refresh, users, PIN
│   │       ├── system_routes.py        # /api/v1/system — device info, firmware, rename
│   │       ├── monitor_routes.py       # /ws/monitor — live CPU/RAM/Temp stream
│   │       ├── file_routes.py          # /api/v1/files — list, mkdir, upload, download
│   │       ├── storage_routes.py       # /api/v1/storage — devices, format, mount, eject
│   │       ├── family_routes.py        # /api/v1/users — family member CRUD
│   │       ├── service_routes.py       # /api/v1/services — NAS service toggles
│   │       ├── network_routes.py       # /api/v1/network — WiFi, hotspot, BT, LAN
│   │       ├── jobs_routes.py          # /api/v1/jobs — async job status polling
│   │       └── event_routes.py         # /ws/events — real-time notifications
│   ├── tests/
│   │   ├── conftest.py                 # Async fixtures, tmp_path isolation, cache clearing
│   │   ├── test_auth.py               # 19 tests — JWT, login, refresh, PIN change
│   │   ├── test_config.py             # 1 test  — env var parsing
│   │   ├── test_path_safety.py        # 11 tests — traversal, encoding, null bytes
│   │   └── test_storage.py            # 16 tests — format, mount, eject, permissions
│   ├── scripts/
│   │   └── smoke_store.py             # Manual store.py smoke test
│   ├── requirements.txt               # Production + dev dependencies
│   ├── pytest.ini                      # asyncio mode=auto
│   ├── cubie-backend.service           # systemd unit file
│   └── README.md                       # Backend setup instructions
│
├── lib/                                # ── Flutter/Dart mobile app ──
│   ├── main.dart                       # App bootstrap, dev shortcut, TLS trust
│   ├── providers.dart                  # All Riverpod providers (state, future, stream)
│   ├── core/
│   │   ├── constants.dart              # Ports, BLE UUIDs, pref keys, NAS paths
│   │   └── theme.dart                  # Dark theme, CubieColors, CubieTheme
│   ├── models/
│   │   └── models.dart                 # Data classes mirroring backend Pydantic models
│   ├── services/
│   │   ├── api_service.dart            # HTTP + WS client, cert pinning, auto-refresh
│   │   ├── discovery_service.dart      # mDNS + BLE device discovery
│   │   ├── auth_session.dart           # Token storage, session state notifier
│   │   └── mock_api_service.dart       # Test/demo mode API stub
│   ├── navigation/
│   │   ├── app_router.dart             # GoRouter config, onboarding + main routes
│   │   └── main_shell.dart             # Bottom nav shell (5 tabs)
│   ├── screens/
│   │   ├── onboarding/                 # 5 screens: Splash, Welcome, QR, Discovery, Setup
│   │   └── main/                       # 8 screens: Dashboard, MyFolder, Shared, Family,
│   │                                   #            Settings, StorageExplorer, FilePreview,
│   │                                   #            FolderView
│   ├── widgets/                        # 6 reusable: CubieCard, StatTile, FileListTile,
│   │                                   #            FolderView, NotificationListener,
│   │                                   #            StorageDonutChart
│   └── l10n/
│       ├── app_en.arb                  # English string resources
│       ├── app_localizations.dart      # Generated base class
│       └── app_localizations_en.dart   # Generated English delegate
│
├── test/                               # ── Flutter tests ──
│   ├── widgets/                        # 4 widget unit tests
│   ├── screens/                        # 1 dashboard screen test
│   └── goldens/                        # Golden image reference files
│
├── android/                            # ── Android build config ──
│   ├── app/build.gradle                # minSdk 23, targetSdk 34, permissions
│   ├── build.gradle                    # Gradle plugins
│   └── settings.gradle                 # Plugin resolution
│
├── docs/                               # ── Authoritative architecture docs ──
│   └── (this directory)
│
├── kb/                                 # ── AI-session reference docs (legacy) ──
│   ├── engineering-blueprint.md        # Original architecture design
│   ├── api-contracts.md                # Endpoint specifications
│   ├── critique.md                     # Code review findings (some outdated)
│   ├── devops-testing-strategy.md      # Testing strategy document
│   ├── storage-architecture.md         # Storage subsystem design
│   └── hardware.md                     # Cubie A7Z hardware specs
│
├── docs/archive/                       # ── Archived troubleshooting notes ──
│   └── (AI-session artifacts, git errors, crash notes)
│
├── deploy.sh                           # Health check script (TLS-aware)
├── tasks.md                            # Milestone tracker (M1-M3 done, M4+ planned)
├── logs.md                             # Development decision log
├── AI_RULES.md                         # AI development guardrails
├── pubspec.yaml                        # Flutter dependencies (28 packages)
├── analysis_options.yaml               # Dart linter rules
├── l10n.yaml                           # Localization config
└── .gitignore
```

---

## 3. File Classification

### Frontend (Flutter/Dart) — 37 files

| Category | Files | Key Patterns |
|----------|-------|-------------|
| Entry point | `lib/main.dart` | ProviderScope, dev shortcut, TLS HttpOverrides |
| State | `lib/providers.dart` | Riverpod: StateProvider, FutureProvider, StreamProvider, StateNotifier |
| Core | `lib/core/` (2 files) | Constants, Material 3 dark theme |
| Models | `lib/models/` (1 file) | 13 data classes, JSON serialization |
| Services | `lib/services/` (4 files) | Singleton HTTP client, BLE/mDNS discovery, auth session |
| Navigation | `lib/navigation/` (2 files) | GoRouter, ShellRoute bottom nav |
| Screens | `lib/screens/` (13 files) | ConsumerWidget / ConsumerStatefulWidget |
| Widgets | `lib/widgets/` (6 files) | Reusable composable UI components |
| Localization | `lib/l10n/` (3 files) | ARB-based i18n (English only) |
| Tests | `test/` (5 files + goldens) | Widget tests, golden image tests |

### Backend (Python/FastAPI) — 22 files

| Category | Files | Key Patterns |
|----------|-------|-------------|
| Entry point | `main.py` | Lifespan hooks, middleware, router registration |
| Config | `config.py` | Pydantic Settings, `@property` path derivation |
| Auth | `auth.py` | JWT (PyJWT), bcrypt (passlib), FastAPI Depends |
| Persistence | `store.py` | JSON files, asyncio.Lock, TTL cache |
| Models | `models.py` | Pydantic v2, camelCase aliases |
| Routes | `routes/` (10 files) | One router per domain |
| Infrastructure | `subprocess_runner.py`, `job_store.py`, `tls.py`, `board.py`, `logging_config.py` | System integration |
| Tests | `tests/` (5 files) | pytest-asyncio, httpx AsyncClient, tmp_path isolation |

### Deployment — 3 files

| File | Purpose |
|------|---------|
| `deploy.sh` | Remote health check with optional TLS cert |
| `cubie-backend.service` | systemd unit, sandboxed (ProtectSystem=strict) |
| `android/app/build.gradle` | Android build config, permissions |

### Documentation — 15+ files

| Location | Purpose |
|----------|---------|
| `docs/` | Authoritative architecture, plans, workflows |
| `kb/` | Legacy AI-session reference (engineering blueprint, API contracts) |
| `tasks.md` | Milestone tracker |
| `logs.md` | Decision log |
| `.github/copilot-instructions.md` | AI coding instructions |

---

## 4. Architecture Inconsistencies

| Issue | Location | Severity | Notes |
|-------|----------|----------|-------|
| **Monolithic providers file** | `lib/providers.dart` | Medium | 400+ lines, all providers in one file. Should split by domain. |
| **Monolithic models file** | `lib/models/models.dart` | Medium | 13 data classes in one file. Should split by domain. |
| **API service is a god object** | `lib/services/api_service.dart` | Medium | ~60 methods covering all endpoints. Should delegate to domain services. |
| **No service layer in backend** | `backend/app/routes/` | Low | Routes call store directly. Acceptable now, but business logic will grow. |
| **Deploy script references missing endpoint** | `deploy.sh` | Low | Calls `/api/health` which doesn't exist. Needs `/health` route. |
| **Dev shortcut hardcoded** | `lib/main.dart` | Low | `const devMode = true` auto-pairs. Must remove before release. |

---

## 5. Technical Debt

| Item | Impact | Effort | Priority |
|------|--------|--------|----------|
| No integration tests (Flutter) | Risk of UI regressions | High | High |
| No rate limiting on API | Brute-force pairing attacks possible | Medium | High |
| Single-file providers.dart | Hard to navigate, merge conflicts | Low | Medium |
| Single-file models.dart | Same as above | Low | Medium |
| No `/health` endpoint | Deploy script broken | Low | Low |
| File download lacks Range headers | Large files can't resume | Medium | Low |
| Notifications not persisted | Lost on app restart | Low | Low |

---

## 6. AI-Generated Structural Issues

| Issue | Evidence | Fix |
|-------|----------|-----|
| **Scattered troubleshooting files at root** | `gitError.md`, `GitError2.md`, `gitError3.md`, `gitfixes.md`, `crash-diagnosis.md` | Move to `docs/archive/` |
| **Duplicate/redundant docs** | `APP_STATUS.md`, `RUN_APP_SUMMARY.md`, `QUICK_START.md` overlap | Consolidate into single onboarding doc |
| **critique.md contains stale findings** | Says `threading.Lock` but code uses `asyncio.Lock` | Mark as resolved in critique |
| **Test assertions were overly broad** | Many tests accepted status codes `in (200, 400, 403, 404, 500)` | Fixed in recent session — tightened assertions |
| **Fire-and-forget async pattern** | `create_refresh_token` used `create_task` instead of `await` | Fixed — now properly async |

---

## 7. Endpoint Summary

| Router | Prefix | Count | Auth |
|--------|--------|-------|------|
| auth_routes | `/api/v1` | 8 | Mixed |
| system_routes | `/api/v1/system` | 4 | Required |
| monitor_routes | `/ws` | 1 WS | None |
| file_routes | `/api/v1/files` | 6 | Required |
| storage_routes | `/api/v1/storage` | 8 | Required |
| family_routes | `/api/v1/users` | 3 | Required |
| service_routes | `/api/v1/services` | 2 | Required |
| network_routes | `/api/v1/network` | 5 | Required |
| jobs_routes | `/api/v1/jobs` | 1 | Required |
| event_routes | `/ws` | 1 WS | None |
| **Total** | | **39** | |

---

## 8. Data Persistence Map

```
/var/lib/cubie/                 ← CUBIE_DATA_DIR
├── users.json                  ← [{id, name, pin (bcrypt), is_admin}]
├── services.json               ← [{id, name, description, isEnabled}]
├── storage.json                ← {activeDevice, mountpoint, fstype, label}
├── tokens.json                 ← [{jti, userId, issuedAt, expiresAt, revoked}]
├── device_state.json           ← {name}
└── tls/
    ├── cert.pem                ← Self-signed TLS certificate
    └── key.pem                 ← TLS private key

/srv/nas/                       ← CUBIE_NAS_ROOT (external storage mount)
├── personal/
│   └── <username>/             ← Per-user private folder
└── shared/                     ← Family shared folder
```
