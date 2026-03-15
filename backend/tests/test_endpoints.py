"""
System, Family, Service, Network, Health, Job, and AdGuard route tests.
Covers endpoints not yet tested by existing test files.
"""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import AsyncClient


# â”€â”€â”€ Health â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@pytest.mark.asyncio
async def test_health_endpoint_returns_ok(client: AsyncClient):
    """GET /api/health returns {status: ok} without authentication."""
    response = await client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_root_endpoint_returns_device_info(client: AsyncClient):
    """GET / returns service info."""
    response = await client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["service"] == "AiHomeCloud"
    assert "serial" in data


# â”€â”€â”€ System â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@pytest.mark.asyncio
async def test_system_info_returns_device(authenticated_client: AsyncClient):
    """GET /api/v1/system/info returns device info."""
    response = await authenticated_client.get("/api/v1/system/info")
    assert response.status_code == 200
    data = response.json()
    assert "serial" in data
    assert "name" in data
    assert "ip" in data
    assert "firmwareVersion" in data


@pytest.mark.asyncio
async def test_system_firmware_check(authenticated_client: AsyncClient):
    """GET /api/v1/system/firmware returns firmware info."""
    response = await authenticated_client.get("/api/v1/system/firmware")
    assert response.status_code == 200
    data = response.json()
    assert "current_version" in data
    assert "latest_version" in data
    assert "update_available" in data


@pytest.mark.asyncio
async def test_system_update_trigger(authenticated_client: AsyncClient):
    """POST /api/v1/system/update returns 202 accepted."""
    response = await authenticated_client.post("/api/v1/system/update")
    assert response.status_code == 202


@pytest.mark.asyncio
async def test_system_name_update(authenticated_client: AsyncClient):
    """PUT /api/v1/system/name updates the device name."""
    response = await authenticated_client.put(
        "/api/v1/system/name",
        json={"name": "TestCubie"},
    )
    assert response.status_code == 204

    # Verify the name changed
    response = await authenticated_client.get("/api/v1/system/info")
    assert response.json()["name"] == "TestCubie"


@pytest.mark.asyncio
async def test_system_name_empty_returns_400(authenticated_client: AsyncClient):
    """PUT /api/v1/system/name with empty name returns 400 or 422 (Pydantic min_length)."""
    response = await authenticated_client.put(
        "/api/v1/system/name",
        json={"name": ""},
    )
    assert response.status_code in (400, 422)


@pytest.mark.asyncio
async def test_system_info_requires_auth(client: AsyncClient):
    """GET /api/v1/system/info without auth returns 401/403."""
    response = await client.get("/api/v1/system/info")
    assert response.status_code in (401, 403)


# â”€â”€â”€ Family / Users â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@pytest.mark.asyncio
async def test_family_list_returns_users(authenticated_client: AsyncClient):
    """GET /api/v1/users/family returns list of users."""
    response = await authenticated_client.get("/api/v1/users/family")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    # At least the admin user should be present
    assert len(data) >= 1
    user = data[0]
    assert "id" in user
    assert "name" in user
    assert "isAdmin" in user
    assert "folderSizeGB" in user
    assert "avatarColor" in user


@pytest.mark.asyncio
async def test_add_family_member(authenticated_client: AsyncClient):
    """POST /api/v1/users/family adds a new family member."""
    response = await authenticated_client.post(
        "/api/v1/users/family",
        json={"name": "TestChild"},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "TestChild"
    assert data["isAdmin"] is False


@pytest.mark.asyncio
async def test_add_family_empty_name_returns_400(authenticated_client: AsyncClient):
    """POST /api/v1/users/family with empty name returns 400."""
    response = await authenticated_client.post(
        "/api/v1/users/family",
        json={"name": ""},
    )
    assert response.status_code == 400


@pytest.mark.asyncio
async def test_remove_family_member(authenticated_client: AsyncClient):
    """DELETE /api/v1/users/family/{id} removes the user."""
    # Create a user first
    resp = await authenticated_client.post(
        "/api/v1/users/family",
        json={"name": "ToRemove"},
    )
    user_id = resp.json()["id"]

    # Remove
    response = await authenticated_client.delete(f"/api/v1/users/family/{user_id}")
    assert response.status_code == 204


@pytest.mark.asyncio
async def test_remove_nonexistent_family_returns_404(authenticated_client: AsyncClient):
    """DELETE /api/v1/users/family/{id} with bad id returns 404."""
    response = await authenticated_client.delete("/api/v1/users/family/nonexistent_id")
    assert response.status_code == 404


# â”€â”€â”€ Services â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@pytest.mark.asyncio
async def test_services_list(authenticated_client: AsyncClient):
    """GET /api/v1/services returns list of services."""
    response = await authenticated_client.get("/api/v1/services")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) >= 1
    for svc in data:
        assert "id" in svc
        assert "name" in svc
        assert "isEnabled" in svc


