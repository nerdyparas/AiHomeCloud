# AI Development Rules — CubieCloud

> These rules apply to all AI assistants (Copilot, Claude, ChatGPT, etc.) working on this codebase.
> Read this file before making any changes.

---

## Rule 1: No New Root Directories

**Do not** create new directories at the project root.

Allowed root directories: `android/`, `backend/`, `build/`, `docs/`, `kb/`, `lib/`, `test/`, `.git/`, `.github/`, `.dart_tool/`, `.idea/`

If you need a new top-level directory, propose it in the conversation first.

---

## Rule 2: Follow Architecture Layers

### Backend (Python)

```
backend/app/
├── api/routes/       ← HTTP handlers only (thin)
├── services/         ← Business logic
├── domain/           ← Models, exceptions (no framework imports)
├── infrastructure/   ← Store, subprocess, TLS, hardware
├── auth.py           ← JWT authentication
├── config.py         ← Settings
└── main.py           ← App entry point
```

**Rules:**
- Route handlers must not contain business logic — delegate to services
- Services must not import FastAPI types (Request, Response, Depends)
- Domain models must not import from infrastructure or api layers
- Store operations go through services, not called directly from routes

> **Note:** The backend is currently flat (not yet restructured). Follow the target layout for any *new* files. Existing files will be migrated per `docs/refactor-plan.md`.

### Frontend (Flutter)

```
lib/
├── core/             ← Constants, theme
├── models/           ← Data classes (split by domain)
├── providers/        ← Riverpod providers (split by domain)
├── services/         ← API service, discovery, BLE
├── navigation/       ← GoRouter, shell
├── screens/          ← UI screens
└── widgets/          ← Reusable UI components
```

**Rules:**
- Screens must not import `ApiService` directly — use providers
- Providers must not contain UI logic
- Models must be pure data classes (no HTTP or provider imports)

> **Note:** `providers.dart` and `models/models.dart` are currently monolithic. Follow the target split for new additions. Existing code will be migrated per `docs/refactor-plan.md`.

---

## Rule 3: Modify Existing Files First

Before creating a new file, check if an existing file already handles that concern.

- New API endpoint? Add to existing route file in `backend/app/routes/`
- New model? Add to existing `models.py` (or the appropriate domain model file after split)
- New provider? Add to existing `providers.dart` (or the appropriate domain provider file after split)
- New widget? Check `lib/widgets/` for similar components first

Only create new files when the existing file would exceed 400 lines or the concern is clearly distinct.

---

## Rule 4: Match Model Conventions

- **Backend models:** Pydantic v2 with `Field(alias="camelCase")`
- **Frontend models:** Dart classes with `fromJson`/`toJson` using camelCase keys
- **Field names must match** between backend and frontend

Example:
```python
# Backend
class StorageDevice(BaseModel):
    device_name: str = Field(alias="deviceName")
    total_bytes: int = Field(alias="totalBytes")
```
```dart
// Frontend
class StorageDevice {
  final String deviceName;
  final int totalBytes;
  factory StorageDevice.fromJson(Map<String, dynamic> json) => ...
}
```

---

## Rule 5: Security Non-Negotiables

1. **All file operations** must go through `_safe_resolve()` — never construct paths manually
2. **All API endpoints** must use `Depends(get_current_user)` unless explicitly public
3. **Never hardcode** IPs, passwords, secrets, or API keys
4. **All HTTP calls** in `ApiService` must include `.timeout(_timeout)`
5. **Validate user input** at the API boundary (Pydantic models handle this)

---

## Rule 6: Test Everything You Change

- New backend endpoint → add test in `backend/tests/`
- Modified backend logic → update existing tests
- Run `python -m pytest tests/ -v` before finalizing
- Run `flutter analyze` before finalizing Flutter changes
- Never skip tests or use `@pytest.mark.skip` without a documented reason

---

## Rule 7: Update the Changelog

After every change, add an entry to `CHANGELOG.md`:

```markdown
- **<type>(<scope>):** <one-line summary>
  - Root cause: <why> (for bugs)
  - Fix: <what was done>
```

Types: `feat`, `fix`, `refactor`, `security`, `test`, `docs`, `chore`, `perf`
Scopes: `backend`, `flutter`, `deploy`, `ci`, `docs`

---

## Rule 8: Experimental Code Goes in Sandbox

If you need to prototype something that doesn't fit the current architecture:

1. Create a branch: `experiment/<name>`
2. Or place files in `backend/app/sandbox/` or `lib/sandbox/`
3. Never merge experimental code directly into production modules
4. Delete sandbox code once the experiment concludes

---

## Rule 9: Keep Files Under 400 Lines

- **Warning** at 400 lines — consider splitting
- **Hard limit** at 600 lines — must split before merging
- Split by domain or responsibility, not arbitrarily

---

## Rule 10: Read Before You Write

Before modifying any part of the codebase:

1. **Read `tasks.md`** — current priorities and milestone status
2. **Read `CHANGELOG.md`** — recent changes
3. **Read this file** — the rules you're following right now
4. **Read `docs/architecture.md`** — system design decisions
5. **Read the target file** — understand context before editing

---

## Quick Reference

| Question | Answer |
|----------|--------|
| Where do new backend endpoints go? | `backend/app/routes/<domain>_routes.py` |
| Where do new models go? | `backend/app/models.py` + `lib/models/models.dart` |
| Where do new providers go? | `lib/providers.dart` (barrel) or `lib/providers/<domain>.dart` |
| Where do new screens go? | `lib/screens/main/<name>_screen.dart` |
| Where do docs go? | `docs/` for architecture, `kb/` for legacy reference |
| How to add a route to nav? | `lib/navigation/app_router.dart` + `main_shell.dart` |
| What port does backend use? | 8443 (TLS) |
| What's the NAS root? | `/srv/nas` |
| What's the data dir? | `/var/lib/cubie` |
