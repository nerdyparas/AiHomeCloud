# AiHomeCloud — DevOps, Testing & Observability Strategy v1.0

> **Companion to:** `kb/engineering-blueprint.md`
> **Scope:** Testing strategy, CI/CD pipeline, observability plan, schema migration,
> upgrade path, and AI integration readiness.
> **Baseline:** Zero automated tests exist in the prototype. Everything in this
> document is to be built.

---

## Part 4 — Testing & Validation Strategy

### 4.1 Current State Assessment

The prototype has **zero automated tests**. All validation has been manual (developer running the app against the real Cubie hardware). This creates the following compounding risks:

| Risk | Probability | Consequence |
|---|---|---|
| Regression introduced by any code change | High | Undetected until manual test |
| Destructive operation (format, eject) misbehaves | Medium | Data loss |
| API contract drift (backend renames field, Flutter silently breaks) | High | Silent null/crash in UI |
| Path traversal bug introduced or regressed | Medium | Security breach |
| Concurrent write to JSON store corrupts user list | Medium | Silent data loss |
| Token auth removed from an endpoint during refactor | High | Auth bypass |

**Prioritization rule:** Write tests in this order — (1) security-critical paths, (2) destructive operations, (3) auth/role logic, (4) API contract validation, (5) UI flows.

---

### 4.2 Test Pyramid (ARM-Constrained)

```
            ┌───────────────┐
            │  E2E / Manual │  < 15 scenarios, hardware-in-loop, manual trigger
            │               │  before each release
            ├───────────────┤
            │  Integration  │  ~40 tests, FastAPI TestClient + mocked subprocess
            │               │  runs in CI (no ARM hardware), ~2 min
            ├───────────────┤
            │   Unit Tests  │  ~120 tests, pure Python + Dart
            │               │  runs in CI, < 60 seconds
            └───────────────┘
```

**Constraint:** Integration tests must not call real `subprocess` — all system calls go through `subprocess_runner.py` which is mockable. The `system/` layer is the only thing not covered by integration tests; it is covered by hardware-in-loop tests.

---

### 4.3 Backend Test Structure

```
backend/
└── tests/
    ├── conftest.py               # Fixtures: TestClient, temp dirs, mock subprocess runner
    ├── unit/
    │   ├── test_auth.py          # JWT create/decode, expiry, role check, denylist
    │   ├── test_store.py         # Atomic writes, concurrent writes, schema migration
    │   ├── test_models.py        # Pydantic serialization, camelCase aliases
    │   ├── test_path_safety.py   # _safe_resolve() boundary and traversal cases
    │   └── test_subprocess_runner.py  # Path validation, timeout, error propagation
    └── integration/
        ├── test_auth_routes.py   # Pair, rate limit, invalid token, refresh, revoke
        ├── test_file_routes.py   # List, upload, delete, rename — with temp NAS dir
        ├── test_storage_routes.py # Device listing with mocked lsblk output
        ├── test_monitor_ws.py    # WebSocket auth, frame format, disconnect
        └── test_network_routes.py # Toggle endpoints with mocked nmcli
```

**`conftest.py` fixture requirements:**

```python
# backend/tests/conftest.py
import pytest
from fastapi.testclient import TestClient
from pathlib import Path
import tempfile

from app.main import app
from app import store, config

@pytest.fixture()
def tmp_data_dir(tmp_path, monkeypatch):
    """Redirect all JSON store paths to a temp directory."""
    monkeypatch.setattr(config.settings, "data_dir", tmp_path)
    monkeypatch.setattr(config.settings, "nas_root", tmp_path / "nas")
    (tmp_path / "nas" / "personal").mkdir(parents=True)
    (tmp_path / "nas" / "family").mkdir(parents=True)
    (tmp_path / "nas" / "entertainment").mkdir(parents=True)
    return tmp_path

@pytest.fixture()
def client(tmp_data_dir):
    return TestClient(app)

@pytest.fixture()
def admin_token(client):
    # Pair as device (always admin-level)
    r = client.post("/api/v1/pair", json={"serial": "TEST-001", "otp": "123456"})
    return r.json()["token"]

@pytest.fixture()
def mock_subprocess(monkeypatch):
    """Replace subprocess_runner.run with a controllable mock."""
    calls = []
    async def fake_run(cmd, timeout=30.0, check=True):
        calls.append(cmd)
        return (0, "", "")
    monkeypatch.setattr("app.system.subprocess_runner.run", fake_run)
    return calls
```

---

### 4.4 Must-Have Test Cases (Backend)

These tests must exist before any v2 release. Failing any of them fails CI.

#### Path Safety — Non-Negotiable

```python
# tests/unit/test_path_safety.py
import pytest
from app.services.file_service import safe_resolve

def test_rejects_parent_traversal():
    assert safe_resolve("../../etc/passwd") is None

def test_rejects_absolute_path_outside_nas():
    assert safe_resolve("/etc/passwd") is None

def test_rejects_url_encoded_traversal():
    assert safe_resolve("..%2F..%2Fetc%2Fpasswd") is None

def test_rejects_null_byte_injection():
    assert safe_resolve("file.txt\x00.jpg") is None

def test_accepts_valid_subpath():
    result = safe_resolve("personal/user1/file.txt")
    assert result is not None
    assert str(result).startswith(str(config.settings.nas_root))

def test_accepts_nested_subpath():
    result = safe_resolve("family/photos/2026/img.jpg")
    assert result is not None
```

