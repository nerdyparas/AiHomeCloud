# Safe Refactoring Plan — CubieCloud

> **Version:** 1.0 | **Date:** 2026-03-06 | **Approach:** Incremental, reversible, git-history-preserving

---

## Guiding Principles

1. **Never break a working system.** Every phase must leave the app buildable and tests passing.
2. **Use `git mv`** for all file moves to preserve history.
3. **One phase per PR.** Each phase is a single, reviewable, revertable commit.
4. **Compatibility layers** where needed — old import paths re-export from new locations during transition.
5. **Validate after every phase** — run `pytest`, `flutter analyze`, `flutter test`.

---

## Phase 1: Freeze Prototype

**Goal:** Tag current state, ensure everything passes, establish baseline.

### Steps

```bash
# 1. Tag the current prototype
git tag v1.0-prototype -m "V1 prototype freeze before architecture refactor"
git push origin v1.0-prototype

# 2. Verify baseline
cd backend && python -m pytest tests/ -v
cd .. && flutter analyze && flutter test

# 3. Record test counts
echo "Backend: $(python -m pytest tests/ --co -q 2>&1 | tail -1)" > docs/baseline.txt
echo "Flutter: $(flutter test 2>&1 | tail -1)" >> docs/baseline.txt
```

### Validation
- [ ] All 47+ backend tests pass
- [ ] `flutter analyze` shows 0 errors
- [ ] All Flutter widget tests pass
- [ ] Git tag `v1.0-prototype` pushed

### Rollback
```bash
git checkout v1.0-prototype
```

### Risk: None. Read-only operations + tag.

---

## Phase 2: Introduce Directory Skeleton + Move Root Clutter

**Goal:** Create target directory structure. Move AI-session artifacts to archive.

### Steps

```bash
# 1. Create docs structure
mkdir -p docs/archive

# 2. Move root-level AI artifacts to archive (git mv preserves history)
git mv gitError.md docs/archive/
git mv GitError2.md docs/archive/
git mv gitError3.md docs/archive/
git mv gitfixes.md docs/archive/
git mv crash-diagnosis.md docs/archive/
git mv APP_STATUS.md docs/archive/
git mv RUN_APP_SUMMARY.md docs/archive/
git mv testingprompt.md docs/archive/
git mv ANDROID_STUDIO_RUN_GUIDE.md docs/archive/
git mv QUICK_START.md docs/archive/
git mv TESTING_GUIDE.md docs/archive/

# 3. Create CHANGELOG.md at root
# (see template below)

# 4. Commit
git add -A
git commit -m "Phase 2: Create docs structure, archive root clutter"
```

### CHANGELOG.md Template

```markdown
# Changelog — CubieCloud

All notable changes to this project are documented here.
Format: [date] [category] summary

## 2026-03-06
- **refactor** Archived 11 root-level AI-session files to docs/archive/
- **fix** Backend test isolation (store cache clearing between tests)
- **fix** Flutter analyze errors (CardThemeData, crypto import)
- **fix** create_refresh_token made async (was fire-and-forget)
- **security** Hardened _safe_resolve() with null byte and path length checks

## 2026-03-05
- **feat** Milestone 8 complete (board abstraction layer)
- **feat** Milestone 7 complete (testing infrastructure)
- **feat** Milestone 6 complete (security hardening)
```

### Validation
- [ ] `flutter analyze` still passes (no source files moved)
- [ ] Backend tests still pass
- [ ] Root directory is cleaner

### Rollback
```bash
git revert HEAD
```

### Risk: Low. Only moves markdown files.

---

## Phase 3: Restructure Backend Layers

**Goal:** Organize backend into api/services/domain/infrastructure layers.

### Phase 3A: Move Routes into api/routes/

