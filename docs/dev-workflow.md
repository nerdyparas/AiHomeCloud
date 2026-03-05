# Development Workflow — CubieCloud

> **Version:** 1.0 | **Date:** 2026-03-06

---

## Branch Strategy

### Branches

| Branch | Purpose | Merges Into | Protection |
|--------|---------|-------------|------------|
| `main` | Production-ready code | — | CI must pass, no force push |
| `develop` | Integration branch | `main` | CI must pass |
| `feat/<name>` | New features | `develop` | None |
| `fix/<name>` | Bug fixes | `develop` or `main` (hotfix) | None |
| `refactor/<name>` | Architecture changes | `develop` | None |

### Workflow

```
feat/storage-widgets ──┐
fix/upload-timeout ────┤──▶ develop ──▶ main (tag vX.Y.Z)
refactor/split-models ─┘
```

**For solo development (current):** Working directly on `main` is acceptable. Switch to branching when adding collaborators or before production deployment.

---

## Commit Convention

```
<type>(<scope>): <short description>

[optional body]

[optional footer]
```

### Types

| Type | When |
|------|------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `refactor` | Code restructuring (no behavior change) |
| `docs` | Documentation only |
| `test` | Adding or fixing tests |
| `ci` | CI/CD configuration |
| `chore` | Dependencies, config, tooling |
| `security` | Security improvement |
| `perf` | Performance improvement |

### Scopes

| Scope | Covers |
|-------|--------|
| `backend` | Python/FastAPI backend |
| `flutter` | Dart/Flutter mobile app |
| `deploy` | Deployment, systemd, scripts |
| `docs` | Documentation |
| `ci` | CI/CD pipelines |

### Examples

```
feat(backend): add WebSocket endpoint for real-time file sync
fix(flutter): upload timeout on large files over slow WiFi
refactor(backend): extract file service from file_routes.py
security(backend): add null byte rejection to _safe_resolve
docs: create architecture and refactor plan
test(backend): add path traversal attack test cases
```

---

## Task Management

### File: `tasks.md`

Central task tracker at repo root. Structure:

```markdown
## Milestone N: <Name>
Status: todo | in-progress | done

### Tasks
- [x] Completed task description
- [ ] Pending task description
```

### Task Lifecycle

```
1. Write task in tasks.md under current milestone
2. Create branch (if using branch strategy): feat/<task-name>
3. Mark task in-progress
4. Implement change
5. Update CHANGELOG.md with entry
6. Run tests locally
7. Commit with conventional message
8. Mark task done in tasks.md
9. Push / merge
```

---

## Structured Change Logging

### Purpose

Every bug, error, fix, and change is logged with a timeline for backtracing.

### File: `CHANGELOG.md` (root)

```markdown
# Changelog — CubieCloud

All notable changes are documented here with dates and categories.

## [Unreleased]

## 2026-03-06
- **fix(backend):** Store cache not clearing between tests — tests interfering with each other
  - Root cause: `store._cache` dict persisted across test runs
  - Fix: Clear cache in conftest.py client fixture (before + after yield)
- **fix(backend):** `create_refresh_token` was fire-and-forget via `asyncio.create_task`
  - Risk: Token might not persist if server shuts down immediately
  - Fix: Changed to `async def` with `await`
- **security(backend):** Hardened `_safe_resolve()` path validation
  - Added: null byte rejection, path length limit (4096), exception handling
- **fix(flutter):** `CardTheme` → `CardThemeData`, `DialogTheme` → `DialogThemeData`
  - Cause: Flutter SDK update changed class names
- **fix(flutter):** Missing `crypto` import in api_service.dart
- **docs:** Created architecture documentation suite (7 documents)

## 2026-03-05
- **feat(backend):** Milestone 8 — board abstraction layer for hardware detection
- **feat(backend):** Milestone 7 — testing infrastructure with pytest-asyncio
- **feat(backend):** Milestone 6 — security hardening (TLS, cert pinning)
```

### Change Entry Format