#### Store Concurrency — Non-Negotiable

```python
# tests/unit/test_store.py
import threading
from app.store import add_user, get_users

def test_concurrent_writes_do_not_corrupt(tmp_data_dir):
    errors = []
    def writer(i):
        try:
            add_user(name=f"user{i}", pin=str(i))
        except Exception as e:
            errors.append(e)

    threads = [threading.Thread(target=writer, args=(i,)) for i in range(10)]
    for t in threads: t.start()
    for t in threads: t.join()

    assert not errors, f"Concurrent write errors: {errors}"
    users = get_users()
    assert len(users) == 10, f"Expected 10 users, got {len(users)} — data was lost"
    names = {u["name"] for u in users}
    assert names == {f"user{i}" for i in range(10)}

def test_atomic_write_survives_interrupt(tmp_data_dir):
    """Verifies no partial file is left if write is interrupted mid-way."""
    import os, signal
    # Write a valid file first
    add_user("existing_user")
    original = get_users()
    # Corrupt write should not replace valid data
    from app.store import _write_json_atomic
    from pathlib import Path
    import json
    with pytest.raises(Exception):
        _write_json_atomic(
            config.settings.users_file,
            object()  # Not JSON serializable
        )
    # Original file must still be valid
    assert get_users() == original
```

#### Auth — Non-Negotiable

```python
# tests/integration/test_auth_routes.py
def test_pair_rate_limit(client):
    """After 5 failed attempts, 6th returns 429."""
    for i in range(5):
        client.post("/api/v1/pair", json={"serial": "x", "otp": "000000"})
    r = client.post("/api/v1/pair", json={"serial": "x", "otp": "000000"})
    assert r.status_code == 429

def test_invalid_token_returns_401(client):
    r = client.get("/api/v1/system/info", headers={"Authorization": "Bearer garbage"})
    assert r.status_code == 401

def test_expired_token_returns_401(client, tmp_data_dir):
    from app.auth_service import create_token
    from datetime import timedelta
    token = create_token("test-user", expire_delta=timedelta(seconds=-1))
    r = client.get("/api/v1/system/info", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 401

def test_logout_invalidates_token(client, admin_token):
    client.post("/api/v1/auth/logout", headers={"Authorization": f"Bearer {admin_token}"})
    r = client.get("/api/v1/system/info", headers={"Authorization": f"Bearer {admin_token}"})
    assert r.status_code == 401

def test_non_admin_cannot_add_family_member(client, tmp_data_dir):
    # Create a non-admin user and get their token
    # Then attempt to POST /api/v1/users/family
    member_token = _create_member_token(client)
    r = client.post(
        "/api/v1/users/family",
        json={"name": "newkid"},
        headers={"Authorization": f"Bearer {member_token}"}
    )
    assert r.status_code == 403
```

#### Device Path Injection — Non-Negotiable

```python
# tests/integration/test_storage_routes.py
def test_format_rejects_shell_injection_in_device_path(client, admin_token):
    r = client.post("/api/v1/storage/format", json={
        "device": "/dev/sda1; rm -rf /",
        "confirmDevice": "/dev/sda1; rm -rf /",
        "label": "test"
    }, headers={"Authorization": f"Bearer {admin_token}"})
    assert r.status_code == 422  # Pydantic validation rejects it

def test_mount_rejects_path_traversal_device(client, admin_token):
    r = client.post("/api/v1/storage/mount", json={
        "device": "../../../../etc/passwd"
    }, headers={"Authorization": f"Bearer {admin_token}"})
    assert r.status_code == 422
```

#### API Contract — camelCase Serialization

```python
# tests/unit/test_models.py
from app.models import StorageDevice, FamilyUser, SystemStats

def test_storage_device_serializes_camelcase():
    d = StorageDevice(name="sda1", path="/dev/sda1",
                      size_bytes=64_000_000_000, size_display="64.0 GB", ...)
    out = d.model_dump(by_alias=True)
    assert "sizeBytes" in out
    assert "sizeDisplay" in out
    assert "size_bytes" not in out  # Must not have snake_case in output

def test_family_user_serializes_camelcase():
    u = FamilyUser(id="u1", name="Alice", is_admin=True,
                   folder_size_gb=1.2, avatar_color="FFE8A84C")
    out = u.model_dump(by_alias=True)
    assert "isAdmin" in out
    assert "folderSizeGB" in out
```

---

### 4.5 Flutter Test Structure

```
test/
├── unit/
│   ├── models_test.dart              # fromJson/toJson, camelCase contract
│   ├── api_service_test.dart         # Mock HTTP, error mapping, timeout
│   └── auth_session_notifier_test.dart  # Login, logout, state invalidation
├── widget/
│   ├── dashboard_screen_test.dart    # Renders with mock data, shows connection state
│   ├── storage_explorer_test.dart    # Format confirm dialog, mount/unmount flow
│   └── file_list_tile_test.dart      # Long press, context menu
└── golden/  (future — v2)
    └── dashboard_golden_test.dart
```

