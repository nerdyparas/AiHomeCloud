
        # Empty path or missing path query
        response = await client.get("/api/v1/files/list?path=")
        # Should either use default or return 400/422 for invalid input
>       assert response.status_code in (200, 400, 422), \
            f"Empty path should return 200 (with default), 400, or 422, got {response.status_code}"
E       AssertionError: Empty path should return 200 (with default), 400, or 422, got 401
E       assert 401 in (200, 400, 422)
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_path_safety.py:182: AssertionError
________________________ test_root_path_access_blocked _________________________

client = <httpx.AsyncClient object at 0x7f0c60fcd670>

    @pytest.mark.asyncio
    async def test_root_path_access_blocked(client: AsyncClient):
        """
        Verify that attempting to list / (filesystem root) is blocked.
        """
        response = await client.get("/api/v1/files/list?path=/")
>       assert response.status_code == 403, "Accessing / should return 403"
E       AssertionError: Accessing / should return 403
E       assert 401 == 403
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_path_safety.py:192: AssertionError
______________________ test_etc_directory_access_blocked _______________________

client = <httpx.AsyncClient object at 0x7f0c60fcee70>

    @pytest.mark.asyncio
    async def test_etc_directory_access_blocked(client: AsyncClient):
        """
        Verify that attempting to list /etc is blocked.
        """
        response = await client.get("/api/v1/files/list?path=/etc")
>       assert response.status_code == 403, "Accessing /etc should return 403"
E       AssertionError: Accessing /etc should return 403
E       assert 401 == 403
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_path_safety.py:201: AssertionError
______________________ test_boot_directory_access_blocked ______________________

client = <httpx.AsyncClient object at 0x7f0c60fc0110>

    @pytest.mark.asyncio
    async def test_boot_directory_access_blocked(client: AsyncClient):
        """
        Verify that attempting to list /boot is blocked.
        """
        response = await client.get("/api/v1/files/list?path=/boot")
>       assert response.status_code == 403, "Accessing /boot should return 403"
E       AssertionError: Accessing /boot should return 403
E       assert 401 == 403
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_path_safety.py:210: AssertionError
________ test_format_request_with_mismatched_confirm_device_returns_400 ________

client = <httpx.AsyncClient object at 0x7f0c60fc1c70>

    @pytest.mark.asyncio
    async def test_format_request_with_mismatched_confirm_device_returns_400(client: AsyncClient):
        """
        7D.2: Format request with confirmDevice != device → 400
    
        Verify that format requests require confirmDevice to match device
        (like GitHub's repo delete confirmation pattern).
        """
        response = await client.post(
            "/api/v1/storage/format",
            json={
                "device": "/dev/sda1",
                "label": "CubieNAS",
                "confirmDevice": "/dev/sdb1"  # Intentionally mismatched
            }
        )
>       assert response.status_code == 400, "Mismatched confirmDevice should return 400"
E       AssertionError: Mismatched confirmDevice should return 400
E       assert 401 == 400
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_storage.py:30: AssertionError
_________________ test_format_request_for_os_disk_returns_403 __________________

client = <httpx.AsyncClient object at 0x7f0c60fc2420>

    @pytest.mark.asyncio
    async def test_format_request_for_os_disk_returns_403(client: AsyncClient):
        """
        7D.3: Format request for OS disk /dev/mmcblk0 → 400 (protected)
    
        Verify that OS partitions (like microSD card) cannot be formatted.
        """
        response = await client.post(
            "/api/v1/storage/format",
            json={
                "device": "/dev/mmcblk0p1",
                "label": "CubieNAS",
                "confirmDevice": "/dev/mmcblk0p1"
            }
        )
        # Should return 403 (Forbidden) or 404 (not found) depending on whether the device exists
>       assert response.status_code in (403, 404), \
            f"OS partition format should be blocked, got {response.status_code}"
E       AssertionError: OS partition format should be blocked, got 401
E       assert 401 in (403, 404)
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_storage.py:50: AssertionError
____________ test_mount_returns_409_when_nas_has_open_file_handles _____________