```markdown
- **<type>(<scope>):** <one-line summary>
  - Root cause: <why it happened> (for bugs)
  - Fix/Change: <what was done>
  - Impact: <what's affected> (optional)
  - Files: <key files changed> (optional, for complex changes)
```

### When to Log

| Event | Log? | Category |
|-------|------|----------|
| Bug fix | Yes | `fix` |
| New feature | Yes | `feat` |
| Security patch | Yes | `security` |
| Refactor | Yes | `refactor` |
| Dependency update | Yes | `chore` |
| Config change | Yes | `chore` |
| Documentation only | Optional | `docs` |
| Code style/formatting | No | — |

---

## AI-Assisted Development Protocol

### Before Starting Any AI Session

1. **Read `tasks.md`** — know what's in progress and what's next
2. **Read `CHANGELOG.md`** — know recent changes and context
3. **Read `AI_RULES.md`** — know the guardrails
4. **Check `docs/`** — reference architecture decisions before proposing changes

### During AI Session

1. **One feature per session** — avoid mixing concerns
2. **Test after every change** — run `pytest` / `flutter analyze` before moving on
3. **Commit atomically** — one logical change per commit
4. **Update CHANGELOG.md** before committing

### AI Prompting Best Practices

| Do | Don't |
|----|-------|
| "Add a GET endpoint for /api/services/{name}/logs" | "Add some logging feature" |
| "Split providers.dart into domain-specific files per docs/refactor-plan.md" | "Clean up the code" |
| "Fix the 401 error when refresh token expires" | "Fix authentication" |
| Reference specific files and line numbers | Assume the AI knows the codebase |
| Paste error messages / stack traces | Describe errors vaguely |

### AI Context Injection

When starting a complex task, front-load context:

```
Read these files first:
1. tasks.md (current priorities)
2. AI_RULES.md (guardrails)
3. docs/architecture.md (system design)
4. [specific files relevant to the task]

Then: [describe the task]
```

---

## Code Review Checklist

Before merging any change (self-review for solo dev):

### Correctness
- [ ] Does the feature work as described?
- [ ] Are edge cases handled?
- [ ] Do all tests pass?

### Security
- [ ] No hardcoded secrets or IPs
- [ ] File paths sandboxed through `_safe_resolve()`
- [ ] API endpoints have proper auth (`Depends(get_current_user)`)
- [ ] User input validated at API boundary

### Architecture
- [ ] Follows layer boundaries (screens → providers → API service → backend)
- [ ] No new root-level directories without approval
- [ ] File stays under 400 lines (warn at 400, block at 600)
- [ ] Models use camelCase aliases to match Flutter

### Documentation
- [ ] CHANGELOG.md updated with entry
- [ ] Complex logic has inline comments
- [ ] New endpoints documented in API contracts

### Testing
- [ ] New backend endpoints have test cases
- [ ] Error paths tested (401, 403, 404, 422)
- [ ] Path safety tests for any new file operations

---

## Local Development Setup

### Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # or .venv\Scripts\activate on Windows
pip install -r requirements.txt
pip install pre-commit && pre-commit install

# Run locally
uvicorn app.main:app --reload --port 8443

# Run tests
python -m pytest tests/ -v
```

### Flutter

```bash
flutter pub get
flutter analyze
flutter test

# Build debug APK
flutter build apk --debug

# Run on device
flutter run
```

### Full Validation (before push)

```bash
# Backend
cd backend && python -m pytest tests/ -v && cd ..

# Flutter
flutter analyze --fatal-warnings
flutter test

# Pre-commit (if installed)
pre-commit run --all-files
```

---

## Release Process (Future)

```
1. Ensure all tests pass on develop
2. Update CHANGELOG.md — move [Unreleased] items under version header
3. Bump version in pubspec.yaml
4. Merge develop → main
5. Tag: git tag vX.Y.Z -m "Release X.Y.Z"
6. Push: git push origin main --tags
7. CI builds APK artifact
8. Deploy backend to Cubie (manual or CI)
```