**Required Flutter test cases:**

```dart
// test/unit/api_service_test.dart
test('throws CubieConnectionException on SocketException', () async {
  when(mockClient.get(any, headers: anyNamed('headers')))
      .thenThrow(const SocketException('No route to host'));
  expect(
    () async => await apiService.getDeviceInfo(),
    throwsA(isA<CubieConnectionException>()),
  );
});

test('throws CubieApiException with detail on 401', () async {
  when(mockClient.get(any, headers: anyNamed('headers')))
      .thenAnswer((_) async => http.Response('{"detail":"unauthorized"}', 401));
  final e = await apiService.getDeviceInfo().then((_) => null, onError: (e) => e);
  expect(e, isA<CubieApiException>());
  expect((e as CubieApiException).statusCode, 401);
});

test('all methods have .timeout applied', () {
  // Static analysis check — every public method in ApiService
  // must call .timeout(_timeout). Enforce via a custom lint rule
  // or a code review checklist item.
  // This test is a reminder, not a runtime check.
});
```

```dart
// test/unit/auth_session_notifier_test.dart
test('logout clears all state', () async {
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(fakePrefs),
  ]);
  final notifier = container.read(authSessionProvider.notifier);
  await notifier.login(AuthSession(host: '192.168.0.1', token: 'tok', ...));
  expect(container.read(authSessionProvider), isNotNull);

  await notifier.logout();
  expect(container.read(authSessionProvider), isNull);
  expect(fakePrefs.getString(CubieConstants.prefAuthToken), isNull);
});
```

**Anti-pattern — explicitly rejected:**
Do NOT write widget tests that mock `ApiService` at 100% and only assert "the widget builds without error." Widget tests must test meaningful interactions: tap a button, assert provider state changes, or assert an error widget appears on exception.

---

### 4.6 Hardware-in-Loop Test Protocol

Run this checklist before every release tag. Sign off is required on `main` PRs.

```markdown
## HARDWARE TEST CHECKLIST — AiHomeCloud
Release: ___________  Tester: ___________  Date: ___________  Hardware: ___________

### Boot & Startup
[ ] Cold boot: cubie-backend.service starts within 15 seconds
[ ] Cold boot with previously mounted USB: NAS auto-remounts correctly
[ ] Cold boot with USB unplugged: Backend starts cleanly, NAS warning shown in app
[ ] JWT secret file exists at /var/lib/cubie/secret.key after first boot
[ ] JWT secret is NOT the default "change-me-in-production" value

### Pairing & Authentication
[ ] QR code pairing flow completes end-to-end on a new install
[ ] BLE pairing flow completes end-to-end
[ ] OTP pairing: second use of same OTP is rejected (single-use)
[ ] OTP pairing: OTP used after 5 minutes is rejected (TTL expired)
[ ] TLS cert fingerprint pinning: app rejects connection after cert regenerated
[ ] TLS cert fingerprint pinning: re-pair flow accepts new cert

### File Operations
[ ] Upload 50 MB file: succeeds, hash on device matches
[ ] Upload 1 GB file: succeeds, backend RSS stays < 256 MB during upload
[ ] Path traversal: GET /api/v1/files/list?path=../../etc → 400 (not 500)
[ ] Path traversal: DELETE /api/v1/files/delete?path=../../etc/passwd → 400
[ ] File listing pagination: 200 item folder, page=1&limit=50 returns 50 items

### Storage Management
[ ] Hot-plug USB drive: detected by scan within 10 seconds
[ ] Format → Mount → verify personal/, family/, and entertainment/ created on device
[ ] Unmount with open file handle: returns 409 with blockers list
[ ] Safe eject: USB power cut confirmed (dmesg shows device removal)
[ ] Unplug USB mid-read (file download): backend returns error, does not crash
[ ] Unplug USB mid-write (file upload): backend returns error, does not crash

### Authentication & Security
[ ] Expired token (1 hour): returns 401
[ ] Revoked token (after logout): returns 401
[ ] Non-admin user: cannot format/mount/unmount storage → 403
[ ] Non-admin user: cannot add family member → 403
[ ] WebSocket monitor: unauthenticated connection → rejected (code 1008)
[ ] Rate limit: 6th pairing attempt in 1 minute → 429

### Resilience
[ ] Backend restart mid-session: app detects disconnect within 5 seconds,
    shows degraded state, reconnects automatically
[ ] WiFi toggle off: app shows offline state, not unhandled exception
[ ] journald SystemMaxUse: confirm 50M limit configured

### Performance
[ ] Backend RSS at idle (with Samba running): < 256 MB
[ ] File listing 1000 items: < 500 ms (measure in app)
[ ] WebSocket monitor frame interval: ~2 seconds (observe in developer mode)
```

---

## Part 5 — CI/CD & DevOps Plan

### 5.1 Git Branching Model

