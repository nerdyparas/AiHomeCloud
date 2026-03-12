"""Tests for AdGuard status and proxy endpoints."""

from unittest.mock import AsyncMock, patch

import pytest


@pytest.mark.asyncio
async def test_status_not_installed(client, admin_token):
    """When binary is absent, installed=False and service_running=False."""
    with patch("app.routes.adguard_routes.Path.exists", return_value=False):
        resp = await client.get(
            "/api/v1/adguard/status",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
    assert resp.status_code == 200
    data = resp.json()
    assert data["installed"] is False
    assert data["service_running"] is False


@pytest.mark.asyncio
async def test_status_installed_service_running(client, admin_token):
    """When binary exists and service is active, status reports running."""
    with (
        patch("app.routes.adguard_routes.Path.exists", return_value=True),
        patch(
            "app.routes.adguard_routes.run_command",
            new_callable=AsyncMock,
            return_value=(0, "", ""),
        ),
    ):
        resp = await client.get(
            "/api/v1/adguard/status",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
    assert resp.status_code == 200
    assert resp.json()["service_running"] is True


@pytest.mark.asyncio
async def test_stats_returns_503_when_disabled(client, admin_token):
    """stats endpoint still returns 503 when adguard_enabled=False."""
    resp = await client.get(
        "/api/v1/adguard/stats",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert resp.status_code == 503


@pytest.mark.asyncio
async def test_status_requires_auth(client):
    """status endpoint requires a valid JWT."""
    resp = await client.get("/api/v1/adguard/status")
    assert resp.status_code == 401
