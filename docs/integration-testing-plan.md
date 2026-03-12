# Integration Test Strategy — Backend + Frontend Compatibility

**Date:** March 12, 2026
**Status:** Planning
**Related:** TASK-023 (No integration test job in CI)

## Overview

This document outlines a plan to add integration testing that validates **backend + frontend API contract compatibility** in CI/CD. The goal is to catch mismatches between backend endpoints and frontend API calls early, before deployment to device hardware.

## Problem

- **Current state:** CI has two separate workflows:
  - `flutter-analyze.yml` — Flutter linting & widget tests
  - `backend-tests.yml` — Backend unit tests & security scans
  - Both test in isolation; no validation they work together
  
- **Gap:** No job validates that:
  - Backend endpoint request/response schemas match what Flutter `ApiService` expects
  - Frontend models can deserialize actual backend responses
  - New API changes don't break existing client code

- **Existing:** `backend/tests/test_hardware_integration.py` exists but is skipped on CI (requires physical device + Telegram setup)

## Proposed Solution

### New CI Job: `api-contract-tests.yml`

Add a third workflow that:

1. **Starts the FastAPI backend** with test config (in-memory storage, no TLS)
2. **Runs contract tests** that:
   - Call backend endpoints (e.g., `/api/v1/auth/login`, `/api/v1/system/info`)
   - Parse responses into Dart model JSON structures
   - Validate response schemas match expected contracts (from `kb/api-contracts.md`)
   - Assert no required fields are missing
3. **Validates forward compatibility:**
   - Response includes all fields Flutter models expect
   - Field types match (string ≠ number, etc.)
   - New optional fields don't break old clients

### Test Categories

| Category | Examples | Tool |
|----------|----------|------|
| **Auth** | POST /login, POST /refresh, GET /users/names | Python httpx + Pydantic |
| **System** | GET /info, GET /stats/stream | Python httpx |
| **Files** | GET /files/list, POST /files/upload, DELETE /files | Python httpx |
| **Events** | WebSocket /events stream | Python httpx + asyncio |
| **Response schemas** | Compare actual backend JSON against Dart models | Pydantic validators |

### Implementation Steps

1. Create `backend/tests/test_api_contracts.py` with:
   ```python
   @pytest.mark.asyncio
   async def test_auth_login_response_schema():
       """Verify /api/v1/auth/login response matches Flutter model."""
       response = await client.post("/api/v1/auth/login", json={...})
       assert response.status_code == 200
       data = response.json()
       
       # Validate required fields
       assert "accessToken" in data
       assert "refreshToken" in data
       assert "user" in data
       
       # Validate nested user object
       user = data["user"]
       assert "name" in user
       assert "isAdmin" in user
   ```

2. Add CI job in `.github/workflows/api-contract-tests.yml`:
   ```yaml
   name: API Contract Tests
   on: [push, pull_request]
   jobs:
     contract-tests:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - uses: actions/setup-python@v4
           with: { python-version: '3.11' }
         - run: pip install -r backend/requirements.txt pytest-asyncio httpx
         - run: |
             cd backend
             PYTHONPATH=. pytest tests/test_api_contracts.py -q --tb=short
   ```

3. Update `docs/api-contracts.md` format to be both human-readable and machine-parseable (e.g., optional OpenAPI/JSON Schema annotations)

### Mock Response Validation Example

```python
# backend/tests/test_api_contracts.py
from pydantic import BaseModel
from app.models import User, AuthResponse

async def test_responses_deserialize_to_models():
    """Verify backend responses can be loaded as Dart models."""
    response = await client.get("/api/v1/system/info")
    data = response.json()
    
    # Pydantic validation ensures all required fields exist
    device = Device(**data)  # Will raise ValidationError if schema mismatch
    assert device.name is not None
    assert device.firmware_version is not None
```

### Benefits

✅ **Early detection** of breaking API changes
✅ **Increased confidence** before OTA updates to devices
✅ **Documentation** — contract tests double as API specification
✅ **Regression prevention** — catch removed fields or renamed parameters
✅ **Zero device overhead** — runs in CI with in-memory backend

### Scope

**In scope:**
- Core auth endpoints (login, refresh)
- System info endpoints
- File list/metadata endpoints
- WebSocket event streams (basic connectivity)

**Out of scope (can be added later):**
- Large file upload/download (CI runner disk constraints)
- Telegram bot integration (requires external API)
- Storage mount/format operations (requires root)
- Hardware-dependent features (Bluetooth, thermal zones)

### Success Criteria

- [ ] Workflow file created and added to CI
- [ ] 10+ contract tests written covering key endpoints
- [ ] All tests pass on main branch
- [ ] Contract tests block PR merge if API schema changes
- [ ] Documentation updated with contract testing approach

### Timeline

- **Week 1:** Write `test_api_contracts.py` with auth/system tests
- **Week 2:** Add file and event tests
- **Week 3:** Integrate into CI, update documentation

---

## Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| **Contract tests (proposed)** | Catches schema mismatches early | Requires maintaining API snapshot |
| **E2E tests on device** | Most realistic | Slow, requires hardware, fragile |
| **Manual testing before deploy** | Thorough | Error-prone, humans forget cases |
| **Relax models (accept Any type)** | Skip tests | Defeats the purpose (type safety) |

---

## Related Issues

- **TASK-022** — Migration tests added for shared/ → family/ logic
- **CI Python version** — Consider setting both to 3.11 (TASK-024)
- **API Docs** — Ensure `kb/api-contracts.md` is current and exact

## Next Steps

1. Present this plan to team
2. Decide on scope (which endpoints to test first?)
3. Assign developer to implement `test_api_contracts.py`
4. Review workflow design before CI integration
5. Merge and enable workflow enforcement in branch protection rules
