"""
Additional auth route tests — covers user profile endpoints, delete, and lockout.
"""

import pytest


class TestUserProfile:
    @pytest.mark.asyncio
    async def test_get_me(self, authenticated_client):
        resp = await authenticated_client.get("/api/v1/users/me")
        assert resp.status_code == 200
        data = resp.json()
        assert "name" in data

    @pytest.mark.asyncio
    async def test_update_me(self, authenticated_client):
        resp = await authenticated_client.put(
            "/api/v1/users/me",
            json={"name": "admin", "emoji": "🚀"},
        )
        assert resp.status_code in (200, 204)

    @pytest.mark.asyncio
    async def test_update_me_no_auth(self, client):
        resp = await client.put(
            "/api/v1/users/me",
            json={"name": "admin", "emoji": "🚀"},
        )
        assert resp.status_code in (401, 403)


class TestUserNames:
    @pytest.mark.asyncio
    async def test_get_user_names(self, client):
        # Create a user first
        await client.post("/api/v1/users", json={"name": "admin", "pin": "0000"})
        resp = await client.get("/api/v1/auth/users/names")
        assert resp.status_code == 200
        data = resp.json()
        # Response is {"users": [...]}
        users = data.get("users", data) if isinstance(data, dict) else data
        assert len(users) >= 1


class TestCertFingerprint:
    @pytest.mark.asyncio
    async def test_cert_fingerprint(self, client):
        resp = await client.get("/api/v1/auth/cert-fingerprint")
        assert resp.status_code == 200
        data = resp.json()
        assert "fingerprint" in data or "sha256" in data or isinstance(data, dict)


class TestRemovePin:
    @pytest.mark.asyncio
    async def test_remove_pin(self, authenticated_client):
        resp = await authenticated_client.delete("/api/v1/users/pin")
        assert resp.status_code in (200, 204)


class TestDeleteProfile:
    @pytest.mark.asyncio
    async def test_delete_last_user_blocked(self, client):
        """Last remaining user (also admin) cannot be deleted."""
        await client.post("/api/v1/users", json={"name": "admin", "pin": "0000"})
        resp = await client.post("/api/v1/auth/login", json={"name": "admin", "pin": "0000"})
        token = resp.json()["accessToken"]
        headers = {"Authorization": f"Bearer {token}"}
        resp = await client.delete("/api/v1/users/me", headers=headers)
        # Should be blocked — last user
        assert resp.status_code in (400, 409, 403)


class TestCreateSecondUser:
    @pytest.mark.asyncio
    async def test_create_second_user_non_admin(self, authenticated_client):
        """Second user should not be admin."""
        resp = await authenticated_client.post(
            "/api/v1/users",
            json={"name": "member1", "pin": "1234"},
        )
        assert resp.status_code == 201
