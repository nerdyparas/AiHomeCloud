import pytest

# Ensure asyncio fixtures have HTTP client
from httpx import AsyncClient, ASGITransport

# Set environment variable before importing the app so Settings picks it up
# Note: event_loop fixture removed â€” pytest-asyncio 0.23.x auto-provides per-function event loops.

@pytest.fixture
async def client(tmp_path, monkeypatch):
    # Point the app data dir AND NAS root to temporary paths before FastAPI loads settings
    monkeypatch.setenv("AHC_DATA_DIR", str(tmp_path))

    nas_tmp = tmp_path / "nas"
    nas_tmp.mkdir()
    (nas_tmp / "shared").mkdir()
    (nas_tmp / "personal").mkdir()

    from app.config import settings
    from app.main import app
    from app import store

    monkeypatch.setattr(settings, "data_dir", tmp_path)
    monkeypatch.setattr(settings, "nas_root", nas_tmp)
    monkeypatch.setattr(settings, "skip_mount_check", True)

    # Clear module-level cache so stale data from previous tests is discarded
    store._cache.clear()

    # Reset rate limiter storage and account lockout between tests
    try:
        from app.limiter import limiter
        limiter._storage.reset()
    except Exception:
        pass
    try:
        from app.routes.auth_routes import _failed_logins
        _failed_logins.clear()
    except Exception:
        pass

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac

    # Cleanup after test
    store._cache.clear()


@pytest.fixture
async def admin_token(client: AsyncClient):
    """
    Create an admin user and return a valid JWT access token.
    Uses a short PIN (4 digits) to avoid bcrypt 72-byte limit issues.
    Named "admin" to match test expectations.
    """
    # Create first user (becomes admin) and login to obtain token
    name = "admin"
    pin = "0000"  # Keep PIN short to avoid bcrypt byte limit issues
    
    # Create user
    resp = await client.post("/api/v1/users", json={"name": name, "pin": pin})
    assert resp.status_code in (200, 201), f"User creation failed: {resp.text}"

    # Login
    resp = await client.post("/api/v1/auth/login", json={"name": name, "pin": pin})
    assert resp.status_code == 200, f"Login failed: {resp.text}"
    
    body = resp.json()
    token = body.get("accessToken")
    assert token, f"No accessToken in response: {body}"
    
    return token


@pytest.fixture
async def authenticated_client(client: AsyncClient, admin_token: str):
    """
    Return a client with Authorization header pre-set with admin token.
    Use this in tests that need authentication.
    """
    client.headers.update({"Authorization": f"Bearer {admin_token}"})
    return client
