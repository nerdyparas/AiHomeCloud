import os
import asyncio
from pathlib import Path
import pytest

# Ensure test deps are present: httpx, pytest-asyncio
from httpx import AsyncClient

# Set environment variable before importing the app so Settings picks it up
@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
async def client(tmp_path, monkeypatch):
    # Point the app data dir to a temporary path
    monkeypatch.setenv("CUBIE_DATA_DIR", str(tmp_path))

    # Import app after env var set
    from app.main import app

    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac


@pytest.fixture
async def admin_token(client: AsyncClient):
    # Create first user (becomes admin) and login to obtain token
    name = "test-admin"
    pin = "0000"
    # Create user
    resp = await client.post("/api/v1/users", json={"name": name, "pin": pin})
    assert resp.status_code in (200, 201)

    # Login
    resp = await client.post("/api/v1/auth/login", json={"name": name, "pin": pin})
    assert resp.status_code == 200
    body = resp.json()
    token = body.get("accessToken")
    assert token
    return token
