# Fix: Security & Access Control — Trash Prefs + Pairing Guard

> Agent task — one session, one commit.
> Priority: MEDIUM — these are correctness/security bugs, not crashes.

---

## Context

Audit on 2026-03-19 found two security gaps:

1. **Trash auto-delete prefs has no admin guard** (`file_routes.py`)
   `PUT /api/v1/files/trash/prefs` lets *any* authenticated user toggle the global 30-day auto-delete setting. This is a device-wide data retention policy and should be admin-only. A non-admin family member could enable auto-delete and cause permanent data loss for everyone.

2. **`_wipe_stale_nas_dirs` runs on every `pair/complete` call** (`auth_routes.py`)
   The function that wipes `personal/`, `family/`, `entertainment/` from the NAS is designed for first-time setup only, but there is no guard preventing it from running if `pair/complete` is called again on a device that already has users (e.g. re-pairing after a factory reset flow that the user didn't finish). This could silently delete existing data.

---

## Files to change

| File | Change |
|---|---|
| `backend/app/routes/file_routes.py` | Add `require_admin` to `set_trash_prefs` |
| `backend/app/routes/auth_routes.py` | Guard `_bg_wipe_stale_nas_dirs` with user-count check |

---

## Exact changes required

### 1. `file_routes.py` — admin guard on trash prefs

The `set_trash_prefs` endpoint currently uses `get_current_user`. Change it to `require_admin`:

```python
# BEFORE:
@router.put("/trash/prefs", status_code=status.HTTP_204_NO_CONTENT)
async def set_trash_prefs(body: _TrashPrefsBody, user: dict = Depends(get_current_user)):
    """Enable or disable the 30-day auto-delete for trash items."""
    await store.set_value("trash_auto_delete", body.autoDelete)

# AFTER:
@router.put("/trash/prefs", status_code=status.HTTP_204_NO_CONTENT)
async def set_trash_prefs(body: _TrashPrefsBody, user: dict = Depends(require_admin)):
    """Enable or disable the 30-day auto-delete for trash items. Admin only."""
    await store.set_value("trash_auto_delete", body.autoDelete)
```

Make sure `require_admin` is in the imports at the top of the file — it's imported in other route files already, just not file_routes. Check the existing imports:

```python
from ..auth import get_current_user  # already there — ADD require_admin
```

Change to:
```python
from ..auth import get_current_user, require_admin
```

The `GET /api/v1/files/trash/prefs` (reading prefs) stays as `get_current_user` — any user can see the policy.

---

### 2. `auth_routes.py` — guard NAS dir wipe with user-count check

In `pair_complete`, the call to `_bg_wipe_stale_nas_dirs()` must only fire when there are truly zero existing users (first-time setup):

```python
# BEFORE (in pair_complete, near end of function):
import asyncio
asyncio.create_task(_bg_wipe_stale_nas_dirs())

# AFTER:
existing_users = await store.get_users()
if not existing_users:
    import asyncio
    asyncio.create_task(_bg_wipe_stale_nas_dirs())
else:
    logger.debug(
        "pair_complete: skipping NAS dir wipe — %d user(s) already exist",
        len(existing_users),
    )
```

This ensures the wipe is truly a first-boot-only operation. The check is fast (users.json is cached by `store.get_users()`).

---

## Tests to write / update

### `backend/tests/test_file_routes.py`

Add two tests for the trash prefs endpoint:

```python
async def test_set_trash_prefs_requires_admin(client, member_token):
    """Non-admin users must not be able to change trash auto-delete setting."""
    res = await client.put(
        "/api/v1/files/trash/prefs",
        json={"autoDelete": True},
        headers={"Authorization": f"Bearer {member_token}"},
    )
    assert res.status_code == 403

async def test_set_trash_prefs_admin_succeeds(client, admin_token):
    """Admin users can change trash auto-delete setting."""
    res = await client.put(
        "/api/v1/files/trash/prefs",
        json={"autoDelete": True},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert res.status_code == 204
```

If `member_token` fixture doesn't exist in `conftest.py`, add it:

```python
@pytest_asyncio.fixture
async def member_token(tmp_data_dir):
    """JWT for a non-admin user."""
    from app.auth import create_token
    from app import store
    await store.add_user("Alice", pin=None, is_admin=False)
    users = await store.get_users()
    alice = users[-1]
    return create_token(subject=alice["id"])
```

### `backend/tests/test_auth.py`

Add a test that pair_complete does NOT wipe directories when users already exist:

```python
async def test_pair_complete_no_wipe_when_users_exist(client, tmp_data_dir, mocker):
    """pair/complete must not wipe NAS dirs if users already exist."""
    from app import store
    await store.add_user("Existing User", is_admin=True)

    wipe_mock = mocker.patch("app.routes.auth_routes._bg_wipe_stale_nas_dirs")
    # ... (set up valid OTP and call pair/complete as in existing tests)
    wipe_mock.assert_not_called()
```

---

## Validation

```bash
cd backend && python -m pytest tests/ -q
```

All existing and new tests must pass.

---

## Docs to update after completing

- `kb/api-contracts.md` — update `PUT /api/v1/files/trash/prefs` auth column from `any user` to `admin`
- `kb/changelog.md` — `2026-03-XX: Added admin guard to trash prefs; guarded NAS dir wipe in pair/complete`