client = <httpx.AsyncClient object at 0x7f0c60fe1af0>

    @pytest.mark.asyncio
    async def test_mount_returns_409_when_nas_has_open_file_handles(client: AsyncClient):
        """
        7D.4: Mount returns 409 when NAS has open file handles (mock lsof)
    
        Verify that attempting to mount a device when another device is already
        mounted returns a conflict (409) error.
        """
        # First, we'd need to mock the storage state to simulate an already-mounted device
        # For now, we verify the endpoint rejects when something is already mounted
    
        response = await client.post(
            "/api/v1/storage/mount",
            json={"device": "/dev/sda1"}
        )
    
        # The response depends on whether a device is already mounted in the test environment
        # If mount succeeds, it's because no device was previously mounted (200)
        # If it fails with 409, it's because a device is already mounted
        # Both are acceptable outcomes for this test
>       assert response.status_code in (200, 409), \
            f"Mount should return 200 or 409, got {response.status_code}"
E       AssertionError: Mount should return 200 or 409, got 401
E       assert 401 in (200, 409)
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_storage.py:77: AssertionError
____________ test_eject_on_unmounted_device_returns_graceful_error _____________

client = <httpx.AsyncClient object at 0x7f0c60fc2930>

    @pytest.mark.asyncio
    async def test_eject_on_unmounted_device_returns_graceful_error(client: AsyncClient):
        """
        7D.5: Eject on already-unmounted device returns graceful error, not 500
    
        Verify that ejecting a device that is not currently mounted
        returns a graceful error (not a 500 server error).
        """
        response = await client.post(
            "/api/v1/storage/eject",
            json={"device": "/dev/sda1"}
        )
    
        # Should return 200 (graceful, no-op) or 404 (not found), not 500
>       assert response.status_code in (200, 404), \
            f"Eject should return 200 or 404, got {response.status_code}"
E       AssertionError: Eject should return 200 or 404, got 401
E       assert 401 in (200, 404)
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_storage.py:98: AssertionError
__________________ test_format_nonexistent_device_returns_404 __________________

client = <httpx.AsyncClient object at 0x7f0c60fc0230>

    @pytest.mark.asyncio
    async def test_format_nonexistent_device_returns_404(client: AsyncClient):
        """
        Bonus: Format request for non-existent device returns 404.
        """
        response = await client.post(
            "/api/v1/storage/format",
            json={
                "device": "/dev/nonexistent999",
                "label": "CubieNAS",
                "confirmDevice": "/dev/nonexistent999"
            }
        )
>       assert response.status_code == 404, "Non-existent device should return 404"
E       AssertionError: Non-existent device should return 404
E       assert 401 == 404
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_storage.py:115: AssertionError
__________________ test_mount_nonexistent_device_returns_404 ___________________

client = <httpx.AsyncClient object at 0x7f0c60f8a7b0>

    @pytest.mark.asyncio
    async def test_mount_nonexistent_device_returns_404(client: AsyncClient):
        """
        Bonus: Mount request for non-existent device returns 404.
        """
        response = await client.post(
            "/api/v1/storage/mount",
            json={"device": "/dev/nonexistent999"}
        )
>       assert response.status_code == 404, "Non-existent device mount should return 404"
E       AssertionError: Non-existent device mount should return 404
E       assert 401 == 404
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_storage.py:128: AssertionError
__________________ test_mount_unformatted_device_returns_400 ___________________

client = <httpx.AsyncClient object at 0x7f0c60f88bc0>

    @pytest.mark.asyncio
    async def test_mount_unformatted_device_returns_400(client: AsyncClient):
        """
        Bonus: Mount request for device without filesystem returns 400.
    
        Verify that attempting to mount a device with no filesystem
        (e.g., raw device) fails gracefully.
        """
        # This would require a real device without a filesystem
        # The test may not apply in the test environment, so we skip if needed
        response = await client.post(
            "/api/v1/storage/mount",
            json={"device": "/dev/sda"}  # Raw device, not a partition
        )
    
        # Should return 400 (bad request) or 404 (not found), not 500
>       assert response.status_code in (400, 404, 409), \
            f"Mount of raw device should return 400/404/409, got {response.status_code}"
E       AssertionError: Mount of raw device should return 400/404/409, got 401
E       assert 401 in (400, 404, 409)
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_storage.py:148: AssertionError
____________________ test_format_mounted_device_returns_409 ____________________