```
main            ← production, deployed to Cubie; hardware-tested; tagged releases only
develop         ← integration, all CI checks must pass before merge
feature/*       ← short-lived features (≤ 2 weeks)
fix/*           ← bug fixes (branch from main for hotfixes, from develop otherwise)
release/x.y.z  ← release candidates; hardware checklist run here
```

**Branch protection rules:**
- `main`: no direct push, 1 approval required, hardware checklist required
- `develop`: no direct push, CI must pass, no approval required (solo project)
- `release/*`: no direct push, CI must pass, hardware checklist required

**Commit message format:** `<type>(<scope>): <description>`
- Types: `feat`, `fix`, `security`, `refactor`, `test`, `docs`, `ci`, `chore`
- Examples: `security(auth): auto-generate JWT secret on first boot`
- Examples: `fix(store): atomic JSON writes with threading lock`

---

### 5.2 CI Pipeline — GitHub Actions

#### Backend CI (`.github/workflows/backend-ci.yml`)

```yaml
name: Backend CI
on:
  push:
    branches: [develop, 'release/**']
  pull_request:
    branches: [develop, main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install ruff mypy
      - run: ruff check backend/app/ --select ALL --ignore D,ANN
      - run: mypy backend/app/ --ignore-missing-imports --strict

  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install bandit safety pip-audit
      - name: Bandit SAST (medium+ severity fails CI)
        run: bandit -r backend/app/ -ll -x backend/app/__pycache__
      - name: Safety dependency scan
        run: pip-audit -r backend/requirements.txt
      - name: Check for default JWT secret in committed code
        run: |
          if grep -r "change-me-in-production" backend/app/; then
            echo "ERROR: Default JWT secret found in committed code"
            exit 1
          fi

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install -r backend/requirements.txt -r backend/requirements-test.txt
      - run: |
          pytest backend/tests/ \
            -v \
            --cov=backend/app \
            --cov-report=xml \
            --cov-report=term-missing \
            -x  # Stop on first failure
      - name: Coverage gate (70% minimum — raise to 80% by v2.0)
        run: coverage report --fail-under=70
      - uses: codecov/codecov-action@v4
        with:
          files: coverage.xml
```

**Hard CI gates (any failure = PR blocked):**
1. `ruff` lint with no errors
2. `bandit` — zero medium or high severity findings
3. `safety` / `pip-audit` — no known CVEs in dependencies
4. Test coverage ≥ 70% (raise to 80% before v2.0)
5. No occurrence of `"change-me-in-production"` in any Python file
6. No `shell=True` in any route or service file (grep check)

**Additional grep checks (add as CI steps):**

```bash
# Verify no shell=True in business code (allowed only in test fixtures with explanation)
! grep -rn "shell=True" backend/app/ --include="*.py"

# Verify no print() statements in production code
! grep -rn "^print(" backend/app/ --include="*.py"

# Verify all routes are under /api/v1 prefix
grep -rn 'router\.' backend/app/routes/ | grep -v '/api/v1/' | grep -v 'api/version' | grep -v 'api/health' && exit 1 || true
```

---

#### Flutter CI (`.github/workflows/flutter-ci.yml`)

```yaml
name: Flutter CI
on:
  push:
    branches: [develop, 'release/**']
  pull_request:
    branches: [develop, main]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.x', channel: 'stable' }
      - run: flutter pub get
      - run: flutter analyze --fatal-infos --fatal-warnings

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.x', channel: 'stable' }
      - run: flutter pub get
      - run: flutter test --coverage
      - name: Coverage report (informational in v1, gate in v2)
        run: |
          lcov --summary coverage/lcov.info || true

  build-apk:
    runs-on: ubuntu-latest
    needs: [analyze, test]
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.x', channel: 'stable' }
      - run: flutter pub get
      - run: flutter build apk --release --obfuscate --split-debug-info=debug-symbols/
      - uses: actions/upload-artifact@v4
        with:
          name: release-apk-${{ github.sha }}
          path: build/app/outputs/flutter-apk/app-release.apk
          retention-days: 30
```

---

### 5.3 Deployment — ARM SBC

**Current state:** SSH + manual `rsync`. Acceptable for solo development but lacks rollback capability.

**Target deployment script (`scripts/deploy.sh`):**

```bash
#!/usr/bin/env bash
# Usage: ./scripts/deploy.sh [cubie-hostname-or-ip]
set -euo pipefail

TARGET=${1:-cubie.local}
DEPLOY_DIR=/opt/cubie/backend
VENV=/opt/cubie/venv
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "▶ Deploying to $TARGET"

echo "  → Backing up current deployment..."
ssh cubie@$TARGET "sudo cp -r $DEPLOY_DIR ${DEPLOY_DIR}.backup.$TIMESTAMP"

echo "  → Syncing backend files..."
rsync -avz --delete \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='.git/' \
  --exclude='tests/' \
  backend/ cubie@$TARGET:$DEPLOY_DIR/

echo "  → Installing dependencies..."
ssh cubie@$TARGET "$VENV/bin/pip install -r $DEPLOY_DIR/requirements.txt --quiet"

echo "  → Restarting service..."
ssh cubie@$TARGET "sudo systemctl restart cubie-backend"

echo "  → Health check (5s)..."
sleep 5
HEALTH=$(curl -sf --max-time 5 https://$TARGET:8443/api/health 2>/dev/null || echo "FAIL")
if echo "$HEALTH" | grep -q '"status":"ok"'; then
  echo "  ✓ Health check passed"
  # Keep only last 3 backups
  ssh cubie@$TARGET "ls -dt ${DEPLOY_DIR}.backup.* | tail -n +4 | xargs sudo rm -rf"
  echo "✓ Deployment successful"
else
  echo "  ✗ Health check FAILED — rolling back"
  ssh cubie@$TARGET "sudo cp -r ${DEPLOY_DIR}.backup.$TIMESTAMP $DEPLOY_DIR && sudo systemctl restart cubie-backend"
  echo "✗ Rollback complete. Deployment failed."
  exit 1
fi
```

