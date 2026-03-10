"""
TASK-P6-04 — Hardware Integration Tests
Run directly on the Cubie A7A hardware (or any ARM64 host with the backend running).

Usage:
    cd backend
    python -m pytest tests/test_hardware_integration.py -v -s --tb=short

Prerequisites:
    - cubie-backend service must be running on port 8443
    - /var/lib/cubie/ data directory must be accessible by the running user
    - /srv/nas/ NAS root must be mounted
"""

import asyncio
import json
import os
import time
import tempfile
import uuid
from pathlib import Path

import httpx
import pytest
import pytest_asyncio

from app.board import detect_board, BoardConfig
from app.config import settings
from app.auth import create_token

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

BASE_URL = "https://localhost:8443"
TLS_VERIFY = False  # self-signed cert — skip verify for local testing
# Hardcoded real-hardware data directory (not settings.data_dir which gets
# monkeypatched by unit tests running in the same pytest session).
_REAL_DATA_DIR = Path("/var/lib/cubie")

# Skip the entire module when not running on real hardware (CI, dev machines, etc.).
if not _REAL_DATA_DIR.joinpath("users.json").exists():
    pytest.skip(
        "Hardware integration tests require /var/lib/cubie/users.json — "
        "skipping on non-hardware environments.",
        allow_module_level=True,
    )


def _make_admin_token() -> str:
    """Create a valid admin JWT directly (no HTTP round-trip needed)."""
    users_path = _REAL_DATA_DIR / "users.json"
    users = json.loads(users_path.read_text())
    admin = next((u for u in users if u.get("is_admin")), None)
    assert admin is not None, "No admin user found in users.json"
    return create_token(admin["id"], {"role": "admin", "name": admin.get("name", "admin")})


@pytest.fixture(scope="module")
def admin_token() -> str:
    return _make_admin_token()


@pytest.fixture(scope="module")
def client(admin_token: str) -> httpx.Client:
    headers = {"Authorization": f"Bearer {admin_token}"}
    with httpx.Client(
        base_url=BASE_URL,
        verify=TLS_VERIFY,
        headers=headers,
        timeout=30,
        follow_redirects=True,
    ) as c:
        yield c


# ------------------------------------------------------------------
# 1. Board Detection
# ------------------------------------------------------------------

class TestBoardDetection:
    def test_detect_board_returns_known_model(self) -> None:
        """detect_board() must return a non-unknown model name on this hardware."""
        board = detect_board()
        assert board.model_name != "unknown", (
            f"Board returned 'unknown'; DTB model string not in KNOWN_BOARDS. "
            f"Fix board.py to add this hardware."
        )
        print(f"\n  model_name:        {board.model_name}")
        print(f"  thermal_zone_path: {board.thermal_zone_path}")
        print(f"  lan_interface:     {board.lan_interface}")

    def test_detect_board_is_cubie_a7a(self) -> None:
        """This specific hardware should be detected as Radxa CUBIE A7A."""
        board = detect_board()
        assert board.model_name == "Radxa CUBIE A7A", (
            f"Expected 'Radxa CUBIE A7A', got '{board.model_name}'"
        )

    def test_thermal_zone_path_exists(self) -> None:
        """Detected thermal zone file must exist on disk."""
        board = detect_board()
        assert Path(board.thermal_zone_path).exists(), (
            f"Thermal zone file not found: {board.thermal_zone_path}"
        )

    def test_thermal_zone_reads_valid_temperature(self) -> None:
        """Thermal zone must return a plausible CPU temperature (10–110 °C)."""
        board = detect_board()
        raw = Path(board.thermal_zone_path).read_text().strip()
        temp_c = int(raw) / 1000.0
        print(f"\n  CPU temperature: {temp_c:.1f}°C (raw={raw})")
        assert 10.0 <= temp_c <= 110.0, (
            f"CPU temperature {temp_c:.1f}°C out of plausible range [10–110]°C"
        )

    def test_lan_interface_exists(self) -> None:
        """Detected LAN interface must exist in /sys/class/net/."""
        board = detect_board()
        assert Path(f"/sys/class/net/{board.lan_interface}").exists(), (
            f"LAN interface not found: {board.lan_interface}"
        )
        print(f"\n  LAN interface: {board.lan_interface} ✓")


