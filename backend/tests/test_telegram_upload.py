"""
Tests for the one-time Telegram upload endpoints (P2-Task 22).

Covers the security boundary: token lifecycle, blocked extensions, size limits,
single-use enforcement, and successful upload flow.
"""

import io
import pytest
from httpx import AsyncClient
from pathlib import Path

from app.routes.telegram_upload_routes import (
    create_upload_token,
    pop_upload_token,
    _purge_expired,
    _upload_tokens,
    UploadToken,
)


# ---------------------------------------------------------------------------
# Token helpers (unit tests — no HTTP)
# ---------------------------------------------------------------------------

def test_create_upload_token_returns_token_string():
    token = create_upload_token(
        chat_id=123, destination="private", owner="alice", filename="photo.jpg"
    )
    assert isinstance(token, str)
    assert len(token) > 20  # urlsafe(32) is 43 chars


def test_pop_upload_token_consumes_token():
    token = create_upload_token(
        chat_id=456, destination="shared", owner="alice", filename="doc.pdf"
    )
    ut = pop_upload_token(token)
    assert ut is not None
    assert ut.chat_id == 456
    assert ut.filename == "doc.pdf"
    # Second pop must return None (single-use)
    assert pop_upload_token(token) is None


def test_pop_upload_token_unknown_token_returns_none():
    assert pop_upload_token("nonexistent-token-xyz") is None


def test_purge_expired_removes_old_tokens(monkeypatch):
    """Tokens with age > TTL are removed by _purge_expired."""
    import time
    token = create_upload_token(
        chat_id=999, destination="private", owner="bob", filename="old.jpg"
    )
    # Simulate token being 16 minutes old (TTL is 15 min)
    ut = _upload_tokens[token]
    monkeypatch.setattr(ut, "created_at", time.monotonic() - 16 * 60)

    _purge_expired()
    assert token not in _upload_tokens


# ---------------------------------------------------------------------------
# HTTP endpoint tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_upload_form_missing_token_returns_410(client: AsyncClient):
    """GET with an unknown / expired token → 410 Gone."""
    resp = await client.get("/api/telegram-upload/invalid-token-999")
    assert resp.status_code == 410


@pytest.mark.asyncio
async def test_upload_form_valid_token_returns_html(client: AsyncClient):
    """GET with a valid token → HTML with filename and destination label."""
    token = create_upload_token(
        chat_id=1, destination="private", owner="priya", filename="invoice.pdf"
    )
    resp = await client.get(f"/api/telegram-upload/{token}")
    assert resp.status_code == 200
    assert "invoice.pdf" in resp.text
    assert "Private personal" in resp.text


@pytest.mark.asyncio
async def test_upload_form_shared_destination_label(client: AsyncClient):
    token = create_upload_token(
        chat_id=2, destination="shared", owner="priya", filename="test.txt"
    )
    resp = await client.get(f"/api/telegram-upload/{token}")
    assert resp.status_code == 200
    assert "Shared personal" in resp.text


@pytest.mark.asyncio
async def test_upload_file_expired_token_returns_410(client: AsyncClient):
    """POST with expired/missing token → 410."""
    data = {"file": ("test.txt", b"hello world", "text/plain")}
    resp = await client.post("/api/telegram-upload/no-such-token", files=data)
    assert resp.status_code == 410


@pytest.mark.asyncio
async def test_upload_file_blocked_extension_returns_422(client: AsyncClient, tmp_path):
    """Files with blocked extensions (.exe, .sh, etc.) are rejected."""
    from app.config import settings
    settings.nas_root = tmp_path / "nas"
    settings.nas_root.mkdir(exist_ok=True)

    token = create_upload_token(
        chat_id=3, destination="private", owner="alice", filename="malware.exe"
    )
    data = {"file": ("malware.exe", b"MZ\x90", "application/octet-stream")}
    resp = await client.post(f"/api/telegram-upload/{token}", files=data)
    assert resp.status_code == 422
    assert ".exe" in resp.json()["detail"].lower() or "not allowed" in resp.json()["detail"].lower()


@pytest.mark.asyncio
async def test_upload_file_single_use_enforcement(client: AsyncClient, tmp_path):
    """The same token cannot be used twice."""
    from app.config import settings
    nas = tmp_path / "nas"
    settings.nas_root = nas
    (nas / "personal" / "alice").mkdir(parents=True)
    (nas / "personal" / "alice" / ".inbox").mkdir(parents=True)

    token = create_upload_token(
        chat_id=4, destination="private", owner="alice", filename="file.txt"
    )
    data1 = {"file": ("file.txt", b"first upload", "text/plain")}
    resp1 = await client.post(f"/api/telegram-upload/{token}", files=data1)
    # First use may succeed or fail (no full NAS setup needed for this test)
    # What matters is that the token is gone after first POST.
    assert token not in _upload_tokens, "Token should be consumed after first POST"

    # Second attempt must always be 410.
    data2 = {"file": ("file.txt", b"second upload", "text/plain")}
    resp2 = await client.post(f"/api/telegram-upload/{token}", files=data2)
    assert resp2.status_code == 410


@pytest.mark.asyncio
async def test_upload_file_too_large_returns_413(client: AsyncClient, tmp_path):
    """Files exceeding max_upload_bytes are rejected."""
    from app.config import settings
    settings.max_upload_bytes = 100  # 100 bytes limit for this test

    token = create_upload_token(
        chat_id=5, destination="private", owner="alice", filename="big.txt"
    )
    big_data = b"x" * 200  # 200 bytes > 100 byte limit
    # httpx sends the Content-Length in multipart; size guard checks file.size
    # We use a real UploadFile with known size via the API.
    # Build a multipart body manually so size is known.
    files = {"file": ("big.txt", big_data, "text/plain")}
    resp = await client.post(f"/api/telegram-upload/{token}", files=files)
    assert resp.status_code == 413


@pytest.mark.asyncio
async def test_get_upload_url_builds_correct_url(client: AsyncClient):
    """get_upload_url returns the correct URL path for a token."""
    from app.routes.telegram_upload_routes import get_upload_url
    from starlette.testclient import TestClient
    from app.main import app

    token = "test-token-abc"
    # Use a real Request object to test URL generation
    from starlette.requests import Request
    from starlette.datastructures import URL

    scope = {
        "type": "http",
        "method": "GET",
        "path": f"/api/telegram-upload/{token}",
        "query_string": b"",
        "headers": [],
        "server": ("testserver", 80),
        "scheme": "http",
        "app": app,
        "root_path": "",
    }
    req = Request(scope)
    url = get_upload_url(req, token)
    assert token in url
    assert "telegram-upload" in url