**Rollback script (`scripts/rollback.sh`):**

```bash
#!/usr/bin/env bash
set -euo pipefail
TARGET=${1:-cubie.local}
ssh cubie@$TARGET "ls -dt /opt/cubie/backend.backup.*"
read -p "Enter backup timestamp to restore: " TS
ssh cubie@$TARGET "
  sudo systemctl stop cubie-backend
  sudo cp -r /opt/cubie/backend.backup.$TS /opt/cubie/backend
  sudo systemctl start cubie-backend
"
sleep 3
curl -sf https://$TARGET:8443/api/health && echo "✓ Rollback successful" || echo "✗ Rollback failed"
```

---

### 5.4 Python Dependency Management

**Problem with current `requirements.txt`:** It is a manually maintained, unpinned list. Any `pip install` on the device may silently upgrade a transitive dependency and break the backend.

**Required approach — `pip-tools`:**

```bash
# requirements.in — only direct dependencies with loose version constraints
fastapi>=0.110,<1.0
uvicorn[standard]>=0.29
pydantic-settings>=2.0
python-jose[cryptography]>=3.3
passlib[bcrypt]>=1.7
slowapi>=0.1.9
psutil>=5.9

# Generate pinned requirements.txt
pip-compile requirements.in --output-file requirements.txt

# Update all deps
pip-compile requirements.in --upgrade --output-file requirements.txt
```

The pinned `requirements.txt` is committed to git. `requirements.in` is the source of truth for intent. Updates are a deliberate PR action, not a side effect of deployment.

---

### 5.5 First-Boot Setup

On a fresh Cubie with no prior configuration:

```bash
# /opt/cubie/scripts/first-boot.sh
#!/bin/bash
set -euo pipefail
ENV_FILE=/var/lib/cubie/cubie.env

mkdir -p /var/lib/cubie
chown cubie:cubie /var/lib/cubie

if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" << EOF
CUBIE_DEVICE_NAME=My AiHomeCloud
EOF
  chmod 0600 "$ENV_FILE"
  chown cubie:cubie "$ENV_FILE"
  echo "First-boot env file created at $ENV_FILE"
fi

# JWT secret is auto-generated by the Python config on first start.
# Pairing OTPs are generated at runtime — no static keys.

echo "First-boot setup complete."
```

The `ExecStartPre` in the systemd unit runs this script (as root) before the uvicorn process starts. The Python app itself generates the JWT secret on first access of `settings.jwt_secret`.

---

## Part 6 — Observability & Logging Plan

### 6.1 Structured Logging Implementation

Replace all `print()` statements and inconsistent `logger.*` calls with a uniform JSON logger.

```python
# backend/app/logging_config.py
import json
import logging
from datetime import datetime, timezone


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        base = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        # Merge any extra fields passed via logger.info("msg", extra={...})
        extra = {
            k: v for k, v in record.__dict__.items()
            if k not in logging.LogRecord.__dict__ and k not in (
                "msg", "args", "levelname", "levelno", "pathname",
                "filename", "module", "exc_info", "exc_text",
                "stack_info", "lineno", "funcName", "created",
                "msecs", "relativeCreated", "thread", "threadName",
                "processName", "process", "name", "message",
            )
        }
        return json.dumps({**base, **extra})


def configure_logging(debug: bool = False) -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(JSONFormatter())
    root = logging.getLogger()
    root.addHandler(handler)
    root.setLevel(logging.DEBUG if debug else logging.INFO)
    # Suppress uvicorn's own access log (replaced by middleware)
    logging.getLogger("uvicorn.access").propagate = False
```

**Usage pattern throughout the codebase:**
```python
logger = logging.getLogger("cubie.storage")
# Good:
logger.info("device_mounted", extra={"device": device_path, "mount_point": str(mount_point)})
# Bad (never do this):
print(f"Device mounted: {device_path}")
logger.info(f"Device mounted: {device_path}")  # f-string loses structure
```

---

### 6.2 Request Logging Middleware