```bash
cd backend/app

# Create layer directories
mkdir -p api
mkdir -p services
mkdir -p domain
mkdir -p infrastructure

# Move routes (already in routes/ — just nest under api/)
git mv routes api/routes

# Create api/__init__.py and api/routes/__init__.py
touch api/__init__.py

# Update main.py imports:
# OLD: from .routes import auth_routes, ...
# NEW: from .api.routes import auth_routes, ...
```

**Import compatibility layer** (temporary `routes/__init__.py` at old location):
```python
"""Compatibility re-exports. Remove after Phase 5."""
from app.api.routes import *  # noqa: F401,F403
```

### Phase 3B: Extract Service Layer

For each domain, extract business logic from routes into service files:

```bash
# Create service files (initially thin wrappers)
touch services/__init__.py
touch services/auth_service.py
touch services/file_service.py
touch services/storage_service.py
touch services/family_service.py
touch services/system_service.py
```

**Example: Extracting file_service.py**

Move `_safe_resolve()` and `_file_item()` from `api/routes/file_routes.py` to `services/file_service.py`. Route handler becomes:

```python
# api/routes/file_routes.py (after extraction)
from ...services.file_service import resolve_path, list_directory

@router.get("/list")
async def list_files(path: str, user: dict = Depends(get_current_user)):
    resolved = resolve_path(path)
    return list_directory(resolved, page, page_size, sort_by, sort_dir)
```

### Phase 3C: Move Infrastructure Files

```bash
git mv store.py infrastructure/store.py
git mv subprocess_runner.py infrastructure/subprocess_runner.py
git mv job_store.py infrastructure/job_store.py
git mv tls.py infrastructure/tls.py
git mv board.py infrastructure/board.py
git mv logging_config.py infrastructure/logging_config.py
touch infrastructure/__init__.py
```

### Phase 3D: Organize Domain Models

```bash
git mv models.py domain/models.py
touch domain/__init__.py
touch domain/exceptions.py
```

### Validation (after each sub-phase)
```bash
cd backend
python -m pytest tests/ -v --tb=short
python -c "from app.main import app; print('Import OK')"
```

### Rollback
```bash
git revert HEAD~N..HEAD  # revert N commits from this phase
```

### Risk: Medium. Import paths change. Mitigate with compatibility re-exports.

---

## Phase 4: Restructure Flutter Modules

**Goal:** Split monolithic `providers.dart` and `models/models.dart` into domain-specific files.

### Phase 4A: Split Models

```bash
cd lib/models

# Create domain-specific model files
# Each file gets its classes + imports extracted from models.dart
```

**Splitting strategy:**

| New File | Classes Moved |
|----------|--------------|
| `device.dart` | `CubieDevice`, `SystemStats`, `ConnectionStatus` |
| `storage.dart` | `StorageStats`, `StorageDevice` |
| `files.dart` | `FileItem`, `FileListResponse`, `UploadTask` |
| `user.dart` | `FamilyUser` |
| `service.dart` | `ServiceInfo` |
| `network.dart` | `NetworkStatus` |
| `notification.dart` | `AppNotification` |

**Compatibility layer** — keep `models.dart` as barrel file:
```dart
/// Barrel file — re-exports all models for backward compatibility.
/// Screens can import individual files or this barrel.
export 'device.dart';
export 'storage.dart';
export 'files.dart';
export 'user.dart';
export 'service.dart';
export 'network.dart';
export 'notification.dart';
```

### Phase 4B: Split Providers

```bash
mkdir -p lib/providers

# Create domain-specific provider files
```

**Splitting strategy:**

| New File | Providers Moved |
|----------|----------------|
| `auth_providers.dart` | `authSessionProvider`, `isSetupDoneProvider`, `certFingerprintProvider` |
| `device_providers.dart` | `deviceInfoProvider`, `systemStatsStreamProvider`, `connectionProvider` |
| `storage_providers.dart` | `storageStatsProvider`, `storageDevicesProvider` |
| `file_providers.dart` | `fileListProvider`, `uploadTasksProvider` |
| `family_providers.dart` | `familyUsersProvider` |
| `service_providers.dart` | `servicesProvider`, `networkStatusProvider` |
| `notification_providers.dart` | `notificationStreamProvider`, `notificationHistoryProvider` |

