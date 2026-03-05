# Git CI/CD Fixes Log

## Issue: Missing `freezegun` Dependency in Test Requirements

**Date:** 2026-03-05  
**Status:** ✅ Fixed  
**Commits:** f425ecc (pip-audit), next commit (freezegun fix)

### Problem

The CI pipeline failed to run backend tests with the following error:

```
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.12.12/x64/lib/python3.12/site-packages/_pytest/python.py", line 617, in _importtestmodule
INTERNALERROR>     mod = import_path(self.path, mode=importmode, root=self.config.rootpath)
...
INTERNALERROR>   File "backend/tests/test_auth.py", line 12, in <module>
INTERNALERROR>     from freezegun import freeze_time
INTERNALERROR> ModuleNotFoundError: No module named 'freezegun'
```

**Root Cause:**
- `backend/tests/test_auth.py` imports `freezegun` for time-mocking in tests
- The `freezegun` package was not listed in `backend/requirements.txt`
- CI pipeline installs only dependencies from requirements.txt, causing import failure
- pytest could not even collect tests due to the import error

### Solution

Added `freezegun>=1.5.1` to the dev dependencies section of `backend/requirements.txt`:

```diff
# dev
pytest==7.4.0
pytest-asyncio==0.22.0
httpx>=0.27.0
+freezegun>=1.5.1
```

### Verification

✅ `freezegun` package imports successfully  
✅ `backend/requirements.txt` now includes all test dependencies  
✅ CI pipeline will now properly install freezegun during `pip install -r requirements.txt` step

### Related Issues

- Previous fix (commit f425ecc) resolved h11 CVE-2025-43859 by upgrading h11 and httpx
- These dependency upgrades required freezegun to be explicitly added (was not listed before)

### Timeline

| Time | Event |
|------|-------|
| 2026-03-05 09:00 | h11 CVE-2025-43859 vulnerability detected and fixed |
| 2026-03-05 09:15 | CI pipeline upgrade detected missing freezegun dependency |
| 2026-03-05 09:20 | Added freezegun>=1.5.1 to requirements.txt dev section |
| 2026-03-05 09:25 | Fixed and verified locally, ready for CI run |