```python
# backend/app/middleware.py
import time
import uuid
import logging
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger("cubie.http")


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = uuid.uuid4().hex[:8]
        start = time.monotonic()

        # Attach request_id to request state so handlers can reference it
        request.state.request_id = request_id

        response = await call_next(request)
        duration_ms = round((time.monotonic() - start) * 1000, 1)

        # Extract user from token (best-effort, don't fail on missing token)
        user_id = _extract_user_id(request)

        logger.info("http_request", extra={
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "status": response.status_code,
            "duration_ms": duration_ms,
            "user_id": user_id,
            "ip": request.client.host if request.client else "unknown",
        })

        response.headers["X-Request-Id"] = request_id
        return response
```

Register in `main.py`:
```python
app.add_middleware(RequestLoggingMiddleware)
```

---

### 6.3 Startup Diagnostics Log

The startup sequence (in `lifespan()`) must emit a structured summary:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_logging(debug=settings.debug_mode)
    logger = logging.getLogger("cubie.startup")

    # Gather diagnostics
    nas_mounted = Path("/proc/mounts").read_text().find(str(settings.nas_root)) != -1
    services = store.get_services()
    active_services = [s["id"] for s in services if s["isEnabled"]]

    logger.info("startup", extra={
        "device_serial": settings.device_serial,
        "device_name": settings.device_name,
        "firmware_version": settings.firmware_version,
        "port": settings.port,
        "tls_enabled": settings.tls_enabled,
        "nas_root": str(settings.nas_root),
        "nas_mounted": nas_mounted,
        "data_dir": str(settings.data_dir),
        "active_services": active_services,
        "jwt_secret_source": "auto-generated" if settings._secret_file.exists() else "generating",
    })

    yield

    logger.info("shutdown")
```

---

### 6.4 Log Volume Budget (ARM-Constrained)

| Log level | Volume estimate | Notes |
|---|---|---|
| INFO | ~100 lines/hour at idle | HTTP requests, state changes |
| WARNING | ~5 lines/hour | Deprecated endpoint calls, retried subprocess |
| ERROR | ~1 line/hour | Unexpected failures |
| DEBUG | ~10,000 lines/hour | Only enabled in development |

**Production rule:** `CUBIE_DEBUG=false` always. DEBUG logs on a busy system would fill 50 MB journald budget in < 1 hour.

**journald configuration** (add to `/etc/systemd/journald.conf`):
```ini
[Journal]
SystemMaxUse=50M
SystemKeepFree=100M
MaxRetentionSec=7day
```

---

### 6.5 Health Check Endpoint

```python
# backend/app/routes/health_routes.py
@router.get("/api/health")  # Intentionally unversioned — always available
async def health():
    import psutil, time
    from pathlib import Path
    nas_mounted = any(
        str(settings.nas_root) in line
        for line in Path("/proc/mounts").read_text().splitlines()
    )
    services = store.get_services()
    service_status = {}
    for svc in services:
        if svc["isEnabled"]:
            rc, _, _ = await subprocess_runner.run(
                ["systemctl", "is-active", svc["id"]], check=False
            )
            service_status[svc["id"]] = "active" if rc == 0 else "inactive"

    return {
        "status": "ok",
        "version": settings.firmware_version,
        "api_version": "v1",
        "nas_mounted": nas_mounted,
        "uptime_seconds": int(time.time() - psutil.boot_time()),
        "services": service_status,
    }
```

This endpoint is used by:
- The deploy script's health check gate
- Flutter app's connection check before rendering main UI
- Future monitoring scripts or uptime tools

---

## Part 7 — Schema Migration & Upgrade Strategy

### 7.1 JSON Store Schema Versioning

**Problem:** All JSON store files (`users.json`, `services.json`, `storage.json`) have no version marker. When a field is added, renamed, or its type changes across a backend update, old files silently fail to deserialize or contain missing data.

**Required — Add `_schema_version` to all files:**

```python
# store.py — new pattern for all JSON stores

USERS_SCHEMA_VERSION = 2
SERVICES_SCHEMA_VERSION = 1
STORAGE_SCHEMA_VERSION = 1

def _migrate_users(data: dict) -> dict:
    """Apply migrations sequentially. Each migration is idempotent."""
    version = data.get("_schema_version", 1)

    if version < 2:
        # v1 → v2: migrate plaintext PIN to bcrypt hash
        from passlib.hash import bcrypt
        for user in data.get("users", []):
            if "pin" in user and user["pin"] is not None:
                # Only hash if it doesn't look like a bcrypt hash already
                if not str(user["pin"]).startswith("$2b$"):
                    user["pin_hash"] = bcrypt.hash(str(user["pin"]))
                else:
                    user["pin_hash"] = user["pin"]
                del user["pin"]
            elif "pin" in user:
                user["pin_hash"] = None
                del user["pin"]
        data["_schema_version"] = 2

    return data

def get_users() -> list[dict]:
    raw = _read_json(settings.users_file, {"_schema_version": USERS_SCHEMA_VERSION, "users": []})
    if isinstance(raw, list):
        # Legacy v1 format: bare list, no version marker
        raw = {"_schema_version": 1, "users": raw}
    raw = _migrate_users(raw)
    # Write back with new version if migration occurred
    if raw.get("_schema_version") != USERS_SCHEMA_VERSION:
        _write_json_atomic(settings.users_file, raw)
    return raw.get("users", [])
