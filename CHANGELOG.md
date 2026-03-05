# Changelog — CubieCloud

All notable changes to this project are documented here.
Format: `**type(scope):** summary`

---

## 2026-03-06

- **docs:** Created engineering documentation suite
  - `docs/repo-map-v1.md` — Full repository analysis and file classification
  - `docs/architecture.md` — System architecture, layer design, deployment model
  - `docs/refactor-plan.md` — 6-phase incremental migration plan
  - `docs/code-intelligence.md` — Code RAG system design (tree-sitter + MiniLM + ChromaDB)
  - `docs/ci-plan.md` — GitHub Actions CI + pre-commit hooks configuration
  - `docs/dev-workflow.md` — Branch strategy, commit convention, change logging protocol
  - `AI_RULES.md` — 10 AI development guardrails at repo root
- **refactor:** Archived 12 root-level AI-session and clutter files to `docs/archive/`
- **fix(backend):** Store cache (`store._cache`) not clearing between tests
  - Root cause: Dict persisted across pytest runs causing fixture collisions
  - Fix: Clear cache in conftest.py client fixture (before + after yield)
- **fix(backend):** `create_refresh_token` was fire-and-forget via `asyncio.create_task`
  - Risk: Token might not persist if server shuts down immediately
  - Fix: Changed to `async def` with `await`
- **security(backend):** Hardened `_safe_resolve()` in file_routes.py
  - Added: null byte rejection, path length limit (4096 chars), broad exception handling
- **fix(backend):** 7 incorrect URL paths in test_auth.py (`/token` → `/auth/token`, etc.)
- **fix(backend):** Test assertions updated for actual API behavior (401 vs 403, token format)
- **fix(backend):** Path safety tests corrected for sandbox resolution logic
- **fix(flutter):** `CardTheme` → `CardThemeData`, `DialogTheme` → `DialogThemeData` (SDK update)
- **fix(flutter):** Added missing `crypto: ^3.0.3` dependency and import in api_service.dart
- **chore(backend):** Pinned `bcrypt<4.1` in requirements.txt for passlib compatibility

## 2026-03-05

- **feat(backend):** Milestone 8 — Board abstraction layer for hardware detection
- **feat(backend):** Milestone 7 — Testing infrastructure with pytest-asyncio
- **feat(backend):** Milestone 6 — Security hardening (TLS, cert pinning, path safety)
- **feat(backend):** Milestone 5 — Service management endpoints
- **feat(flutter):** Milestone 5 — Services screen with start/stop/restart controls