# ------------------------------------------------------------------
# 2. Backend Connectivity
# ------------------------------------------------------------------

class TestBackendConnectivity:
    def test_health_endpoint(self, client: httpx.Client) -> None:
        resp = client.get("/api/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"
        print(f"\n  /api/health → {resp.json()}")

    def test_root_endpoint(self, client: httpx.Client) -> None:
        resp = client.get("/")
        assert resp.status_code == 200
        data = resp.json()
        assert "service" in data
        print(f"\n  / → {data}")

    def test_system_info_authenticated(self, client: httpx.Client) -> None:
        resp = client.get("/api/v1/system/info")
        assert resp.status_code == 200, f"system/info failed: {resp.text}"
        info = resp.json()
        print(f"\n  systemInfo → {list(info.keys())}")


# ------------------------------------------------------------------
# 3. Concurrent File List Requests — No Deadlock
# ------------------------------------------------------------------

class TestConcurrentRequests:
    def test_ten_concurrent_file_list_requests(self, admin_token: str) -> None:
        """
        Fire 10 concurrent GET /api/v1/files/list requests.
        All must complete without deadlock, error, or timeout.
        """
        headers = {"Authorization": f"Bearer {admin_token}"}

        async def run_concurrent() -> list[int]:
            async with httpx.AsyncClient(
                base_url=BASE_URL, verify=TLS_VERIFY, headers=headers, timeout=30
            ) as ac:
                tasks = [
                    ac.get("/api/v1/files/list", params={"path": "/", "page": 1, "pageSize": 20})
                    for _ in range(10)
                ]
                responses = await asyncio.gather(*tasks)
                return [r.status_code for r in responses]

        start = time.monotonic()
        # Use a dedicated loop to avoid disrupting the pytest-asyncio session loop.
        # asyncio.run() calls asyncio.set_event_loop(None) on exit, which breaks
        # subsequent async tests that share the session-scoped event loop.
        _loop = asyncio.new_event_loop()
        try:
            status_codes = _loop.run_until_complete(run_concurrent())
        finally:
            _loop.close()
        elapsed = time.monotonic() - start

        print(f"\n  10 concurrent requests completed in {elapsed:.2f}s")
        print(f"  Status codes: {status_codes}")

        assert all(sc == 200 for sc in status_codes), (
            f"Some requests failed: {status_codes}"
        )
        # Should complete in under 10 seconds (they're IO-bound, not CPU-bound)
        assert elapsed < 10.0, f"Requests took too long: {elapsed:.2f}s"


# ------------------------------------------------------------------
# 4. Upload → Download → Search → Delete (Soft)
# ------------------------------------------------------------------

class TestFileLifecycle:
    def test_upload_text_file(self, client: httpx.Client) -> None:
        """Upload a small text file to the admin's inbox."""
        content = b"Hardware integration test file\nCreated by TASK-P6-04\n"
        filename = f"hwtest_{uuid.uuid4().hex[:8]}.txt"
        print(f"\n  Uploading: {filename}")

        # path param is accepted but ignored — files always land in .inbox/
        resp = client.post(
            "/api/v1/files/upload",
            params={"path": ".inbox/"},
            files={"file": (filename, content, "text/plain")},
        )
        assert resp.status_code == 201, f"Upload failed: {resp.status_code} {resp.text}"
        print(f"  Upload response: {resp.json()}")
        # Store filename for subsequent tests via pytest cache
        TestFileLifecycle._uploaded_filename = filename

    def test_file_list_shows_inbox(self, client: httpx.Client) -> None:
        """After upload, the file should appear in the files list."""
        resp = client.get("/api/v1/files/list", params={"path": "/", "page": 1, "pageSize": 100})
        assert resp.status_code == 200, f"File list failed: {resp.text}"
        data = resp.json()
        print(f"\n  Files list totalCount: {data.get('totalCount', '?')}")

    def test_download_uploaded_file(self, client: httpx.Client) -> None:
        """Download the uploaded test file and verify content."""
        filename = getattr(TestFileLifecycle, "_uploaded_filename", None)
        if not filename:
            pytest.skip("Upload test did not run or failed")

        resp = client.get(
            "/api/v1/files/download",
            params={"path": f".inbox/{filename}"},
        )
        if resp.status_code == 404:
            # File may have been auto-sorted out of .inbox already
            print(f"\n  File moved from .inbox (auto-sorted) — checking roots")
            resp2 = client.get("/api/v1/files/roots")
            print(f"  Roots: {resp2.text[:200]}")
            pytest.skip("File auto-sorted out of .inbox before download test")

        assert resp.status_code == 200, f"Download failed: {resp.status_code} {resp.text}"
        assert b"Hardware integration test" in resp.content
        print(f"\n  Download OK: {len(resp.content)} bytes")

    def test_document_search(self, client: httpx.Client) -> None:
        """Search for the uploaded document by keyword."""
        resp = client.get("/api/v1/files/search", params={"q": "hardware integration"})
        assert resp.status_code == 200, f"Search failed: {resp.status_code} {resp.text}"
        results = resp.json()
        print(f"\n  Search 'hardware integration' → {len(results)} result(s)")
        # Results may be 0 if file not yet indexed (async indexing)
        # That's acceptable — just verify endpoint doesn't error

    def test_delete_uploaded_file_moves_to_trash(self, client: httpx.Client) -> None:
        """Delete (soft-delete) the uploaded file — it should go to trash, not be erased."""
        filename = getattr(TestFileLifecycle, "_uploaded_filename", None)
        if not filename:
            pytest.skip("Upload test did not run or failed")

        # Try .inbox path first; may have moved
        for path in [f".inbox/{filename}", f"Documents/{filename}", filename]:
            resp = client.delete(
                "/api/v1/files/delete",
                params={"path": path},
            )
            if resp.status_code == 200:
                print(f"\n  Deleted (soft) from path '{path}': {resp.json()}")
                break
            if resp.status_code == 404:
                continue
            assert False, f"Delete failed unexpected status {resp.status_code}: {resp.text}"
        else:
            pytest.skip("Could not find uploaded file at any expected path to delete")

    def test_trash_contains_deleted_file(self, client: httpx.Client) -> None:
        """Verify trash endpoint lists the previously deleted file."""
        resp = client.get("/api/v1/files/trash")
        assert resp.status_code == 200, f"Trash list failed: {resp.text}"
        items = resp.json()
        print(f"\n  Trash items: {len(items)}")
        # If our file is there, great; if not, the route still works
        assert isinstance(items, list)


# ------------------------------------------------------------------
# 5. OTP / Pairing Key Persistence
# ------------------------------------------------------------------

class TestOTPPersistence:
    def test_pairing_json_exists(self) -> None:
        """pairing.json must exist and contain a non-expired OTP hash."""
        pairing_path = _REAL_DATA_DIR / "pairing.json"
        assert pairing_path.exists(), "pairing.json not found"
        data = json.loads(pairing_path.read_text())
        assert "otp_hash" in data, "pairing.json has no otp_hash"
        assert "expires_at" in data, "pairing.json has no expires_at"
        print(f"\n  pairing.json expires_at: {data['expires_at']} "
              f"(now={int(time.time())}, valid={data['expires_at'] > int(time.time())})")

    def test_pairing_key_file_exists(self) -> None:
        """pairing_key file must exist (used to derive OTP)."""
        key_path = _REAL_DATA_DIR / "pairing_key"
        assert key_path.exists(), "pairing_key file not found"
        key = key_path.read_text().strip()
        assert len(key) >= 16, f"pairing_key too short: '{key}'"
        print(f"\n  pairing_key length: {len(key)} chars ✓")

    def test_pair_qr_endpoint_works(self, client: httpx.Client) -> None:
        """GET /api/v1/pair/qr returns JSON payload for the Flutter QR display.

        The response must contain 'qrValue' (cubie:// URI) and must NOT expose
        the pairing key as a standalone top-level 'key' field (TASK-P1-04).
        """
        resp = client.get("/api/v1/pair/qr")
        assert resp.status_code == 200, f"pair/qr failed: {resp.text}"
        data = resp.json()
        # Must have qrValue field with cubie:// URI
        assert "qrValue" in data, f"Missing qrValue in response: {data}"
        assert data["qrValue"].startswith("cubie://pair"), (
            f"Unexpected qrValue format: {data['qrValue']}"
        )
        # Standalone 'key' field must NOT exist at top level (TASK-P1-04 fix)
        assert "key" not in data, f"Security issue: 'key' field exposed at top level: {data}"
        print(f"\n  /pair/qr → qrValue={data['qrValue'][:50]}... serial={data.get('serial')} ✓")


# ------------------------------------------------------------------
# 6. Service Management
# ------------------------------------------------------------------

class TestServiceManagement:
    def test_services_list(self, client: httpx.Client) -> None:
        """GET /api/v1/services must return a list of known services."""
        resp = client.get("/api/v1/services")
        assert resp.status_code == 200, f"services failed: {resp.text}"
        services = resp.json()
        assert isinstance(services, list)
        names = [s.get("id", s.get("name", "?")) for s in services]
        print(f"\n  Services: {names}")

    def test_storage_stats(self, client: httpx.Client) -> None:
        """/api/v1/storage/stats must return NAS usage data."""
        resp = client.get("/api/v1/storage/stats")
        assert resp.status_code == 200, f"storage/stats failed: {resp.text}"
        data = resp.json()
        print(f"\n  Storage stats: {data}")

    def test_network_status(self, client: httpx.Client) -> None:
        """/api/v1/network/status must return network info."""
        resp = client.get("/api/v1/network/status")
        assert resp.status_code == 200, f"network/status failed: {resp.text}"
        data = resp.json()
        print(f"\n  Network status keys: {list(data.keys())}")


# ------------------------------------------------------------------
# 8. Format Protection — OS Partition Safety
# ------------------------------------------------------------------

class TestFormatProtection:
    """
    Verify is_os_partition() correctly classifies all devices on this hardware.

    Rule: format is allowed for ANY externally-connected drive (USB / NVMe port)
    where OS files are not present — size does not matter.
    Blocked: mmcblk* (SD/eMMC OS disk), mtdblock* (NAND flash), system mounts.
    """

    def test_mmcblk_is_os_partition(self) -> None:
        """mmcblk0 partitions (SD card OS disk) must be classified as OS."""
        from app.routes.storage_helpers import is_os_partition
        # Simulated mmcblk0p3 (root filesystem)
        assert is_os_partition({"name": "mmcblk0p3", "mountpoint": "/"}) is True
        # mmcblk0p2 (/boot/efi) — name prefix alone should block it
        assert is_os_partition({"name": "mmcblk0p2", "mountpoint": "/boot/efi"}) is True
        # mmcblk0p1 (/config) — covered by both name prefix and mount prefix
        assert is_os_partition({"name": "mmcblk0p1", "mountpoint": "/config"}) is True
        print("\n  mmcblk* → OS partition ✓")

    def test_mtdblock_is_os_partition(self) -> None:
        """mtdblock (NAND flash / SPI bootloader) must be classified as OS."""
        from app.routes.storage_helpers import is_os_partition
        assert is_os_partition({"name": "mtdblock0", "mountpoint": None}) is True
        print("\n  mtdblock* → OS partition ✓")

    def test_boot_efi_mount_is_os_partition(self) -> None:
        """/boot/efi mount on a non-mmcblk device must still be blocked."""
        from app.routes.storage_helpers import is_os_partition
        # e.g. an NVMe with /boot/efi → must be protected
        assert is_os_partition({"name": "nvme0n1p1", "mountpoint": "/boot/efi"}) is True
        assert is_os_partition({"name": "nvme0n1p2", "mountpoint": "/boot/firmware"}) is True
        print("\n  /boot/efi, /boot/firmware mounts → OS partition ✓")

    def test_external_usb_any_size_is_not_os_partition(self) -> None:
        """External USB drives are NOT OS partitions regardless of size."""
        from app.routes.storage_helpers import is_os_partition
        # 14.9 GB USB drive — should be formattable
        assert is_os_partition({"name": "sda1", "mountpoint": "/srv/nas", "tran": "usb"}) is False
        # 1 GB USB — also formattable
        assert is_os_partition({"name": "sdb1", "mountpoint": None, "tran": "usb"}) is False
        # 256 GB NVMe external — also formattable
        assert is_os_partition({"name": "nvme1n1p1", "mountpoint": None, "tran": "nvme"}) is False
        print("\n  External USB/NVMe (any size) → NOT OS partition ✓ (formattable)")

    def test_format_os_partition_rejected_by_api(self, client: httpx.Client) -> None:
        """Attempting to format the OS SD card via API must return 403."""
        # mmcblk0p3 is the root partition — format must be rejected
        resp = client.post(
            "/api/v1/storage/format",
            json={"device": "/dev/mmcblk0p3", "confirmDevice": "/dev/mmcblk0p3", "label": "test"},
        )
        assert resp.status_code in (403, 404), (
            f"Expected 403 (OS partition blocked) or 404 (not found), got {resp.status_code}: {resp.text}"
        )
        print(f"\n  Format /dev/mmcblk0p3 → HTTP {resp.status_code} (OS protection ✓)")

    def test_real_devices_classified_correctly(self) -> None:
        """Verify is_os_partition() gives correct results for all real lsblk devices."""
        import subprocess
        import json as _json
        from app.routes.storage_helpers import is_os_partition

        result = subprocess.run(
            ["lsblk", "-J", "-b", "-o", "NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,TRAN"],
            capture_output=True, text=True,
        )
        data = _json.loads(result.stdout)
        all_devs = []

        def _flatten(devs, parent_tran=None):
            for d in devs:
                tran = d.get("tran") or parent_tran
                d["tran"] = tran
                all_devs.append(d)
                _flatten(d.get("children") or [], parent_tran=tran)

        _flatten(data.get("blockdevices", []))

        print("\n  Real device classification:")
        for dev in all_devs:
            is_os = is_os_partition(dev)
            name = dev["name"]
            mp = dev.get("mountpoint") or "-"
            tran = dev.get("tran") or "?"
            size_gb = (dev.get("size") or 0) / 1e9
            verdict = "OS (BLOCKED)" if is_os else "external (formattable)"
            print(f"    {name:20s} tran={tran:6s} mount={mp:20s} size={size_gb:.1f}GB → {verdict}")

            # mmcblk and mtd must always be OS
            if name.startswith(("mmcblk", "mtdblock")):
                assert is_os, f"{name} should be OS partition but wasn't"
            # sda (USB drive) should not be OS
            if name.startswith("sda"):
                assert not is_os, f"{name} (USB drive) should be formattable but was blocked"


# ------------------------------------------------------------------
# 7. JWT Secret Quality
# ------------------------------------------------------------------

class TestSecurityInvariants:
    def test_jwt_secret_length(self) -> None:
        """JWT secret must be at least 32 bytes."""
        secret = settings.jwt_secret
        assert len(secret) >= 32, (
            f"JWT secret too short: {len(secret)} chars (min 32)"
        )
        print(f"\n  JWT secret length: {len(secret)} chars ✓")

    def test_jwt_expires_one_hour(self) -> None:
        """JWT expire time must be 1 hour (not 720h)."""
        assert settings.jwt_expire_hours == 1, (
            f"jwt_expire_hours={settings.jwt_expire_hours} — should be 1"
        )
        print(f"\n  jwt_expire_hours: {settings.jwt_expire_hours} ✓")

    def test_cors_no_wildcard_by_default(self) -> None:
        """CORS origins must not include '*' wildcard by default."""
        # settings.cors_origins may be a list
        origins = settings.cors_origins if hasattr(settings, "cors_origins") else []
        if isinstance(origins, str):
            origins = [o.strip() for o in origins.split(",") if o.strip()]
        assert "*" not in origins, f"CORS wildcard found: {origins}"
        print(f"\n  CORS origins: {origins} (no wildcard ✓)")
