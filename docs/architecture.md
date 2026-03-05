# Architecture — CubieCloud

> **Version:** 2.0 | **Date:** 2026-03-06 | **Status:** Approved target architecture

---

## 1. System Overview

CubieCloud is a single-product system with two deployable units:

```
┌─────────────────────┐         HTTPS/WSS          ┌─────────────────────────┐
│   Flutter Android   │ ◄──────────────────────────►│   FastAPI Backend       │
│   Mobile App        │        LAN (port 8443)      │   (Cubie A7Z device)    │
│                     │                              │                         │
│  • Riverpod state   │                              │  • JSON-file store      │
│  • GoRouter nav     │                              │  • systemd service      │
│  • BLE/mDNS pair    │                              │  • TLS (self-signed)    │
└─────────────────────┘                              └─────────────────────────┘
         │                                                      │
         │  APK install                                         │  ARM SBC
         ▼                                                      ▼
   Android phone                                     Radxa Cubie A7Z
   (user's device)                                   + external USB/NVMe
```

**Key constraints:**
- Single device, ≤8 concurrent family users
- LAN-only (no cloud, no internet dependency)
- ARM SoC, 8 GB RAM, microSD boot, external NAS storage
- CPU-only compute (no GPU — future AI features must be lightweight)

---

## 2. Component Diagram

```
┌── Mobile App (lib/) ──────────────────────────────────────────┐
│                                                                │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  ┌──────────────┐  │
│  │ Screens │──│ Providers│──│ Services  │──│ Models       │  │
│  │ (UI)    │  │ (State)  │  │ (API/IO)  │  │ (Data)       │  │
│  └─────────┘  └──────────┘  └───────────┘  └──────────────┘  │
│       │                           │                            │
│  ┌─────────┐                ┌───────────┐                      │
│  │ Widgets │                │ Navigation│                      │
│  │ (Shared)│                │ (Router)  │                      │
│  └─────────┘                └───────────┘                      │
└────────────────────────────────┬───────────────────────────────┘
                                 │ HTTPS / WebSocket
┌── Backend (backend/app/) ──────┴───────────────────────────────┐
│                                                                 │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐  ┌──────────────┐   │
│  │ Routes  │──│ Auth     │──│ Store     │──│ Models       │   │
│  │ (API)   │  │ (JWT)    │  │ (JSON IO) │  │ (Pydantic)   │   │
│  └─────────┘  └──────────┘  └───────────┘  └──────────────┘   │
│       │                           │                             │
│  ┌─────────┐  ┌──────────┐  ┌───────────┐                      │
│  │ Jobs    │  │ Subprocess│  │ Config   │                      │
│  │ (Async) │  │ (Runner)  │  │ (Settings)│                     │
│  └─────────┘  └──────────┘  └───────────┘                      │
└─────────────────────────────────────────────────────────────────┘
         │                              │
    ┌────┴────┐                   ┌─────┴──────┐
    │ systemd │                   │ Filesystem │
    │ services│                   │ /srv/nas   │
    │ (smbd,  │                   │ /var/lib/  │
    │  nfsd)  │                   │  cubie/    │
    └─────────┘                   └────────────┘
```

---

## 3. Backend Architecture

### Current Structure (Flat)

```
backend/app/
├── main.py              # Entry point, middleware, lifespan
├── config.py            # Settings singleton
├── auth.py              # JWT + password utilities
├── store.py             # All JSON persistence
├── models.py            # All Pydantic models
├── subprocess_runner.py # Safe command execution
├── job_store.py         # Async job tracking
├── logging_config.py    # Structured logging
├── tls.py               # Certificate generation
├── board.py             # Hardware detection
└── routes/              # HTTP/WS endpoints (10 routers)
```

### Target Structure (Layered)

