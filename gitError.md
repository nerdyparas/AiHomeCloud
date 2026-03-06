
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/asyncio/base_events.py:691: in run_until_complete
    return future.result()
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:317: in setup
    res = await gen_obj.__anext__()
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

tmp_path = PosixPath('/tmp/pytest-of-runner/pytest-0/test_eject_requires_admin_priv0')
monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x7f6cd260e930>

    @pytest.fixture
    async def client(tmp_path, monkeypatch):
        # Point the app data dir to a temporary path before FastAPI loads settings
        monkeypatch.setenv("CUBIE_DATA_DIR", str(tmp_path))
    
        from app.config import settings
        from app.main import app
    
        settings.data_dir = tmp_path
    
>       async with AsyncClient(app=app, base_url="http://test") as ac:
E       TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'

tests/conftest.py:25: TypeError
_________ ERROR at setup of test_storage_stats_does_not_require_admin __________

request = <SubRequest 'client' for <Coroutine test_storage_stats_does_not_require_admin>>
kwargs = {'monkeypatch': <_pytest.monkeypatch.MonkeyPatch object at 0x7f6cd258fd10>, 'tmp_path': PosixPath('/tmp/pytest-of-runner/pytest-0/test_storage_stats_does_not_re0')}
func = <function client at 0x7f6cd4dac540>
setup = <function _wrap_asyncgen_fixture.<locals>._asyncgen_fixture_wrapper.<locals>.setup at 0x7f6cd25c3600>
finalizer = <function _wrap_asyncgen_fixture.<locals>._asyncgen_fixture_wrapper.<locals>.finalizer at 0x7f6cd25c3420>

    @functools.wraps(fixture)
    def _asyncgen_fixture_wrapper(request: SubRequest, **kwargs: Any):
        func = _perhaps_rebind_fixture_func(
            fixture, request.instance, fixturedef.unittest
        )
        event_loop = kwargs.pop(event_loop_fixture_id)
        gen_obj = func(
            **_add_kwargs(func, kwargs, event_loop_fixture_id, event_loop, request)
        )
    
        async def setup():
            res = await gen_obj.__anext__()
            return res
    
        def finalizer() -> None:
            """Yield again, to finalize."""
    
            async def async_finalizer() -> None:
                try:
                    await gen_obj.__anext__()
                except StopAsyncIteration:
                    pass
                else:
                    msg = "Async generator fixture didn't stop."
                    msg += "Yield only once."
                    raise ValueError(msg)
    
            event_loop.run_until_complete(async_finalizer())
    
>       result = event_loop.run_until_complete(setup())

/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:335: 
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/asyncio/base_events.py:691: in run_until_complete
    return future.result()
/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/pytest_asyncio/plugin.py:317: in setup
    res = await gen_obj.__anext__()
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 

tmp_path = PosixPath('/tmp/pytest-of-runner/pytest-0/test_storage_stats_does_not_re0')
monkeypatch = <_pytest.monkeypatch.MonkeyPatch object at 0x7f6cd258fd10>

    @pytest.fixture
    async def client(tmp_path, monkeypatch):
        # Point the app data dir to a temporary path before FastAPI loads settings
        monkeypatch.setenv("CUBIE_DATA_DIR", str(tmp_path))
    
        from app.config import settings
        from app.main import app
    
        settings.data_dir = tmp_path
    
>       async with AsyncClient(app=app, base_url="http://test") as ac:
E       TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'

tests/conftest.py:25: TypeError
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
ERROR tests/test_auth.py::test_valid_login_returns_200_with_tokens - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_wrong_password_returns_401 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_nonexistent_user_returns_401 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_login_rate_limiting_429_on_rapid_calls - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_member_cannot_access_admin_endpoint_403 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_expired_jwt_returns_401 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_refresh_with_revoked_jti_returns_401 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_logout_then_refresh_returns_401 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_valid_refresh_token_returns_new_access_token - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_missing_authorization_header_returns_403 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_malformed_bearer_token_returns_403 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_admin_can_access_admin_endpoint - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_create_user_first_user_is_admin - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_second_user_is_not_admin - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_login_with_empty_pin_returns_401 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_change_pin_requires_auth - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_change_pin_with_wrong_old_pin_returns_403 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_change_pin_success - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_auth.py::test_change_pin_with_short_pin_returns_400 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_path_traversal_attack_returns_403 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_valid_subdirectory_path_returns_200 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_url_encoded_path_traversal_returns_403 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_path_exceeding_4096_characters_returns_400 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_file_listing_response_contains_no_entries_outside_nas_root - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_path_with_null_bytes_returns_403 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_path_with_symbolic_link_escape_attempt_returns_403 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_double_encoding_traversal_attempt_returns_403 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_empty_path_defaults_to_shared - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_root_path_access_blocked - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_etc_directory_access_blocked - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_path_safety.py::test_boot_directory_access_blocked - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_format_request_with_mismatched_confirm_device_returns_400 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_format_request_for_os_disk_returns_403 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_mount_returns_409_when_nas_has_open_file_handles - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_eject_on_unmounted_device_returns_graceful_error - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_format_nonexistent_device_returns_404 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_mount_nonexistent_device_returns_404 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_mount_unformatted_device_returns_400 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_format_mounted_device_returns_409 - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_format_returns_job_id - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_storage_devices_endpoint_returns_list - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_storage_stats_endpoint_returns_stats - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_format_requires_admin_privileges - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_mount_requires_admin_privileges - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_unmount_requires_admin_privileges - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_eject_requires_admin_privileges - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
ERROR tests/test_storage.py::test_storage_stats_does_not_require_admin - TypeError: AsyncClient.__init__() got an unexpected keyword argument 'app'
1 passed, 2 warnings, 47 errors in 2.89s
Error: Process completed with exit code 1.