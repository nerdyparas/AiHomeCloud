"""Tests for backend/app/auto_ap.py — Auto-AP startup logic."""

import asyncio
from unittest.mock import AsyncMock, patch, MagicMock

import pytest

from app.auto_ap import (
    _has_lan,
    _has_wifi_station,
    _is_hotspot_active,
    _start_hotspot,
    _stop_hotspot,
    maybe_start_auto_ap,
    shutdown_auto_ap,
)
import app.auto_ap as auto_ap_module


# ── Helper to mock run_command ─────────────────────────────────────────────

def _mock_run(*call_map):
    """Build a side_effect for run_command that maps cmd prefixes to results."""
    mapping = {tuple(k): v for k, v in call_map}

    async def _side_effect(cmd, timeout=5):
        # Match by exact cmd or by prefix
        key = tuple(cmd)
        if key in mapping:
            return mapping[key]
        # Try prefix match (first 3 tokens)
        for length in (4, 3, 2):
            prefix = tuple(cmd[:length])
            if prefix in mapping:
                return mapping[prefix]
        return (1, "", "not mocked")

    return _side_effect


# ── _has_lan ─────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_has_lan_true():
    """Return True when eth0 is UP with an IP."""
    with patch("app.auto_ap.run_command", new_callable=AsyncMock) as mock_run:
        mock_run.side_effect = _mock_run(
            (["ip", "link", "show", "eth0"], (0, "2: eth0: <BROADCAST> state UP", "")),
            (["ip", "-4", "-o", "addr", "show", "eth0"], (0, "inet 192.168.0.10/24", "")),
        )
        assert await _has_lan() is True


@pytest.mark.asyncio
async def test_has_lan_false_no_interface():
    """Return False when no ethernet interface exists."""
    with patch("app.auto_ap.run_command", new_callable=AsyncMock) as mock_run:
        mock_run.return_value = (1, "", "not found")
        assert await _has_lan() is False


@pytest.mark.asyncio
async def test_has_lan_false_down():
    """Return False when eth0 exists but is DOWN."""
    with patch("app.auto_ap.run_command", new_callable=AsyncMock) as mock_run:
        mock_run.side_effect = _mock_run(
            (["ip", "link", "show", "eth0"], (0, "2: eth0: <BROADCAST> state DOWN", "")),
            (["ip", "link", "show", "end0"], (1, "", "not found")),
            (["ip", "link", "show", "enp1s0"], (1, "", "not found")),
        )
        assert await _has_lan() is False


# ── _has_wifi_station ────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_has_wifi_station_true():
    """Return True when wlan0 is connected in station mode."""
    with patch("app.auto_ap.run_command", new_callable=AsyncMock) as mock_run:
        mock_run.side_effect = _mock_run(
            (["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION"],
             (0, "wlan0:wifi:connected:MyNetwork", "")),
            (["nmcli", "-t", "-f", "802-11-wireless.mode"],
             (0, "802-11-wireless.mode:infra", "")),
        )
        assert await _has_wifi_station() is True


@pytest.mark.asyncio
async def test_has_wifi_station_false_ap_mode():
    """Return False when wlan0 is in AP mode (hotspot)."""
    with patch("app.auto_ap.run_command", new_callable=AsyncMock) as mock_run:
        mock_run.side_effect = _mock_run(
            (["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION"],
             (0, "wlan0:wifi:connected:Hotspot", "")),
            (["nmcli", "-t", "-f", "802-11-wireless.mode"],
             (0, "802-11-wireless.mode:ap", "")),
        )
        assert await _has_wifi_station() is False


@pytest.mark.asyncio
async def test_has_wifi_station_false_disconnected():
    """Return False when wlan0 is not connected."""
    with patch("app.auto_ap.run_command", new_callable=AsyncMock) as mock_run:
        mock_run.side_effect = _mock_run(
            (["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION"],
             (0, "wlan0:wifi:disconnected:", "")),
        )
        assert await _has_wifi_station() is False


# ── _is_hotspot_active ───────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_is_hotspot_active_true():
    """Return True when an AP-mode connection is active."""
    with patch("app.auto_ap.run_command", new_callable=AsyncMock) as mock_run:
        mock_run.side_effect = _mock_run(
            (["nmcli", "-t", "-f", "NAME,TYPE,DEVICE"],
             (0, "Hotspot:802-11-wireless:wlan0", "")),
            (["nmcli", "-t", "-f", "802-11-wireless.mode"],
             (0, "802-11-wireless.mode:ap", "")),
        )
        assert await _is_hotspot_active() is True


@pytest.mark.asyncio
async def test_is_hotspot_active_false():
    """Return False when no AP-mode connection is active."""
    with patch("app.auto_ap.run_command", new_callable=AsyncMock) as mock_run:
        mock_run.return_value = (0, "", "")
        assert await _is_hotspot_active() is False