client = <httpx.AsyncClient object at 0x7f0c60f3a450>

    @pytest.mark.asyncio
    async def test_format_mounted_device_returns_409(client: AsyncClient):
        """
        Bonus: Format request for currently mounted device returns 409.
        """
        # Get the currently mounted device (if any) from storage state
        response = await client.get("/api/v1/storage/devices")
>       assert response.status_code == 200
E       assert 401 == 200
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_storage.py:159: AssertionError
__________________________ test_format_returns_job_id __________________________

client = <httpx.AsyncClient object at 0x7f0c60f63a10>

    @pytest.mark.asyncio
    async def test_format_returns_job_id(client: AsyncClient):
        """
        Bonus: Format request returns a jobId for async tracking.
        """
        # Try to format a non-OS device (if one exists)
        response = await client.get("/api/v1/storage/devices")
>       assert response.status_code == 200
E       assert 401 == 200
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_storage.py:190: AssertionError
__________________ test_storage_devices_endpoint_returns_list __________________

client = <httpx.AsyncClient object at 0x7f0c60fe3590>

    @pytest.mark.asyncio
    async def test_storage_devices_endpoint_returns_list(client: AsyncClient):
        """
        Bonus: Verify that GET /api/v1/storage/devices returns a device list.
        """
        response = await client.get("/api/v1/storage/devices")
>       assert response.status_code == 200
E       assert 401 == 200
E        +  where 401 = <Response [401 Unauthorized]>.status_code