```
backend/app/
├── main.py                     # Entry point (unchanged)
├── config.py                   # Settings (unchanged)
│
├── api/                        # ── Presentation Layer ──
│   ├── routes/                 # HTTP/WS endpoint handlers
│   │   ├── auth_routes.py
│   │   ├── file_routes.py
│   │   ├── storage_routes.py
│   │   └── ...
│   ├── deps.py                 # Shared FastAPI dependencies
│   └── middleware.py           # Request ID, logging middleware
│
├── services/                   # ── Business Logic Layer ──
│   ├── auth_service.py         # Token management, password ops
│   ├── file_service.py         # Path resolution, file operations
│   ├── storage_service.py      # Device management, mount logic
│   ├── family_service.py       # User management business rules
│   └── system_service.py       # Device info, firmware logic
│
├── domain/                     # ── Domain Models ──
│   ├── models.py               # Pydantic request/response models
│   ├── entities.py             # Internal data structures
│   └── exceptions.py           # Domain-specific exceptions
│
├── infrastructure/             # ── External Integrations ──
│   ├── store.py                # JSON-file persistence
│   ├── subprocess_runner.py    # OS command execution
│   ├── job_store.py            # Job tracking
│   ├── tls.py                  # TLS certificate management
│   ├── board.py                # Hardware detection
│   └── logging_config.py       # Logging setup
│
└── tests/                      # ── Test Suite ──
    ├── conftest.py
    ├── unit/                   # Pure logic tests
    ├── integration/            # API endpoint tests
    └── fixtures/               # Shared test data
```

### Layer Responsibilities