# ── _start_hotspot ───────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_start_hotspot_creates_new():
    """Start hotspot with nmcli when no existing profile."""
    auto_ap_module._auto_ap_active = False
    with patch("app.auto_ap.run_command", new_callable=AsyncMock) as mock_run:
        mock_run.side_effect = _mock_run(
            # No existing hotspot profile
            (["nmcli", "-t", "-f", "NAME,TYPE"], (0, "MyWifi:802-11-wireless", "")),
            # Create hotspot succeeds
            (["nmcli", "device", "wifi", "hotspot"], (0, "", "")),
        )
        result = await _start_hotspot()
        assert result is True
        assert auto_ap_module._auto_ap_active is True


@pytest.mark.asyncio
async def test_start_hotspot_reuses_profile():
    """Start hotspot by activating existing 'hotspot' profile."""
    auto_ap_module._auto_ap_active = False
    with patch("app.auto_ap.run_command", new_callable=AsyncMock) as mock_run:
        mock_run.side_effect = _mock_run(
            (["nmcli", "-t", "-f", "NAME,TYPE"],
             (0, "Hotspot:802-11-wireless\nother:802-3-ethernet", "")),
            (["nmcli", "connection", "up", "Hotspot"], (0, "", "")),
        )
        result = await _start_hotspot()
        assert result is True
        assert auto_ap_module._auto_ap_active is True


@pytest.mark.asyncio
async def test_start_hotspot_failure():
    """Return False when nmcli fails."""
    auto_ap_module._auto_ap_active = False
    with patch("app.auto_ap.run_command", new_callable=AsyncMock) as mock_run:
        mock_run.side_effect = _mock_run(
            (["nmcli", "-t", "-f", "NAME,TYPE"], (0, "", "")),
            (["nmcli", "device", "wifi", "hotspot"], (1, "", "Error: no wifi device")),
        )
        result = await _start_hotspot()
        assert result is False
        assert auto_ap_module._auto_ap_active is False


# ── maybe_start_auto_ap ─────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_maybe_start_auto_ap_disabled():
    """When auto_ap_enabled is False, do nothing."""
    auto_ap_module._auto_ap_active = False
    auto_ap_module._monitor_task = None

    with patch("app.auto_ap.settings") as mock_settings:
        mock_settings.auto_ap_enabled = False
        await maybe_start_auto_ap()

    assert auto_ap_module._monitor_task is None


@pytest.mark.asyncio
async def test_maybe_start_auto_ap_with_network():
    """When network is available, don't start hotspot but do start monitor."""
    auto_ap_module._auto_ap_active = False
    auto_ap_module._monitor_task = None

    with patch("app.auto_ap.settings") as mock_settings, \
         patch("app.auto_ap._has_lan", new_callable=AsyncMock, return_value=True), \
         patch("app.auto_ap._has_wifi_station", new_callable=AsyncMock, return_value=False), \
         patch("app.auto_ap._start_hotspot", new_callable=AsyncMock) as mock_start:
        mock_settings.auto_ap_enabled = True
        await maybe_start_auto_ap()

    mock_start.assert_not_called()
    # Monitor task should have been started
    assert auto_ap_module._monitor_task is not None
    # Clean up
    await shutdown_auto_ap()


@pytest.mark.asyncio
async def test_maybe_start_auto_ap_no_network():
    """When no network, start hotspot and monitor."""
    auto_ap_module._auto_ap_active = False
    auto_ap_module._monitor_task = None

    with patch("app.auto_ap.settings") as mock_settings, \
         patch("app.auto_ap._has_lan", new_callable=AsyncMock, return_value=False), \
         patch("app.auto_ap._has_wifi_station", new_callable=AsyncMock, return_value=False), \
         patch("app.auto_ap._start_hotspot", new_callable=AsyncMock, return_value=True) as mock_start:
        mock_settings.auto_ap_enabled = True
        await maybe_start_auto_ap()

    mock_start.assert_called_once()
    assert auto_ap_module._monitor_task is not None
    await shutdown_auto_ap()


# ── shutdown_auto_ap ─────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_shutdown_auto_ap():
    """Shutdown cancels the monitor task and resets state."""
    auto_ap_module._auto_ap_active = True
    auto_ap_module._monitor_task = asyncio.create_task(asyncio.sleep(999))

    await shutdown_auto_ap()

    assert auto_ap_module._auto_ap_active is False
    assert auto_ap_module._monitor_task is None


# ── API endpoint tests (via httpx) ──────────────────────────────────────────

@pytest.mark.asyncio
async def test_auto_ap_get_requires_auth(client):
    """GET /api/v1/network/auto-ap requires auth."""
    resp = await client.get("/api/v1/network/auto-ap")
    assert resp.status_code in (401, 403)


@pytest.mark.asyncio
async def test_auto_ap_put_requires_admin(client):
    """PUT /api/v1/network/auto-ap requires admin."""
    resp = await client.put(
        "/api/v1/network/auto-ap",
        json={"enabled": False},
    )
    assert resp.status_code in (401, 403)


@pytest.mark.asyncio
async def test_auto_ap_get_returns_status(client, admin_token):
    """GET /api/v1/network/auto-ap returns current config."""
    resp = await client.get(
        "/api/v1/network/auto-ap",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert "enabled" in body
    assert "hotspotSsid" in body
    assert "autoApActive" in body