**Compatibility layer** — keep `providers.dart` as barrel:
```dart
/// Barrel file — re-exports all providers.
export 'providers/auth_providers.dart';
export 'providers/device_providers.dart';
// ... etc
```

### Phase 4C: Update Screen Imports

After barrel files are in place, all existing imports (`import '../providers.dart'`, `import '../models/models.dart'`) continue working. No screen changes needed in this phase.

### Validation
```bash
flutter analyze
flutter test
flutter build apk --debug  # full compilation check
```

### Rollback
```bash
git revert HEAD~N..HEAD
```

### Risk: Low. Barrel re-exports mean no import breakage.

---

## Phase 5: Remove Compatibility Layers

**Goal:** Clean up barrel files and old-path re-exports once all imports are updated.

### Steps

1. **Search for old imports** across all `.dart` and `.py` files
2. **Update each file** to use new direct imports
3. **Remove barrel re-export files** (or keep them slim)
4. **Remove Python compatibility `__init__.py` re-exports**

```bash
# Find all old-style imports in Flutter
grep -rn "import.*providers\.dart" lib/ --include="*.dart"
grep -rn "import.*models/models\.dart" lib/ --include="*.dart"

# Find all old-style imports in Python
grep -rn "from.*\.routes\." backend/app/ --include="*.py"
grep -rn "from.*\.store " backend/app/ --include="*.py"
```

### Validation
```bash
flutter analyze && flutter test
cd backend && python -m pytest tests/ -v
```

### Risk: Low if Phase 4 barrel files worked correctly.

---

## Phase 6: Enforce Architecture Rules

**Goal:** Add CI checks and linting rules that prevent structural regressions.

### 6A: Import Linting (Python)

Add to CI pipeline:
```bash
# Ensure routes don't import store directly (must go through services)
! grep -rn "from.*infrastructure.*import" backend/app/api/ && echo "OK: Routes don't bypass services"

# Ensure domain has no framework imports
! grep -rn "from fastapi" backend/app/domain/ && echo "OK: Domain is framework-free"
```

### 6B: Import Linting (Dart)

Add custom analysis rule or CI check:
```bash
# Ensure screens don't import api_service directly (must go through providers)
! grep -rn "import.*api_service" lib/screens/ && echo "OK: Screens use providers"
```

### 6C: File Size Limits

```bash
# No single file exceeds 400 lines (warn) or 600 lines (fail)
find lib/ -name "*.dart" -exec awk 'END{if(NR>600)print FILENAME": "NR" lines"}' {} \;
find backend/app/ -name "*.py" -exec awk 'END{if(NR>400)print FILENAME": "NR" lines"}' {} \;
```

### 6D: Directory Rules

Enforce via `AI_RULES.md` + CI:
- No new directories at project root
- No new files in `backend/app/` root (must go in a layer)
- No new providers in `lib/providers.dart` (must go in `lib/providers/`)

---

## Migration Timeline

| Phase | Scope | Impact | Suggested Order |
|-------|-------|--------|-----------------|
| Phase 1 | Tag + baseline | None | Do first |
| Phase 2 | Archive root clutter | None | Do second |
| Phase 4A | Split Flutter models | Low | Do early (small, safe) |
| Phase 4B | Split Flutter providers | Low | After 4A |
| Phase 3A | Move backend routes | Medium | After 4B |
| Phase 3B | Extract services | Medium | After 3A |
| Phase 3C | Move infrastructure | Medium | After 3B |
| Phase 3D | Organize domain | Low | After 3C |
| Phase 5 | Remove compat layers | Low | After all above stable |
| Phase 6 | Enforce rules | None | Last |

**Total estimated phases:** 10 atomic commits, each independently revertable.