@pytest.mark.asyncio
async def test_service_toggle(authenticated_client: AsyncClient):
    """POST /api/v1/services/{id}/toggle toggles service state."""
    # Get services first
    resp = await authenticated_client.get("/api/v1/services")
    services = resp.json()
    if services:
        svc_id = services[0]["id"]
        response = await authenticated_client.post(
            f"/api/v1/services/{svc_id}/toggle",
            json={"enabled": False},
        )
        # 204 on success, or error if systemd not available
        assert response.status_code == 204


@pytest.mark.asyncio
async def test_service_toggle_nonexistent_returns_404(authenticated_client: AsyncClient):
    """Toggle a nonexistent service returns 404."""
    response = await authenticated_client.post(
        "/api/v1/services/nonexistent_service/toggle",
        json={"enabled": True},
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_services_list_requires_auth(client: AsyncClient):
    """GET /api/v1/services without auth returns 401/403."""
    response = await client.get("/api/v1/services")
    assert response.status_code in (401, 403)


# â”€â”€â”€ Jobs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@pytest.mark.asyncio
async def test_job_nonexistent_returns_404(authenticated_client: AsyncClient):
    """GET /api/v1/jobs/{id} with nonexistent id returns 404."""
    response = await authenticated_client.get("/api/v1/jobs/nonexistent_job_id")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_job_requires_auth(client: AsyncClient):
    """GET /api/v1/jobs/{id} without auth returns 401/403."""
    response = await client.get("/api/v1/jobs/some_id")
    assert response.status_code in (401, 403)


# â”€â”€â”€ Backward compatibility redirect â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@pytest.mark.asyncio
async def test_api_redirect_preserves_path(client: AsyncClient):
    """GET /api/health should still work (unversioned health is direct, not redirected)."""
    response = await client.get("/api/health")
    assert response.status_code == 200


# â”€â”€â”€ Cert fingerprint â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@pytest.mark.asyncio
async def test_cert_fingerprint_endpoint(client: AsyncClient):
    """GET /api/v1/auth/cert-fingerprint returns fingerprint info."""
    response = await client.get("/api/v1/auth/cert-fingerprint")
    assert response.status_code == 200
    data = response.json()
    assert "fingerprint" in data
    assert data["algorithm"] == "sha256"


# â”€â”€â”€ QR Pairing â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

@pytest.mark.asyncio
async def test_qr_pairing_endpoint(client: AsyncClient):
    """GET /api/v1/pair/qr returns pairing QR info."""
    response = await client.get("/api/v1/pair/qr")
    assert response.status_code == 200
    data = response.json()
    assert "qrValue" in data
    assert "serial" in data
    assert "ip" in data
    assert "expiresAt" in data


@pytest.mark.asyncio
async def test_pair_with_wrong_serial_returns_403(client: AsyncClient):
    """POST /api/v1/pair with wrong serial returns 403."""
    response = await client.post(
        "/api/v1/pair",
        json={"serial": "WRONG-SERIAL", "key": "wrong-key"},
    )
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_pair_with_wrong_key_returns_403(client: AsyncClient):
    """POST /api/v1/pair with correct serial but wrong key returns 403."""
    from app.config import settings

    response = await client.post(
        "/api/v1/pair",
        json={"serial": settings.device_serial, "key": "wrong-key"},
    )
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_pair_with_correct_credentials(client: AsyncClient):
    """POST /api/v1/pair with correct serial and key returns JWT."""
    from app.config import settings

    response = await client.post(
        "/api/v1/pair",
        json={"serial": settings.device_serial, "key": settings.pairing_key},
    )
    assert response.status_code == 200
    data = response.json()
    assert "token" in data
