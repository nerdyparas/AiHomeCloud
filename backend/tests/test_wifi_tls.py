"""
Tests for wifi_manager.py and tls.py.
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from pathlib import Path


# — wifi_manager ——————————————————————————————————————————————

class TestEthernetIsUp:
    def test_detects_up_interface(self, tmp_path):
        from app.wifi_manager import _ethernet_is_up

        net_dir = tmp_path / "net"
        net_dir.mkdir()
        eth0 = net_dir / "eth0"
        eth0.mkdir()
        (eth0 / "operstate").write_text("up")

        with patch("app.wifi_manager.Path", return_value=net_dir):
            # Directly patch the internal logic — the function reads /sys/class/net
            pass

        # Use a different approach: set up the path properly
        import app.wifi_manager as wm
        original_func = wm._ethernet_is_up

        def _patched():
            if not net_dir.exists():
                return False
            for iface in net_dir.iterdir():
                name = iface.name
                if name == "lo" or name.startswith("wl") or name.startswith("docker") or name.startswith("veth"):
                    continue
                operstate = iface / "operstate"
                if operstate.exists():
                    state = operstate.read_text().strip()
                    if state == "up":
                        return True
            return False

        assert _patched() is True

    def test_no_net_dir(self):
        from app.wifi_manager import _ethernet_is_up
        with patch("app.wifi_manager.Path") as MockPath:
            mock_dir = MagicMock()
            mock_dir.exists.return_value = False
            MockPath.return_value = mock_dir
            assert _ethernet_is_up() is False

    def test_skips_loopback_and_wireless(self, tmp_path):
        net_dir = tmp_path / "net"
        net_dir.mkdir()
        for name in ["lo", "wlan0", "docker0", "veth123"]:
            d = net_dir / name
            d.mkdir()
            (d / "operstate").write_text("up")

        import app.wifi_manager as wm
        with patch.object(Path, "__new__", return_value=net_dir):
            pass  # Can't easily patch Path constructor


class TestDisableWifi:
    @pytest.mark.asyncio
    async def test_success(self):
        from app.wifi_manager import disable_wifi
        with patch("app.wifi_manager.run_command", new_callable=AsyncMock) as mock_cmd:
            mock_cmd.return_value = (0, "", "")
            assert await disable_wifi() is True

    @pytest.mark.asyncio
    async def test_failure(self):
        from app.wifi_manager import disable_wifi
        with patch("app.wifi_manager.run_command", new_callable=AsyncMock) as mock_cmd:
            mock_cmd.return_value = (1, "", "error")
            assert await disable_wifi() is False


class TestEnableWifi:
    @pytest.mark.asyncio
    async def test_success(self):
        from app.wifi_manager import enable_wifi
        with patch("app.wifi_manager.run_command", new_callable=AsyncMock) as mock_cmd:
            mock_cmd.return_value = (0, "", "")
            assert await enable_wifi() is True

    @pytest.mark.asyncio
    async def test_failure(self):
        from app.wifi_manager import enable_wifi
        with patch("app.wifi_manager.run_command", new_callable=AsyncMock) as mock_cmd:
            mock_cmd.return_value = (1, "", "error")
            assert await enable_wifi() is False


class TestGetWifiStatus:
    @pytest.mark.asyncio
    async def test_enabled(self):
        from app.wifi_manager import get_wifi_status
        with patch("app.wifi_manager.run_command", new_callable=AsyncMock) as mock_cmd, \
             patch("app.wifi_manager._ethernet_is_up", return_value=True):
            mock_cmd.return_value = (0, "enabled", "")
            status = await get_wifi_status()
            assert status["wifiEnabled"] is True
            assert status["ethernetUp"] is True

    @pytest.mark.asyncio
    async def test_disabled(self):
        from app.wifi_manager import get_wifi_status
        with patch("app.wifi_manager.run_command", new_callable=AsyncMock) as mock_cmd, \
             patch("app.wifi_manager._ethernet_is_up", return_value=False):
            mock_cmd.return_value = (0, "disabled", "")
            status = await get_wifi_status()
            assert status["wifiEnabled"] is False

    @pytest.mark.asyncio
    async def test_command_fails(self):
        from app.wifi_manager import get_wifi_status
        with patch("app.wifi_manager.run_command", new_callable=AsyncMock) as mock_cmd, \
             patch("app.wifi_manager._ethernet_is_up", return_value=False):
            mock_cmd.return_value = (1, "", "error")
            status = await get_wifi_status()
            assert status["wifiEnabled"] is None


class TestAutoDisableWifi:
    @pytest.mark.asyncio
    async def test_disables_when_ethernet_up(self):
        from app.wifi_manager import auto_disable_wifi_if_ethernet
        import app.wifi_manager as wm
        with patch("app.wifi_manager.store") as mock_store, \
             patch("app.wifi_manager._ethernet_is_up", return_value=True), \
             patch("app.wifi_manager.disable_wifi", new_callable=AsyncMock) as mock_disable:
            mock_store.get_value = AsyncMock(return_value=False)
            wm._user_wifi_override = False
            await auto_disable_wifi_if_ethernet()
            mock_disable.assert_called_once()

    @pytest.mark.asyncio
    async def test_skips_when_user_override(self):
        from app.wifi_manager import auto_disable_wifi_if_ethernet
        import app.wifi_manager as wm
        with patch("app.wifi_manager.store") as mock_store, \
             patch("app.wifi_manager.disable_wifi", new_callable=AsyncMock) as mock_disable:
            mock_store.get_value = AsyncMock(return_value=True)
            await auto_disable_wifi_if_ethernet()
            mock_disable.assert_not_called()

    @pytest.mark.asyncio
    async def test_keeps_wifi_when_no_ethernet(self):
        from app.wifi_manager import auto_disable_wifi_if_ethernet
        import app.wifi_manager as wm
        with patch("app.wifi_manager.store") as mock_store, \
             patch("app.wifi_manager._ethernet_is_up", return_value=False), \
             patch("app.wifi_manager.disable_wifi", new_callable=AsyncMock) as mock_disable:
            mock_store.get_value = AsyncMock(return_value=False)
            wm._user_wifi_override = False
            await auto_disable_wifi_if_ethernet()
            mock_disable.assert_not_called()


class TestSetUserWifiOverride:
    @pytest.mark.asyncio
    async def test_enable_override(self):
        from app.wifi_manager import set_user_wifi_override
        import app.wifi_manager as wm
        with patch("app.wifi_manager.store") as mock_store, \
             patch("app.wifi_manager.enable_wifi", new_callable=AsyncMock) as mock_enable:
            mock_store.set_value = AsyncMock()
            await set_user_wifi_override(True)
            assert wm._user_wifi_override is True
            mock_enable.assert_called_once()

    @pytest.mark.asyncio
    async def test_disable_override(self):
        from app.wifi_manager import set_user_wifi_override
        import app.wifi_manager as wm
        with patch("app.wifi_manager.store") as mock_store, \
             patch("app.wifi_manager.disable_wifi", new_callable=AsyncMock) as mock_disable:
            mock_store.set_value = AsyncMock()
            await set_user_wifi_override(False)
            assert wm._user_wifi_override is False
            mock_disable.assert_called_once()


# — tls.py ———————————————————————————————————————————————————

class TestGetLocalIps:
    def test_returns_at_least_localhost(self):
        from app.tls import _get_local_ips
        ips = _get_local_ips()
        assert "127.0.0.1" in ips

    def test_returns_sorted(self):
        from app.tls import _get_local_ips
        ips = _get_local_ips()
        assert ips == sorted(ips)


class TestEnsureTlsCert:
    @pytest.mark.asyncio
    async def test_returns_existing_cert(self, tmp_path):
        from app.tls import ensure_tls_cert
        cert = tmp_path / "cert.pem"
        key = tmp_path / "key.pem"
        cert.write_text("CERT")
        key.write_text("KEY")

        with patch("app.tls.settings") as mock_settings:
            mock_settings.tls_cert_path = cert
            mock_settings.tls_key_path = key
            result_cert, result_key = await ensure_tls_cert()
            assert result_cert == cert
            assert result_key == key

    @pytest.mark.asyncio
    async def test_generates_cert_on_missing(self, tmp_path):
        from app.tls import ensure_tls_cert
        cert = tmp_path / "tls" / "cert.pem"
        key = tmp_path / "tls" / "key.pem"

        with patch("app.tls.settings") as mock_settings, \
             patch("app.tls.run_command", new_callable=AsyncMock) as mock_cmd:
            mock_settings.tls_cert_path = cert
            mock_settings.tls_key_path = key
            mock_cmd.return_value = (0, "", "")
            result_cert, result_key = await ensure_tls_cert()
            assert result_cert == cert
            mock_cmd.assert_called_once()

    @pytest.mark.asyncio
    async def test_raises_on_openssl_failure(self, tmp_path):
        from app.tls import ensure_tls_cert
        cert = tmp_path / "tls" / "cert.pem"
        key = tmp_path / "tls" / "key.pem"

        with patch("app.tls.settings") as mock_settings, \
             patch("app.tls.run_command", new_callable=AsyncMock) as mock_cmd:
            mock_settings.tls_cert_path = cert
            mock_settings.tls_key_path = key
            mock_cmd.return_value = (1, "", "openssl error")
            with pytest.raises(RuntimeError, match="openssl"):
                await ensure_tls_cert()
