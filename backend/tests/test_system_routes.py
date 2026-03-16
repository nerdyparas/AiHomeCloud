"""
Tests for system_routes.py — device info, firmware check, device name.
"""

import pytest
from unittest.mock import AsyncMock, patch


class TestSystemInfo:
    @pytest.mark.asyncio
    async def test_device_info(self, authenticated_client):
        resp = await authenticated_client.get("/api/v1/system/info")
        assert resp.status_code == 200
        data = resp.json()
        assert "serial" in data or "name" in data

    @pytest.mark.asyncio
    async def test_firmware_info(self, authenticated_client):
        resp = await authenticated_client.get("/api/v1/system/firmware")
        assert resp.status_code == 200
        data = resp.json()
        assert "update_available" in data or "updateAvailable" in data

    @pytest.mark.asyncio
    async def test_trigger_update_501(self, authenticated_client):
        resp = await authenticated_client.post("/api/v1/system/update")
        assert resp.status_code == 501


class TestDeviceName:
    @pytest.mark.asyncio
    async def test_update_name(self, authenticated_client):
        with patch("app.routes.system_routes.store") as mock_store:
            mock_store.update_device_name = AsyncMock()
            resp = await authenticated_client.put(
                "/api/v1/system/name",
                json={"name": "My Cubie"},
            )
            assert resp.status_code == 204

    @pytest.mark.asyncio
    async def test_update_name_empty(self, authenticated_client):
        resp = await authenticated_client.put(
            "/api/v1/system/name",
            json={"name": "  "},
        )
        assert resp.status_code == 400


class TestPowerEndpoints:
    @pytest.mark.asyncio
    async def test_shutdown(self, authenticated_client):
        with patch("app.routes.system_routes.store") as mock_store, \
             patch("app.routes.system_routes.run_command", new_callable=AsyncMock, return_value=(0, "", "")), \
             patch("app.routes.system_routes._deferred_power_command", new_callable=AsyncMock):
            mock_store.get_services = AsyncMock(return_value=[])
            resp = await authenticated_client.post("/api/v1/system/shutdown")
            assert resp.status_code == 202

    @pytest.mark.asyncio
    async def test_reboot(self, authenticated_client):
        with patch("app.routes.system_routes._deferred_power_command", new_callable=AsyncMock):
            resp = await authenticated_client.post("/api/v1/system/reboot")
            assert resp.status_code == 202

    @pytest.mark.asyncio
    async def test_shutdown_stops_services(self, authenticated_client):
        with patch("app.routes.system_routes.store") as mock_store, \
             patch("app.routes.system_routes._systemctl_stop", new_callable=AsyncMock, return_value=(True, "")) as mock_stop, \
             patch("app.routes.system_routes._deferred_power_command", new_callable=AsyncMock):
            mock_store.get_services = AsyncMock(return_value=[
                {"id": "samba", "isEnabled": True},
            ])
            resp = await authenticated_client.post("/api/v1/system/shutdown")
            assert resp.status_code == 202
            assert mock_stop.called
