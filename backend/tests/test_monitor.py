"""
Tests for monitor_routes.py helper functions.
Covers _pick_network_counters, _read_system_stats.
"""

import time
from collections import namedtuple
from unittest.mock import patch, MagicMock

import pytest

from app.routes.monitor_routes import _pick_network_counters, _read_system_stats


NetCounters = namedtuple("NetCounters", ["bytes_sent", "bytes_recv", "packets_sent", "packets_recv", "errin", "errout", "dropin", "dropout"])


class TestPickNetworkCounters:
    def test_preferred_iface(self):
        per_nic = {
            "eth0": NetCounters(1000, 2000, 0, 0, 0, 0, 0, 0),
            "wlan0": NetCounters(500, 500, 0, 0, 0, 0, 0, 0),
        }
        with patch("app.routes.monitor_routes.psutil") as mock_psutil:
            mock_psutil.net_io_counters.return_value = per_nic
            counters, iface = _pick_network_counters("eth0")
            assert iface == "eth0"
            assert counters.bytes_sent == 1000

    def test_busiest_non_loopback(self):
        per_nic = {
            "lo": NetCounters(9999, 9999, 0, 0, 0, 0, 0, 0),
            "eth0": NetCounters(100, 200, 0, 0, 0, 0, 0, 0),
            "wlan0": NetCounters(1000, 2000, 0, 0, 0, 0, 0, 0),
        }
        with patch("app.routes.monitor_routes.psutil") as mock_psutil:
            mock_psutil.net_io_counters.side_effect = lambda pernic=False: per_nic if pernic else None
            counters, iface = _pick_network_counters(None)
            assert iface == "wlan0"

    def test_no_per_nic(self):
        total = NetCounters(500, 600, 0, 0, 0, 0, 0, 0)
        with patch("app.routes.monitor_routes.psutil") as mock_psutil:
            mock_psutil.net_io_counters.side_effect = lambda pernic=False: None if pernic else total
            counters, iface = _pick_network_counters()
            assert iface == "all"

    def test_only_loopback(self):
        per_nic = {
            "lo": NetCounters(100, 100, 0, 0, 0, 0, 0, 0),
        }
        total = NetCounters(100, 100, 0, 0, 0, 0, 0, 0)
        with patch("app.routes.monitor_routes.psutil") as mock_psutil:
            mock_psutil.net_io_counters.side_effect = lambda pernic=False: per_nic if pernic else total
            counters, iface = _pick_network_counters(None)
            assert iface == "all"

    def test_preferred_not_in_nics(self):
        per_nic = {
            "eth0": NetCounters(100, 200, 0, 0, 0, 0, 0, 0),
        }
        with patch("app.routes.monitor_routes.psutil") as mock_psutil:
            mock_psutil.net_io_counters.side_effect = lambda pernic=False: per_nic if pernic else None
            counters, iface = _pick_network_counters("wlan0")
            assert iface == "eth0"


