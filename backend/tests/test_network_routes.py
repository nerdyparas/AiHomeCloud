"""
Tests for network_routes.py — WiFi status, toggle, LAN network status.
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock


class TestNetworkStatus:
    @pytest.mark.asyncio
    async def test_network_status(self, authenticated_client):
        """Test basic network status returns expected fields."""
        with patch("app.routes.network_routes.Path") as mock_path_cls:
            net_dir = MagicMock()
            net_dir.exists.return_value = False
            mock_path_cls.return_value = net_dir
            resp = await authenticated_client.get("/api/v1/network/status")
            assert resp.status_code == 200
            data = resp.json()
            assert "lan_connected" in data or "lanConnected" in data


class TestWifiStatus:
    @pytest.mark.asyncio
    async def test_wifi_status(self, authenticated_client):
        with patch("app.routes.network_routes.get_wifi_status", new_callable=AsyncMock) as mock_ws:
            mock_ws.return_value = {
                "wifi_enabled": False,
                "ethernet_up": True,
                "user_override": None,
            }
            resp = await authenticated_client.get("/api/v1/network/wifi")
            assert resp.status_code == 200


class TestToggleWifi:
    @pytest.mark.asyncio
    async def test_toggle_wifi(self, authenticated_client):
        with patch("app.routes.network_routes.set_user_wifi_override", new_callable=AsyncMock), \
             patch("app.routes.network_routes.get_wifi_status", new_callable=AsyncMock) as mock_ws:
            mock_ws.return_value = {
                "wifi_enabled": True,
                "ethernet_up": False,
                "user_override": True,
            }
            resp = await authenticated_client.put(
                "/api/v1/network/wifi",
                json={"enabled": True},
            )
            assert resp.status_code == 200