| Layer | Purpose | Depends On | Rules |
|-------|---------|-----------|-------|
| **api/** | HTTP request handling, input validation, response formatting | services, domain | No business logic. No direct store access. |
| **services/** | Business rules, orchestration, authorization checks | domain, infrastructure | No HTTP concepts. No FastAPI imports. |
| **domain/** | Data models, entities, domain exceptions | Nothing | Pure Python. No I/O. No framework imports. |
| **infrastructure/** | File I/O, subprocess calls, external system integration | domain | No business logic. Replaceable implementations. |

### Why This Layering

1. **Routes stay thin** — Handlers validate input, call a service, return response. No business decisions.
2. **Services are testable** — Business logic can be unit-tested without HTTP or filesystem.
3. **Infrastructure is swappable** — JSON store could become SQLite without touching services.
4. **LLM-friendly** — Each layer has a clear purpose. An AI agent can be told "modify the file service" without needing to understand routes or persistence.

---

## 4. Mobile Architecture

### Current Structure

```
lib/
├── main.dart            # Bootstrap
├── providers.dart       # ALL providers (400+ lines)
├── core/                # Constants + theme
├── models/models.dart   # ALL data classes
├── services/            # API client, discovery, auth
├── navigation/          # Router + shell
├── screens/             # 13 screens
└── widgets/             # 6 reusable widgets
```

### Target Structure

```
lib/
├── main.dart                    # Bootstrap (unchanged)
│
├── core/                        # ── Foundation ──
│   ├── constants.dart           # App-wide constants
│   ├── theme.dart               # Theme definition
│   └── extensions.dart          # Dart extension methods (if needed)
│
├── models/                      # ── Data Layer ──
│   ├── device.dart              # CubieDevice, SystemStats
│   ├── storage.dart             # StorageStats, StorageDevice
│   ├── files.dart               # FileItem, FileListResponse
│   ├── user.dart                # FamilyUser
│   ├── service.dart             # ServiceInfo
│   └── network.dart             # NetworkStatus
│
├── services/                    # ── External Communication ──
│   ├── api_service.dart         # HTTP + WS client (singleton)
│   ├── discovery_service.dart   # mDNS + BLE
│   ├── auth_session.dart        # Token state management
│   └── mock_api_service.dart    # Test stub
│
├── providers/                   # ── State Management ──
│   ├── auth_providers.dart      # Auth session, setup state
│   ├── device_providers.dart    # Device info, system stats stream
│   ├── storage_providers.dart   # Storage stats, devices
│   ├── file_providers.dart      # File listing, upload tasks
│   ├── family_providers.dart    # Family users
│   ├── service_providers.dart   # NAS services, network status
│   └── notification_providers.dart # Event stream, history
│
├── navigation/                  # ── Routing ──
│   ├── app_router.dart          # GoRouter config
│   └── main_shell.dart          # Bottom nav shell
│
├── screens/                     # ── Screen-Level UI ──
│   ├── onboarding/              # Splash, Welcome, QR, Discovery, Setup
│   └── main/                    # Dashboard, MyFolder, Shared, Family,
│                                # Settings, StorageExplorer, FilePreview
│
└── widgets/                     # ── Reusable Components ──
    ├── cubie_card.dart
    ├── stat_tile.dart
    ├── file_list_tile.dart
    ├── folder_view.dart
    ├── notification_listener.dart
    └── storage_donut_chart.dart
```

### Key Changes

| Change | Why |
|--------|-----|
| Split `providers.dart` → `providers/` directory | 400-line file is hard to navigate. Domain grouping enables targeted reads. |
| Split `models/models.dart` → per-domain files | Each model file is self-contained. LLM reads only what it needs. |
| Keep `services/` flat | 4 files is manageable. API service stays monolithic until >80 methods. |
| Keep `screens/` structure unchanged | Already well-organized by flow (onboarding vs main). |

---

## 5. Deployment Architecture

```
┌─ Cubie A7Z Device ─────────────────────────────────────────┐
│                                                             │
│  systemd                                                    │
│  ┌─────────────────────┐   ┌────────────────────────────┐  │
│  │ cubie-backend.service│   │ smbd / nfsd / sshd / minidlnad│
│  │ (FastAPI on :8443)  │   │ (NAS services)             │  │
│  └─────────┬───────────┘   └────────────┬───────────────┘  │
│            │                             │                   │
│  ┌─────────┴─────────────────────────────┴───────────────┐  │
│  │                    /srv/nas/                           │  │
│  │     (external USB pen drive or NVMe SSD)              │  │
│  │     ├── personal/<user>/                              │  │
│  │     └── shared/                                       │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  /var/lib/cubie/          ← config + state (on microSD)    │
│  /opt/cubie/backend/      ← application code               │
│  /opt/cubie/backend/venv/ ← Python virtual environment     │
└─────────────────────────────────────────────────────────────┘
```

### Hardware Constraints

| Resource | Spec | Architecture Impact |
|----------|------|-------------------|
| CPU | ARM Cortex-A55 (quad-core) | No heavy computation. Async I/O everywhere. |
| RAM | 8 GB | JSON store fits entirely. No need for database until >10K files. |
| Boot disk | microSD (≤64 GB) | OS + app code only. No user data on SD. |
| NAS disk | USB 3.0 or NVMe (user-provided) | Must handle hot-plug, format, mount/unmount. |
| Network | Ethernet + WiFi | LAN-only. mDNS for discovery. BLE for initial pairing. |
| TLS | Self-signed certs | No CA. Cert pinning in app. Fingerprint exchange via QR. |

### Security Model

```
Mobile App ──(TLS 1.3 + cert pin)──► Backend (:8443)
     │                                    │
     │ JWT Bearer token                   │ systemd sandboxing:
     │ (access + refresh)                 │  - ProtectSystem=strict
     │                                    │  - ReadWritePaths=/var/lib/cubie /srv/nas
     │ OTP pairing flow                   │  - PrivateTmp=yes
     │ (6-digit, 10-min expiry)           │  - NoNewPrivileges=yes
     ▼                                    ▼
  SharedPreferences                 JSON files (atomic writes)
  (token storage)                   (asyncio.Lock protection)
```

---

## 6. Future AI Feature Integration

### Design Principles for AI on ARM

1. **CPU-only inference** — No GPU available. Use ONNX Runtime or llama.cpp with quantized models.
2. **Background-only** — AI tasks must not block API responses. Use job queue (existing `job_store.py`).
3. **Incremental indexing** — Index files on upload/change, not bulk scans.
4. **Local-first** — No cloud API calls. All inference runs on-device.

### Planned AI Architecture

```
backend/app/
└── ai/                          # Future AI subsystem
    ├── indexer.py               # File content extraction + chunking
    ├── embeddings.py            # Sentence embedding (MiniLM or similar)
    ├── vector_store.py          # ChromaDB or SQLite-vss local store
    ├── search_service.py        # Semantic search over indexed files
    └── scheduler.py             # Background job scheduling for indexing
```

### Integration Points

| Feature | How It Connects | Resource Budget |
|---------|----------------|-----------------|
| **Semantic file search** | New route `/api/v1/files/search?q=...` | <500 MB RAM, <2s per query |
| **Auto-tagging** | Post-upload hook in file_routes → indexer | Background job, <30s per file |
| **Smart folders** | Virtual folder views based on embeddings | Read-only, cached results |
| **Content summaries** | On-demand via job queue | Background, user-initiated |

### Model Constraints (ARM Cortex-A55)

| Model | Size | Inference | Suitable |
|-------|------|-----------|----------|
| all-MiniLM-L6-v2 (ONNX) | 80 MB | ~100ms/query | Yes — embeddings |
| TinyLlama 1.1B (Q4) | 600 MB | ~5s/query | Marginal — summaries only |
| Phi-2 (Q4) | 1.6 GB | ~15s/query | No — too slow for interactive |

**Recommendation:** Start with MiniLM for embeddings + semantic search. Defer generative AI until hardware upgrade or cloud offload decision.

---

## 7. Structure Decision: Flat vs Monorepo

### Current: Flat (Recommended to Keep)

```
AiHomeCloud/
├── backend/     # Python
├── lib/         # Flutter (required by Dart tooling)
├── android/     # Android build
├── test/        # Flutter tests
├── docs/        # Documentation
└── pubspec.yaml # Flutter manifest
```

**Pros:**
- Flutter CLI requires `lib/` at project root
- Single `pubspec.yaml`, single `flutter run`
- Simple CI — one checkout, both stacks available
- IDE support works out of the box

**Cons:**
- Backend and frontend share git history (noisy diffs)
- Can't independently version backend vs app

### Alternative: Monorepo (Not Recommended Now)

```
AiHomeCloud/
├── packages/
│   ├── mobile/        # Flutter project (its own pubspec.yaml)
│   │   ├── lib/
│   │   ├── test/
│   │   └── pubspec.yaml
│   └── backend/       # Python project
│       ├── app/
│       └── requirements.txt
├── deployment/
├── docs/
└── Makefile
```

**Pros:**
- Clean separation
- Independent versioning

**Cons:**
- Flutter tooling expects `lib/` at workspace root
- IDE reconfiguration needed
- CI becomes multi-step
- Overkill for single-product, single-developer

**Decision:** Keep flat structure. Improve internal layering instead.

---

## 8. LLM-Friendly Architecture Principles

These principles ensure the codebase remains navigable for AI coding assistants as it grows:

1. **One concern per file** — Split 400-line `providers.dart` into domain-specific files. An LLM can read `storage_providers.dart` (50 lines) instead of scanning 400 lines for context.

2. **Predictable naming** — `*_routes.py`, `*_service.py`, `*_providers.dart`. An AI can infer file purpose from name alone.

3. **Flat over deep** — Maximum 3 levels of nesting. Deep hierarchies waste tokens on path resolution.

4. **Index files for navigation** — Each directory should have a clear entry point or barrel file that lists its contents.

5. **Inline architecture markers** — Use structured comments at the top of each file:
   ```python
   """
   Storage device management service.
   Layer: services
   Depends: infrastructure/store, infrastructure/subprocess_runner
   Used by: api/routes/storage_routes
   """
   ```

6. **Changelog as context** — `CHANGELOG.md` with structured entries lets an LLM understand recent changes without reading git log.