class TestReadSystemStats:
    def test_basic_stats(self, tmp_path):
        """Test that _read_system_stats returns expected keys."""
        with patch("app.routes.monitor_routes.psutil") as mock_psutil, \
             patch("app.routes.monitor_routes.disk_usage") as mock_disk, \
             patch("app.routes.monitor_routes._pick_network_counters") as mock_net:

            mock_psutil.cpu_percent.return_value = 25.5
            mock_psutil.virtual_memory.return_value = MagicMock(percent=60.0)
            mock_psutil.sensors_temperatures.return_value = {
                "cpu_thermal": [MagicMock(current=45.0)]
            }
            mock_psutil.boot_time.return_value = time.time() - 3600

            mock_disk.return_value = MagicMock(total=100 * 1024**3, used=30 * 1024**3)

            net_counters = NetCounters(1000, 2000, 0, 0, 0, 0, 0, 0)
            mock_net.return_value = (net_counters, "eth0")

            stats, net, t = _read_system_stats(
                thermal_zone_path=None,
                lan_interface="eth0",
                prev_net=None,
                prev_time=None,
            )

            assert "cpuPercent" in stats
            assert "ramPercent" in stats
            assert "tempCelsius" in stats
            assert "uptimeSeconds" in stats
            assert "networkUpMbps" in stats
            assert "networkDownMbps" in stats
            assert "storage" in stats
            assert stats["cpuPercent"] == 25.5

    def test_with_thermal_zone_file(self, tmp_path):
        """Test reading temperature from a thermal zone file."""
        thermal_file = tmp_path / "temp"
        thermal_file.write_text("42500")

        with patch("app.routes.monitor_routes.psutil") as mock_psutil, \
             patch("app.routes.monitor_routes.disk_usage") as mock_disk, \
             patch("app.routes.monitor_routes._pick_network_counters") as mock_net:

            mock_psutil.cpu_percent.return_value = 10.0
            mock_psutil.virtual_memory.return_value = MagicMock(percent=50.0)
            mock_psutil.boot_time.return_value = time.time() - 100

            mock_disk.return_value = MagicMock(total=50 * 1024**3, used=10 * 1024**3)

            net_counters = NetCounters(0, 0, 0, 0, 0, 0, 0, 0)
            mock_net.return_value = (net_counters, "eth0")

            stats, _, _ = _read_system_stats(
                thermal_zone_path=str(thermal_file),
                lan_interface=None,
                prev_net=None,
                prev_time=None,
            )
            assert stats["tempCelsius"] == 42.5

    def test_with_prev_net_calculates_speed(self):
        """Test network speed calculation with previous counters."""
        with patch("app.routes.monitor_routes.psutil") as mock_psutil, \
             patch("app.routes.monitor_routes.disk_usage") as mock_disk, \
             patch("app.routes.monitor_routes._pick_network_counters") as mock_net:

            mock_psutil.cpu_percent.return_value = 5.0
            mock_psutil.virtual_memory.return_value = MagicMock(percent=30.0)
            mock_psutil.sensors_temperatures.return_value = {}
            mock_psutil.boot_time.return_value = time.time() - 100

            mock_disk.return_value = MagicMock(total=100 * 1024**3, used=50 * 1024**3)

            prev_net = NetCounters(0, 0, 0, 0, 0, 0, 0, 0)
            now_net = NetCounters(1_000_000, 2_000_000, 0, 0, 0, 0, 0, 0)
            mock_net.return_value = (now_net, "eth0")

            stats, _, _ = _read_system_stats(
                thermal_zone_path=None,
                lan_interface="eth0",
                prev_net=prev_net,
                prev_time=time.monotonic() - 1.0,
            )
            assert stats["networkUpMbps"] > 0
            assert stats["networkDownMbps"] > 0

    def test_disk_usage_exception(self):
        """Test fallback when disk_usage raises."""
        with patch("app.routes.monitor_routes.psutil") as mock_psutil, \
             patch("app.routes.monitor_routes.disk_usage") as mock_disk, \
             patch("app.routes.monitor_routes._pick_network_counters") as mock_net:

            mock_psutil.cpu_percent.return_value = 5.0
            mock_psutil.virtual_memory.return_value = MagicMock(percent=30.0)
            mock_psutil.sensors_temperatures.return_value = {}
            mock_psutil.boot_time.return_value = time.time() - 100

            mock_disk.side_effect = OSError("no mount")

            net_counters = NetCounters(0, 0, 0, 0, 0, 0, 0, 0)
            mock_net.return_value = (net_counters, "eth0")

            stats, _, _ = _read_system_stats(None, None, None, None)
            assert stats["storage"]["usedGB"] == 0.0

    def test_no_temp_sensors(self):
        """Test when no temperature sensors available."""
        with patch("app.routes.monitor_routes.psutil") as mock_psutil, \
             patch("app.routes.monitor_routes.disk_usage") as mock_disk, \
             patch("app.routes.monitor_routes._pick_network_counters") as mock_net:

            mock_psutil.cpu_percent.return_value = 5.0
            mock_psutil.virtual_memory.return_value = MagicMock(percent=30.0)
            mock_psutil.sensors_temperatures.return_value = {}
            mock_psutil.boot_time.return_value = time.time() - 100

            mock_disk.return_value = MagicMock(total=100 * 1024**3, used=50 * 1024**3)
            net_counters = NetCounters(0, 0, 0, 0, 0, 0, 0, 0)
            mock_net.return_value = (net_counters, "eth0")

            stats, _, _ = _read_system_stats(None, None, None, None)
            assert stats["tempCelsius"] == 0.0

    def test_fallback_temp_sensor(self):
        """Test fallback to first available sensor."""
        with patch("app.routes.monitor_routes.psutil") as mock_psutil, \
             patch("app.routes.monitor_routes.disk_usage") as mock_disk, \
             patch("app.routes.monitor_routes._pick_network_counters") as mock_net:

            mock_psutil.cpu_percent.return_value = 5.0
            mock_psutil.virtual_memory.return_value = MagicMock(percent=30.0)
            mock_psutil.sensors_temperatures.return_value = {
                "some_other_sensor": [MagicMock(current=55.0)]
            }
            mock_psutil.boot_time.return_value = time.time() - 100

            mock_disk.return_value = MagicMock(total=100 * 1024**3, used=50 * 1024**3)
            net_counters = NetCounters(0, 0, 0, 0, 0, 0, 0, 0)
            mock_net.return_value = (net_counters, "eth0")

            stats, _, _ = _read_system_stats(None, None, None, None)
            assert stats["tempCelsius"] == 55.0
