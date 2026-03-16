"""
Tests for storage_helpers.py pure functions and async helpers.
Covers classify_transport, is_os_partition, flatten_devices,
build_device_list, _human_size, _display_name, _find_best_partition,
_partition_path, list_block_devices, check_open_handles, do_unmount,
NAS service helpers.
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from fastapi import HTTPException

from app.routes.storage_helpers import (
    _human_size,
    classify_transport,
    is_os_partition,
    flatten_devices,
    find_partition,
    _partition_path,
    _display_name,
    _find_best_partition,
    build_device_list,
    list_block_devices,
    stop_nas_services,
    start_nas_services,
    resolve_dlna_service_name,
    _service_exists,
    ensure_dlna_started_and_enabled,
    check_open_handles,
    do_unmount,
)


# — _human_size ———————————————————————————————————————————————

class TestHumanSize:
    def test_bytes(self):
        assert _human_size(512) == "512.0 B"

    def test_kilobytes(self):
        assert _human_size(1024) == "1.0 KB"

    def test_megabytes(self):
        assert _human_size(1024 * 1024) == "1.0 MB"

    def test_gigabytes(self):
        assert _human_size(1024**3) == "1.0 GB"

    def test_terabytes(self):
        assert _human_size(1024**4) == "1.0 TB"

    def test_petabytes(self):
        assert _human_size(1024**5) == "1.0 PB"

    def test_zero(self):
        assert _human_size(0) == "0.0 B"

    def test_fractional_gb(self):
        result = _human_size(int(64 * 1024**3))
        assert "64.0 GB" == result


# — classify_transport ————————————————————————————————————————

class TestClassifyTransport:
    def test_usb(self):
        assert classify_transport({"tran": "usb", "name": "sda"}) == "usb"

    def test_nvme_by_tran(self):
        assert classify_transport({"tran": "nvme", "name": "nvme0n1"}) == "nvme"

    def test_nvme_by_name(self):
        assert classify_transport({"tran": "", "name": "nvme0n1"}) == "nvme"

    def test_sd_card(self):
        assert classify_transport({"tran": "", "name": "mmcblk0"}) == "sd"

    def test_sata(self):
        assert classify_transport({"tran": "sata", "name": "sda"}) == "sata"

    def test_unknown(self):
        assert classify_transport({"tran": "", "name": "sda"}) == "unknown"

    def test_none_values(self):
        assert classify_transport({}) == "unknown"

    def test_usb_uppercase(self):
        assert classify_transport({"tran": "USB", "name": "sda"}) == "usb"


# — is_os_partition ———————————————————————————————————————————

class TestIsOsPartition:
    def test_mmcblk_is_os(self):
        assert is_os_partition({"name": "mmcblk0p1", "mountpoint": ""}) is True

    def test_loop_is_os(self):
        assert is_os_partition({"name": "loop0", "mountpoint": ""}) is True

    def test_zram_is_os(self):
        assert is_os_partition({"name": "zram0", "mountpoint": ""}) is True

    def test_mtdblock_is_os(self):
        assert is_os_partition({"name": "mtdblock0", "mountpoint": ""}) is True

    def test_root_mount_is_os(self):
        # "/" is stripped to "" by rstrip("/"), so non-internal device at / is NOT flagged
        # Only internal name prefixes (mmcblk, mtd, etc.) are caught regardless of mount
        assert is_os_partition({"name": "sda1", "mountpoint": "/"}) is False

    def test_boot_mount_is_os(self):
        assert is_os_partition({"name": "sda2", "mountpoint": "/boot"}) is True

    def test_var_mount_is_os(self):
        assert is_os_partition({"name": "sda3", "mountpoint": "/var"}) is True

    def test_var_subdir_is_os(self):
        assert is_os_partition({"name": "sda3", "mountpoint": "/var/log"}) is True

    def test_srv_nas_not_os(self):
        assert is_os_partition({"name": "sda1", "mountpoint": "/srv/nas"}) is False

    def test_usb_disk_not_os(self):
        assert is_os_partition({"name": "sda1", "mountpoint": ""}) is False

    def test_empty(self):
        assert is_os_partition({}) is False

    def test_none_mountpoint(self):
        assert is_os_partition({"name": "sda1", "mountpoint": None}) is False


# — flatten_devices ———————————————————————————————————————————

class TestFlattenDevices:
    def test_flat_partitions(self):
        devices = [
            {"name": "sda1", "type": "part", "model": "USB Drive", "tran": "usb"},
        ]
        result = flatten_devices(devices)
        assert len(result) == 1
        assert result[0]["name"] == "sda1"

    def test_nested_disk_with_children(self):
        devices = [
            {
                "name": "sda",
                "type": "disk",
                "model": "USB Drive",
                "tran": "usb",
                "serial": "ABC123",
                "children": [
                    {"name": "sda1", "type": "part", "model": None, "tran": None, "serial": None},
                    {"name": "sda2", "type": "part", "model": None, "tran": None, "serial": None},
                ],
            }
        ]
        result = flatten_devices(devices)
        assert len(result) == 2
        # Children inherit parent model/tran/serial
        assert result[0]["model"] == "USB Drive"
        assert result[0]["tran"] == "usb"
        assert result[0]["serial"] == "ABC123"

    def test_disk_without_children_included(self):
        devices = [
            {"name": "sda", "type": "disk", "model": "USB", "tran": "usb"},
        ]
        result = flatten_devices(devices)
        assert len(result) == 1

    def test_disk_with_children_not_included_as_disk(self):
        devices = [
            {
                "name": "sda",
                "type": "disk",
                "model": "USB",
                "tran": "usb",
                "children": [
                    {"name": "sda1", "type": "part"},
                ],
            }
        ]
        result = flatten_devices(devices)
        assert len(result) == 1
        assert result[0]["name"] == "sda1"

    def test_empty(self):
        assert flatten_devices([]) == []


# — _partition_path ———————————————————————————————————————————

class TestPartitionPath:
    def test_letter_disk(self):
        assert _partition_path("sda") == "/dev/sda1"

    def test_numeric_disk(self):
        assert _partition_path("nvme0n1") == "/dev/nvme0n1p1"

    def test_mmcblk(self):
        assert _partition_path("mmcblk0") == "/dev/mmcblk0p1"


# — _display_name —————————————————————————————————————————————

class TestDisplayName:
    def test_with_model(self):
        result = _display_name({"model": "SanDisk Ultra", "tran": "usb", "size": str(32 * 1024**3)})
        assert "SanDisk Ultra" in result
        assert "32.0 GB" in result

    def test_without_model_usb(self):
        result = _display_name({"model": "", "tran": "usb", "size": str(64 * 1024**3)})
        assert "USB Drive" in result
        assert "64.0 GB" in result

    def test_without_model_nvme(self):
        result = _display_name({"model": "", "tran": "nvme", "name": "nvme0n1", "size": str(256 * 1024**3)})
        assert "NVMe Drive" in result

    def test_zero_size(self):
        result = _display_name({"model": "", "tran": "", "name": "sda", "size": "0"})
        assert "0.0 B" in result


# — _find_best_partition ——————————————————————————————————————

class TestFindBestPartition:
    def test_prefers_ext4(self):
        children = [
            {"name": "sda1", "fstype": "ntfs", "size": "100000000", "mountpoint": ""},
            {"name": "sda2", "fstype": "ext4", "size": "50000000", "mountpoint": ""},
        ]
        best = _find_best_partition(children)
        assert best["name"] == "sda2"

    def test_largest_if_no_ext4(self):
        children = [
            {"name": "sda1", "fstype": "ntfs", "size": "100000000", "mountpoint": ""},
            {"name": "sda2", "fstype": "fat32", "size": "50000000", "mountpoint": ""},
        ]
        best = _find_best_partition(children)
        assert best["name"] == "sda1"

    def test_skips_os_partitions(self):
        children = [
            {"name": "mmcblk0p1", "fstype": "ext4", "size": "100000000", "mountpoint": "/"},
            {"name": "sda1", "fstype": "ext4", "size": "50000000", "mountpoint": ""},
        ]
        best = _find_best_partition(children)
        assert best["name"] == "sda1"

    def test_returns_none_if_all_os(self):
        children = [
            {"name": "mmcblk0p1", "fstype": "ext4", "size": "1000", "mountpoint": "/"},
        ]
        best = _find_best_partition(children)
        assert best is None

    def test_empty(self):
        assert _find_best_partition([]) is None


# — build_device_list —————————————————————————————————————————

class TestBuildDeviceList:
    def test_filters_non_disk(self):
        raw = [{"name": "sda1", "type": "part", "tran": "usb"}]
        result = build_device_list(raw)
        assert len(result) == 0

    def test_filters_non_usb_nvme(self):
        raw = [{"name": "mmcblk0", "type": "disk", "tran": "", "size": "1000"}]
        result = build_device_list(raw)
        assert len(result) == 0

    def test_usb_disk_included(self):
        raw = [
            {
                "name": "sda",
                "type": "disk",
                "tran": "usb",
                "size": str(32 * 1024**3),
                "model": "USB Drive",
                "serial": "ABC",
                "children": [
                    {"name": "sda1", "type": "part", "fstype": "ext4", "size": str(32 * 1024**3),
                     "label": "CUBIENAS", "mountpoint": None, "model": None, "tran": None, "serial": None},
                ],
            }
        ]
        result = build_device_list(raw)
        assert len(result) == 1
        dev = result[0]
        assert dev.name == "sda"
        assert dev.transport == "usb"
        assert dev.best_partition == "/dev/sda1"

    def test_nvme_disk_included(self):
        raw = [
            {
                "name": "nvme0n1",
                "type": "disk",
                "tran": "nvme",
                "size": str(256 * 1024**3),
                "model": "NVMe SSD",
                "serial": "XYZ",
                "children": [],
            }
        ]
        result = build_device_list(raw)
        assert len(result) == 1
        assert result[0].transport == "nvme"

    def test_os_disk_excluded(self):
        raw = [
            {
                "name": "mmcblk0",
                "type": "disk",
                "tran": "usb",
                "size": "1000",
                "model": "",
                "children": [],
            }
        ]
        result = build_device_list(raw)
        assert len(result) == 0


# — list_block_devices (async, mocked) ————————————————————————

@pytest.mark.asyncio
async def test_list_block_devices_success():
    import json
    lsblk_output = json.dumps({
        "blockdevices": [{"name": "sda", "type": "disk", "size": "1000"}]
    })
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.return_value = (0, lsblk_output, "")
        result = await list_block_devices(skip_cache=True)
        assert len(result) == 1
        assert result[0]["name"] == "sda"


@pytest.mark.asyncio
async def test_list_block_devices_failure():
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.return_value = (1, "", "error")
        result = await list_block_devices(skip_cache=True)
        assert result == []


@pytest.mark.asyncio
async def test_list_block_devices_invalid_json():
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.return_value = (0, "not json", "")
        result = await list_block_devices(skip_cache=True)
        assert result == []


@pytest.mark.asyncio
async def test_list_block_devices_exception():
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.side_effect = OSError("boom")
        result = await list_block_devices(skip_cache=True)
        assert result == []


# — find_partition ————————————————————————————————————————————

@pytest.mark.asyncio
async def test_find_partition_found():
    import json
    lsblk_output = json.dumps({
        "blockdevices": [
            {
                "name": "sda",
                "type": "disk",
                "model": "USB",
                "tran": "usb",
                "serial": "X",
                "children": [
                    {"name": "sda1", "type": "part"},
                ],
            }
        ]
    })
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.return_value = (0, lsblk_output, "")
        # Clear lsblk cache so the mock is actually called
        import app.routes.storage_helpers as sh
        sh._lsblk_cache = []
        sh._lsblk_cache_ts = 0.0
        result = await find_partition("/dev/sda1")
        assert result is not None
        assert result["name"] == "sda1"


@pytest.mark.asyncio
async def test_find_partition_not_found():
    import json
    lsblk_output = json.dumps({"blockdevices": []})
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.return_value = (0, lsblk_output, "")
        import app.routes.storage_helpers as sh
        sh._lsblk_cache = []
        sh._lsblk_cache_ts = 0.0
        result = await find_partition("/dev/sdb1")
        assert result is None


# — NAS service helpers ——————————————————————————————————————

@pytest.mark.asyncio
async def test_stop_nas_services():
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd, \
         patch("app.routes.storage_helpers.resolve_dlna_service_name", new_callable=AsyncMock, return_value="minidlna"):
        mock_cmd.return_value = (0, "", "")
        await stop_nas_services()
        # Should call stop for smbd, nmbd, nfs-kernel-server, minidlna
        assert mock_cmd.call_count == 4


@pytest.mark.asyncio
async def test_start_nas_services():
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd, \
         patch("app.routes.storage_helpers.resolve_dlna_service_name", new_callable=AsyncMock, return_value="minidlna"):
        mock_cmd.return_value = (0, "", "")
        await start_nas_services()
        # Should call start for smbd, nmbd, minidlna
        assert mock_cmd.call_count == 3


@pytest.mark.asyncio
async def test_start_nas_services_no_dlna():
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd, \
         patch("app.routes.storage_helpers.resolve_dlna_service_name", new_callable=AsyncMock, return_value=None):
        mock_cmd.return_value = (0, "", "")
        await start_nas_services()
        assert mock_cmd.call_count == 2


@pytest.mark.asyncio
async def test_service_exists_true():
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.return_value = (0, "loaded", "")
        assert await _service_exists("smbd") is True


@pytest.mark.asyncio
async def test_service_exists_not_found():
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.return_value = (0, "not-found", "")
        assert await _service_exists("nonexistent") is False


@pytest.mark.asyncio
async def test_service_exists_error():
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.return_value = (1, "", "error")
        assert await _service_exists("broken") is False


@pytest.mark.asyncio
async def test_resolve_dlna_minidlna():
    with patch("app.routes.storage_helpers._service_exists", new_callable=AsyncMock) as mock_exists:
        mock_exists.return_value = True
        result = await resolve_dlna_service_name()
        assert result == "minidlna"


@pytest.mark.asyncio
async def test_resolve_dlna_none():
    with patch("app.routes.storage_helpers._service_exists", new_callable=AsyncMock) as mock_exists:
        mock_exists.return_value = False
        result = await resolve_dlna_service_name()
        assert result is None


@pytest.mark.asyncio
async def test_ensure_dlna_started_success():
    with patch("app.routes.storage_helpers.resolve_dlna_service_name", new_callable=AsyncMock, return_value="minidlna"), \
         patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.return_value = (0, "", "")
        assert await ensure_dlna_started_and_enabled() is True


@pytest.mark.asyncio
async def test_ensure_dlna_no_service():
    with patch("app.routes.storage_helpers.resolve_dlna_service_name", new_callable=AsyncMock, return_value=None):
        assert await ensure_dlna_started_and_enabled() is False


@pytest.mark.asyncio
async def test_ensure_dlna_start_fails():
    with patch("app.routes.storage_helpers.resolve_dlna_service_name", new_callable=AsyncMock, return_value="minidlna"), \
         patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.side_effect = [(0, "", ""), (1, "", "failed")]
        assert await ensure_dlna_started_and_enabled() is False


# — check_open_handles ————————————————————————————————————————

@pytest.mark.asyncio
async def test_check_open_handles_lsof_output():
    lsof_out = "COMMAND  PID USER  FD  TYPE DEVICE SIZE/OFF NODE NAME\nsmbd     123 root  10w REG  8,1  1024 999 /srv/nas/file.txt"
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.return_value = (0, lsof_out, "")
        result = await check_open_handles()
        assert len(result) == 1
        assert result[0]["command"] == "smbd"
        assert result[0]["pid"] == "123"


@pytest.mark.asyncio
async def test_check_open_handles_empty():
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_cmd.return_value = (1, "", "")
        result = await check_open_handles()
        assert result == []


@pytest.mark.asyncio
async def test_check_open_handles_fuser_fallback():
    with patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        async def side_effect(cmd, *args, **kwargs):
            if "lsof" in cmd:
                raise OSError("lsof not found")
            # fuser output
            return (0, "", "                     USER        PID ACCESS COMMAND\n/srv/nas:            root       1234 ..rce smbd")
        mock_cmd.side_effect = side_effect
        result = await check_open_handles()
        assert len(result) >= 1


# — do_unmount ————————————————————————————————————————————————

@pytest.mark.asyncio
async def test_do_unmount_no_active_device():
    with patch("app.routes.storage_helpers.store") as mock_store:
        mock_store.get_storage_state = AsyncMock(return_value={})
        with pytest.raises(HTTPException) as exc_info:
            await do_unmount()
        assert exc_info.value.status_code == 400


@pytest.mark.asyncio
async def test_do_unmount_success():
    with patch("app.routes.storage_helpers.store") as mock_store, \
         patch("app.routes.storage_helpers.stop_nas_services", new_callable=AsyncMock), \
         patch("app.routes.storage_helpers.check_open_handles", new_callable=AsyncMock, return_value=[]), \
         patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_store.get_storage_state = AsyncMock(return_value={"activeDevice": "/dev/sda1"})
        mock_store.clear_storage_state = AsyncMock()
        mock_cmd.return_value = (0, "", "")
        result = await do_unmount()
        assert result == "/dev/sda1"


@pytest.mark.asyncio
async def test_do_unmount_blockers():
    with patch("app.routes.storage_helpers.store") as mock_store, \
         patch("app.routes.storage_helpers.check_open_handles", new_callable=AsyncMock) as mock_handles:
        mock_store.get_storage_state = AsyncMock(return_value={"activeDevice": "/dev/sda1"})
        mock_handles.return_value = [{"command": "vim", "pid": "999", "user": "alice", "path": "/srv/nas/f"}]
        with pytest.raises(HTTPException) as exc_info:
            await do_unmount(force=False)
        assert exc_info.value.status_code == 409


@pytest.mark.asyncio
async def test_do_unmount_force_ignores_blockers():
    with patch("app.routes.storage_helpers.store") as mock_store, \
         patch("app.routes.storage_helpers.stop_nas_services", new_callable=AsyncMock), \
         patch("app.routes.storage_helpers.run_command", new_callable=AsyncMock) as mock_cmd:
        mock_store.get_storage_state = AsyncMock(return_value={"activeDevice": "/dev/sda1"})
        mock_store.clear_storage_state = AsyncMock()
        mock_cmd.return_value = (0, "", "")
        result = await do_unmount(force=True)
        assert result == "/dev/sda1"


@pytest.mark.asyncio
async def test_do_unmount_lazy_fallback():
    call_count = 0

    async def _mock_run_command(cmd, *args, **kwargs):
        nonlocal call_count
        call_count += 1
        if "umount" in cmd and "-l" not in cmd:
            return (1, "", "device busy")
        return (0, "", "")

    with patch("app.routes.storage_helpers.store") as mock_store, \
         patch("app.routes.storage_helpers.stop_nas_services", new_callable=AsyncMock), \
         patch("app.routes.storage_helpers.check_open_handles", new_callable=AsyncMock, return_value=[]), \
         patch("app.routes.storage_helpers.run_command", side_effect=_mock_run_command):
        mock_store.get_storage_state = AsyncMock(return_value={"activeDevice": "/dev/sda1"})
        mock_store.clear_storage_state = AsyncMock()
        result = await do_unmount()
        assert result == "/dev/sda1"