tests/test_storage.py:223: AssertionError
=============================== warnings summary ===============================
tests/test_auth.py::test_valid_login_returns_200_with_tokens
  /opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:687: DeprecationWarning: The event_loop fixture provided by pytest-asyncio has been redefined in
  /home/runner/work/AiHomeCloud/AiHomeCloud/backend/tests/conftest.py:8
  Replacing the event_loop fixture with a custom implementation is deprecated
  and will lead to errors in the future.
  If you want to request an asyncio event loop with a class or module scope,
  please attach the asyncio_event_loop mark to the respective class or module.
  
    warnings.warn(

tests/test_auth.py::test_valid_login_returns_200_with_tokens
  /opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/passlib/utils/__init__.py:854: DeprecationWarning: 'crypt' is deprecated and slated for removal in Python 3.13
    from crypt import crypt as _crypt

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
=========================== short test summary info ============================
FAILED tests/test_auth.py::test_member_cannot_access_admin_endpoint_403 - ValueError: password cannot be longer than 72 bytes, truncate manually if necessary (e.g. my_password[:72])
FAILED tests/test_auth.py::test_expired_jwt_returns_401 - ImportError: attempted relative import beyond top-level package
FAILED tests/test_auth.py::test_valid_refresh_token_returns_new_access_token - assert 401 == 200
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_auth.py::test_missing_authorization_header_returns_403 - AssertionError: Missing auth header should return 403
assert 308 == 403
 +  where 308 = <Response [308 Permanent Redirect]>.status_code
FAILED tests/test_auth.py::test_malformed_bearer_token_returns_403 - AssertionError: Malformed token should return 401
assert 308 == 401
 +  where 308 = <Response [308 Permanent Redirect]>.status_code
FAILED tests/test_auth.py::test_create_user_first_user_is_admin - NameError: name 'admin_token' is not defined
FAILED tests/test_auth.py::test_change_pin_requires_auth - AssertionError: Unauthenticated PIN change should return 403
assert 401 == 403
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_path_safety.py::test_path_traversal_attack_returns_403 - AssertionError: Path traversal should return 403
assert 401 == 403
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_path_safety.py::test_valid_subdirectory_path_returns_200 - AssertionError: Valid NAS path should return 200
assert 401 == 200
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_path_safety.py::test_url_encoded_path_traversal_returns_403 - AssertionError: URL-encoded path traversal should return 403
assert 401 == 403
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_path_safety.py::test_path_exceeding_4096_characters_returns_400 - AssertionError: Overly long path should return 400 or 403, got 401
assert 401 in (400, 403)
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_path_safety.py::test_file_listing_response_contains_no_entries_outside_nas_root - assert 401 == 200
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_path_safety.py::test_path_with_null_bytes_returns_403 - AssertionError: Path with null byte should be rejected, got 401
assert 401 in (400, 403)
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_path_safety.py::test_double_encoding_traversal_attempt_returns_403 - AssertionError: Double-encoded path should return 200 or 403, got 401
assert 401 in (200, 403)
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_path_safety.py::test_empty_path_defaults_to_shared - AssertionError: Empty path should return 200 (with default), 400, or 422, got 401
assert 401 in (200, 400, 422)
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_path_safety.py::test_root_path_access_blocked - AssertionError: Accessing / should return 403
assert 401 == 403
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_path_safety.py::test_etc_directory_access_blocked - AssertionError: Accessing /etc should return 403
assert 401 == 403
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_path_safety.py::test_boot_directory_access_blocked - AssertionError: Accessing /boot should return 403
assert 401 == 403
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_storage.py::test_format_request_with_mismatched_confirm_device_returns_400 - AssertionError: Mismatched confirmDevice should return 400
assert 401 == 400
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_storage.py::test_format_request_for_os_disk_returns_403 - AssertionError: OS partition format should be blocked, got 401
assert 401 in (403, 404)
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_storage.py::test_mount_returns_409_when_nas_has_open_file_handles - AssertionError: Mount should return 200 or 409, got 401
assert 401 in (200, 409)
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_storage.py::test_eject_on_unmounted_device_returns_graceful_error - AssertionError: Eject should return 200 or 404, got 401
assert 401 in (200, 404)
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_storage.py::test_format_nonexistent_device_returns_404 - AssertionError: Non-existent device should return 404
assert 401 == 404
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_storage.py::test_mount_nonexistent_device_returns_404 - AssertionError: Non-existent device mount should return 404
assert 401 == 404
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_storage.py::test_mount_unformatted_device_returns_400 - AssertionError: Mount of raw device should return 400/404/409, got 401
assert 401 in (400, 404, 409)
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_storage.py::test_format_mounted_device_returns_409 - assert 401 == 200
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_storage.py::test_format_returns_job_id - assert 401 == 200
 +  where 401 = <Response [401 Unauthorized]>.status_code
FAILED tests/test_storage.py::test_storage_devices_endpoint_returns_list - assert 401 == 200
 +  where 401 = <Response [401 Unauthorized]>.status_code
ERROR tests/test_auth.py::test_valid_login_returns_200_with_tokens - ValueError: password cannot be longer than 72 bytes, truncate manually if necessary (e.g. my_password[:72])
ERROR tests/test_auth.py::test_refresh_with_revoked_jti_returns_401 - ValueError: password cannot be longer than 72 bytes, truncate manually if necessary (e.g. my_password[:72])
ERROR tests/test_auth.py::test_logout_then_refresh_returns_401 - ValueError: password cannot be longer than 72 bytes, truncate manually if necessary (e.g. my_password[:72])
ERROR tests/test_auth.py::test_admin_can_access_admin_endpoint - ValueError: password cannot be longer than 72 bytes, truncate manually if necessary (e.g. my_password[:72])
ERROR tests/test_auth.py::test_second_user_is_not_admin - ValueError: password cannot be longer than 72 bytes, truncate manually if necessary (e.g. my_password[:72])
ERROR tests/test_auth.py::test_change_pin_with_wrong_old_pin_returns_403 - ValueError: password cannot be longer than 72 bytes, truncate manually if necessary (e.g. my_password[:72])
ERROR tests/test_auth.py::test_change_pin_success - ValueError: password cannot be longer than 72 bytes, truncate manually if necessary (e.g. my_password[:72])
ERROR tests/test_auth.py::test_change_pin_with_short_pin_returns_400 - ValueError: password cannot be longer than 72 bytes, truncate manually if necessary (e.g. my_password[:72])
ERROR tests/test_storage.py::test_storage_stats_endpoint_returns_stats - ValueError: password cannot be longer than 72 bytes, truncate manually if necessary (e.g. my_password[:72])
ERROR tests/test_storage.py::test_storage_stats_does_not_require_admin - ValueError: password cannot be longer than 72 bytes, truncate manually if necessary (e.g. my_password[:72])
28 failed, 10 passed, 2 warnings, 10 errors in 5.39s
Error: Process completed with exit code 1.
0s