```

**Migration rules:**
1. Migrations must be idempotent — running twice must produce the same result
2. Migrations must be backward-compatible reads — old data must never cause a crash
3. Each migration step must be individually tested
4. Migrations run automatically on first `get_*()` call after a backend update
5. No manual migration scripts — everything is code

---

### 7.2 API Migration Path (v0.1 → v0.2)

The transition to `/api/v1/` prefix must be coordinated across the backend and app:

| Week | Action |
|---|---|
| Week 1 | Backend: expose both `/api/*` (old) and `/api/v1/*` (new) simultaneously |
| Week 1 | Backend: old routes return `X-Deprecated: true` header |
| Week 1 | App: update to use `/api/v1/*` exclusively |
| Week 1 | App: add `/api/version` check on connect, show update dialog if needed |
| Week 2–3 | Monitor: log all calls to deprecated routes in production |
| Week 6 | Backend: remove old `/api/*` routes entirely |

**Compatibility shim in `main.py`:**
```python
# Temporary backward-compat: add deprecated marker to old routes
from starlette.middleware.base import BaseHTTPMiddleware

class DeprecatedRouteMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        if request.url.path.startswith("/api/") and not request.url.path.startswith("/api/v"):
            response.headers["X-Deprecated"] = "true"
            response.headers["X-Sunset-Date"] = "2026-09-01"
        return response
```

---

### 7.3 App Distribution & Update Flow

**Current: Direct APK download** (suitable for personal/family use)

```dart
// lib/services/update_service.dart
class UpdateService {
  Future<VersionInfo> checkForUpdate() async {
    // 1. Call /api/version on connected device
    final deviceVersion = await api.getVersion();
    // 2. Also check GitHub Releases API for latest APK
    final latestRelease = await _fetchGitHubLatest();
    return VersionInfo(
      currentVersion: AppConfig.version,
      minRequired: deviceVersion.minAppVersion,
      latestAvailable: latestRelease.tagName,
      downloadUrl: latestRelease.apkDownloadUrl,
      isBackendIncompatible: _isIncompatible(deviceVersion),
      isAppUpdateAvailable: _isNewer(latestRelease.tagName),
    );
  }
}
```

**APK signing key management:**
- Keystore file: `android/release.keystore` — **NOT committed to git**
- Location: stored in a password manager (1Password, Bitwarden) + one encrypted backup
- `key.properties`: generated from CI environment secrets, never committed
- If keystore is lost: users must uninstall and reinstall (cannot update in-place)

---

## Part 8 — AI Integration Readiness

This section constrains current v1 work to avoid blocking AI features in v2. No AI code ships in v1.

### 8.1 File Event Infrastructure

**Required in v1 (zero overhead):** Every file mutation must emit an event to an internal asyncio queue. In v1, nothing consumes this queue. In v2, the background indexer subscribes.

```python
# backend/app/events.py
import asyncio
from dataclasses import dataclass
from enum import Enum
from pathlib import Path


class FileEventType(Enum):
    CREATED = "created"
    DELETED = "deleted"
    RENAMED = "renamed"
    UPLOADED = "uploaded"


@dataclass
class FileEvent:
    type: FileEventType
    path: Path
    user_id: str
    size_bytes: int = 0
    mime_type: str | None = None


_queue: asyncio.Queue[FileEvent] = asyncio.Queue(maxsize=1000)


async def emit(event: FileEvent) -> None:
    try:
        _queue.put_nowait(event)
    except asyncio.QueueFull:
        pass  # Drop event silently — indexer will re-scan on startup


def get_queue() -> asyncio.Queue[FileEvent]:
    return _queue
```

**File routes must call `emit()` on every mutation.** This is a fire-and-forget call with `put_nowait` — it adds zero latency to the HTTP response.

---

### 8.2 Metadata Storage Reservation

Reserve `/var/lib/cubie/index.db` (SQLite) now, even if it is empty:

```sql
-- Created on startup if not exists — no data written in v1
CREATE TABLE IF NOT EXISTS file_index (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT UNIQUE NOT NULL,
    user_id TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    mime_type TEXT,
    content_hash TEXT,  -- SHA-256 of file content
    indexed_at TEXT,    -- ISO 8601 timestamp
    embedding BLOB      -- NULL in v1; quantized float32 vector in v2
);

CREATE INDEX IF NOT EXISTS idx_file_index_user ON file_index(user_id);
CREATE INDEX IF NOT EXISTS idx_file_index_hash ON file_index(content_hash);
```

**Why SQLite over another vector DB?** On an 8 GB ARM SBC, running a separate vector database (Chroma, Qdrant, Weaviate) consumes 200–500 MB RAM for the daemon. SQLite with `sqlite-vec` (formerly sqlite-vss) extension handles up to 100,000 256-dim vectors in < 100 MB with adequate latency for a personal NAS.

---

### 8.3 ARM CPU Budget for AI

| Operation | Time (ARM Cortex-A55 @ 1.8 GHz) | RAM |
|---|---|---|
| CLIP image embedding (ViT-B/32, ONNX Q8) | ~3–5 seconds per image | ~300 MB peak |
| Phi-3.5-mini-instruct (GGUF Q4_K_M) | ~800 tokens/min | ~450 MB |
| Llama-3.2-1B (GGUF Q4_K_M) | ~1200 tokens/min | ~700 MB |
| Whisper-tiny (ONNX) | ~4× real-time | ~150 MB |

**Constraint:** AI inference must be scheduled as a `asyncio` background task at low priority (`asyncio.create_task` with `asyncio.sleep(0)` yields between chunks). It must never run during active file uploads or downloads. It must be pauseable via a config flag.

**Memory constraint:** The backend (256 MB) + AI model must stay under 700 MB total (leaving 1.3 GB for OS + NAS services on an 8 GB device is comfortable). Phi-3.5-mini at 450 MB + backend at 256 MB = 706 MB — acceptable.

---

### 8.4 Search API Contract (Reserve Now, Implement in v2)

Reserve these endpoint paths now so they can be added in v2 without conflicting with existing routes:

```
GET  /api/v1/search?q=<text>&type=<files|all>&limit=20
GET  /api/v1/files/{path}/similar          # Find visually similar images
POST /api/v1/ai/index?path=<dir>           # Trigger manual re-index of directory
GET  /api/v1/ai/status                     # Indexer status, queue depth, last run
```

Do not implement these in v1. Do not add stub handlers. Reserve the paths in documentation only.

---

## Part 9 — Risk Register

| ID | Risk | Likelihood | Impact | Current State | Mitigation |
|---|---|---|---|---|---|
| R-01 | SD card corruption during users.json write | Medium | High | ❌ Non-atomic writes | NFR-REL-01: atomic writes |
| R-02 | JWT secret left as default string | **High** | **Critical** | ❌ Defaults to public string | SEC-01: auto-generate on boot |
| R-03 | TLS cert MITM on local network (ARP spoof) | Medium | **Critical** | ❌ All certs accepted | SEC-02: cert pinning from QR |
| R-04 | PIN exposed via users.json leak | Medium | High | ❌ Plaintext storage | SEC-03: bcrypt hash |
| R-05 | Subprocess shell injection via device path | Low | **Critical** | ❌ Some shell=True | SEC-04: subprocess_runner.py |
| R-06 | Backend OOM during large upload | Medium | High | ❌ Loads body in memory | NFR-PERF-03: streaming response |
| R-07 | Concurrent writes corrupt user list | Medium | High | ❌ No file locking | RISK-02: per-file threading.Lock |
| R-08 | Path traversal via file API | Low | **Critical** | ⚠️ Partial safe_resolve | FR-FILE-03: systematic audit |
| R-09 | API breaks on first field rename (no versioning) | **High** | High | ❌ No versioning | FR-API-01: /api/v1 prefix |
| R-10 | Stale ApiService state after logout | Medium | Medium | ❌ Mutable singleton | Section 2.5: AuthSessionNotifier |
| R-11 | BLE/QR pairing key observed, replay attack | Low | High | ❌ Static key | FR-AUTH-01: time-limited OTP |
| R-12 | USB pulled mid-lazy-unmount, silent data loss | Low | **Critical** | ❌ Lazy unmount fallback | RISK-10: remove lazy unmount |
| R-13 | WebSocket monitor leaks system stats to LAN | **High** | Medium | ❌ No auth on WS | FR-MON-01: token on upgrade |
| R-14 | Keystore lost, no APK updates possible | Low | High | ⚠️ No documented backup | Section 7.3: document storage |

---

## Appendix A — Milestone Planning Guidance

Use this table to sequence engineering work. Address risks in order of `Impact × Likelihood`.

### Recommended Milestone 4 — Security & Foundation

Priority order:
1. **SEC-01** — Auto-generate JWT secret (30 min, zero risk)
2. **NFR-REL-01** — Atomic JSON writes + file locking (2 hours)
3. **SEC-03** — bcrypt PIN hashing + schema migration (3 hours)
4. **RISK-02** — Fix subprocess safety via `subprocess_runner.py` (4 hours)
5. **FR-API-01** — `/api/v1` versioning prefix (2 hours)
6. **FR-MON-01** — WebSocket auth (1 hour)
7. **RISK-03** — Remove CORS middleware (30 min)
8. **FR-AUTH-02** — 1-hour access token + refresh token (4 hours)
9. Write backend unit tests for all of the above (4 hours)

**Estimated total: ~2 days. Required before any production deployment or external exposure.**

### Recommended Milestone 5 — Reliability & Observability

1. Structured JSON logging (`logging_config.py`, `middleware.py`)
2. `GET /api/health` endpoint
3. `AuthSessionNotifier` replacing individual state providers
4. Connection state machine in Flutter shell
5. File pagination (`FR-FILE-01`)
6. Streaming file upload for large files
7. Deploy script with rollback (`scripts/deploy.sh`)
8. Hardware test checklist — first full run

### Recommended Milestone 6 — Certificate Pinning & OTP Pairing

1. Include cert fingerprint in QR payload
2. Flutter cert pinning on first connect
3. OTP-based pairing replacing static key
4. Rate limiting on `/api/v1/pair`
5. Token revocation denylist

---

*End of document. Version: 1.0, March 2026.*
