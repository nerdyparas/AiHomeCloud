# Profile Edit Screen — Implement Full User Self-Management

## What to build

A new screen reachable from the More tab profile card. The user can:
- Rename their display name
- Change or remove their PIN
- Change their emoji/avatar icon
- Switch to a different profile
- Delete their own profile (with warning)

This screen edits the **currently logged-in user's own profile** only.
It is not an admin screen — every user sees it for themselves.

---

## Architecture rules — never break these

- `friendlyError(e)` is the only error surface shown to users
- `store.py` is the only JSON persistence layer — no direct file reads
- `settings.nas_root` / `settings.personal_path` — never hardcode paths
- `logger` not `print()` in backend code
- No technical terms in user-facing strings (no user IDs, no file paths)
- All colours from `AppColors` — no new hex literals inline
- JWT `sub` claim = user ID — use `user.get("sub")` in backend handlers

---

## Part A — Backend: new store functions

### File: `backend/app/store.py`

Add two new functions after `update_user_pin`:

```python
async def update_user_profile(
    user_id: str,
    *,
    name: str | None = None,
    icon_emoji: str | None = None,
) -> bool:
    """Update display name and/or icon_emoji for a user. Returns False if not found."""
    users = await get_users()
    for u in users:
        if u["id"] == user_id:
            if name is not None:
                u["name"] = name.strip()
            if icon_emoji is not None:
                u["icon_emoji"] = icon_emoji.strip()
            await save_users(users)
            _set_cached("users", None)  # invalidate cache
            return True
    return False


async def remove_pin(user_id: str) -> bool:
    """Remove PIN from a user (sets to None = no PIN required)."""
    users = await get_users()
    for u in users:
        if u["id"] == user_id:
            u["pin"] = None
            await save_users(users)
            _set_cached("users", None)
            return True
    return False
```

---

## Part B — Backend: new API endpoints

### File: `backend/app/routes/auth_routes.py`

Add three new endpoints. Place them after the existing `PUT /users/pin` endpoint.

#### B1 — GET /users/me — fetch own profile

```python
@router.get("/users/me")
async def get_my_profile(user: dict = Depends(get_current_user)):
    """Return the current user's own profile data."""
    user_id = user.get("sub", "")
    found = await store.find_user(user_id)
    if not found:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    return {
        "id": found["id"],
        "name": found["name"],
        "icon_emoji": found.get("icon_emoji", ""),
        "has_pin": bool(found.get("pin")),
        "is_admin": found.get("is_admin", False),
    }
```

#### B2 — PUT /users/me — update own profile (name + emoji)

Add the request model near the other request models:

```python
class UpdateProfileRequest(BaseModel):
    name: str | None = None
    icon_emoji: str | None = None
```

Add the endpoint:

```python
@router.put("/users/me", status_code=status.HTTP_204_NO_CONTENT)
async def update_my_profile(
    body: UpdateProfileRequest,
    user: dict = Depends(get_current_user),
):
    """Update current user's display name and/or emoji icon."""
    user_id = user.get("sub", "")

    if body.name is not None:
        name = body.name.strip()
        if not name:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, "Name cannot be empty"
            )
        # Prevent duplicate names (case-insensitive)
        existing = await store.get_users()
        for u in existing:
            if u["id"] != user_id and u["name"].lower() == name.lower():
                raise HTTPException(
                    status.HTTP_409_CONFLICT,
                    "That name is already taken by another profile"
                )

    updated = await store.update_user_profile(
        user_id,
        name=body.name,
        icon_emoji=body.icon_emoji,
    )
    if not updated:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
```

#### B3 — DELETE /users/me — delete own profile

```python
@router.delete("/users/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_my_profile(user: dict = Depends(get_current_user)):
    """
    Delete the current user's own profile and personal folder.
    Blocked if this user is the only remaining user, or the only admin.
    """
    import shutil as _shutil

    user_id = user.get("sub", "")
    found = await store.find_user(user_id)
    if not found:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")

    all_users = await store.get_users()

    # Block if last user
    if len(all_users) <= 1:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "Cannot delete the only profile on this device"
        )

    # Block if last admin
    if found.get("is_admin"):
        admins = [u for u in all_users if u.get("is_admin")]
        if len(admins) <= 1:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                "Cannot delete the only admin profile"
            )

    # Remove from users list
    removed = await store.remove_user(user_id)
    if not removed:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")

    # Delete personal folder (best-effort, non-blocking)
    safe_name = Path(found["name"]).name
    personal_dir = settings.personal_path / safe_name
    if personal_dir.exists() and personal_dir.is_dir():
        try:
            _shutil.rmtree(personal_dir)
            logger.info("Deleted personal folder for user %s", found["name"])
        except Exception as exc:
            logger.warning("Could not delete folder for %s: %s", found["name"], exc)
```

Add `from pathlib import Path` if not already imported at top.

#### B4 — DELETE PIN endpoint

```python
@router.delete("/users/pin", status_code=status.HTTP_204_NO_CONTENT)
async def remove_my_pin(user: dict = Depends(get_current_user)):
    """Remove the current user's PIN so no PIN is required to log in."""
    user_id = user.get("sub", "")
    removed = await store.remove_pin(user_id)
    if not removed:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
```

---

## Part C — Flutter: extend AuthSession with iconEmoji

### File: `lib/services/auth_session.dart`

Add `iconEmoji` field to `AuthSession`:

```dart
class AuthSession {
  final String host;
  final int port;
  final String token;
  final String? refreshToken;
  final String username;
  final bool isAdmin;
  final String iconEmoji;    // ← add this

  const AuthSession({
    required this.host,
    required this.port,
    required this.token,
    required this.refreshToken,
    required this.username,
    required this.isAdmin,
    this.iconEmoji = '',      // ← add this
  });
```

Update `copyWith` to include `iconEmoji`:
```dart
AuthSession copyWith({
  ...
  String? iconEmoji,
}) {
  return AuthSession(
    ...
    iconEmoji: iconEmoji ?? this.iconEmoji,
  );
}
```

Update `login()` to accept and save `iconEmoji`:
```dart
Future<void> login({
  ...
  String iconEmoji = '',
}) async {
  final next = AuthSession(
    ...
    iconEmoji: iconEmoji,
  );
  ...
  await _prefs.setString('icon_emoji', iconEmoji);
}
```

Update `restoreFromPrefs()` to load `iconEmoji`:
```dart
state = AuthSession(
  ...
  iconEmoji: _prefs.getString('icon_emoji') ?? '',
);
```

Add `updateProfile` method to `AuthSessionNotifier` for local state refresh:
```dart
Future<void> updateProfile({String? username, String? iconEmoji}) async {
  if (state == null) return;
  state = state!.copyWith(
    username: username ?? state!.username,
    iconEmoji: iconEmoji ?? state!.iconEmoji,
  );
  if (username != null) {
    await _prefs.setString(AppConstants.prefUserName, username);
  }
  if (iconEmoji != null) {
    await _prefs.setString('icon_emoji', iconEmoji);
  }
}
```

---

## Part D — Flutter: new API methods

### File: `lib/services/api/auth_api.dart`

Add these methods:

```dart
/// GET /api/v1/users/me
Future<Map<String, dynamic>> getMyProfile() async {
  final res = await _withAutoRefresh(
    () => _client
        .get(
          Uri.parse('$_baseUrl${AppConstants.apiVersion}/users/me'),
          headers: _headers,
        )
        .timeout(ApiService._timeout),
  );
  _check(res);
  return jsonDecode(res.body) as Map<String, dynamic>;
}

/// PUT /api/v1/users/me
Future<void> updateMyProfile({String? name, String? iconEmoji}) async {
  final res = await _withAutoRefresh(
    () => _client
        .put(
          Uri.parse('$_baseUrl${AppConstants.apiVersion}/users/me'),
          headers: _headers,
          body: jsonEncode({
            if (name != null) 'name': name,
            if (iconEmoji != null) 'icon_emoji': iconEmoji,
          }),
        )
        .timeout(ApiService._timeout),
  );
  _check(res);
}

/// DELETE /api/v1/users/me
Future<void> deleteMyProfile() async {
  final res = await _withAutoRefresh(
    () => _client
        .delete(
          Uri.parse('$_baseUrl${AppConstants.apiVersion}/users/me'),
          headers: _headers,
        )
        .timeout(ApiService._timeout),
  );
  _check(res);
}

/// DELETE /api/v1/users/pin — remove PIN entirely
Future<void> removePin() async {
  final res = await _withAutoRefresh(
    () => _client
        .delete(
          Uri.parse('$_baseUrl${AppConstants.apiVersion}/users/pin'),
          headers: _headers,
        )
        .timeout(ApiService._timeout),
  );
  _check(res);
}
```

---

## Part E — New screen: profile_edit_screen.dart

### New file: `lib/screens/main/profile_edit_screen.dart`

This is the complete screen. Build it as a `ConsumerStatefulWidget`.

#### State variables

```dart
late TextEditingController _nameCtrl;
String _selectedEmoji = '';
bool _saving = false;
bool _loadingProfile = true;
String? _error;
bool _hasPin = false;         // loaded from API
bool _isAdmin = false;
```

#### initState — load current profile from API

```dart
@override
void initState() {
  super.initState();
  _nameCtrl = TextEditingController();
  _loadProfile();
}

Future<void> _loadProfile() async {
  try {
    final profile = await ref.read(apiServiceProvider).getMyProfile();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = profile['name'] as String? ?? '';
      _selectedEmoji = profile['icon_emoji'] as String? ?? '';
      _hasPin = profile['has_pin'] as bool? ?? false;
      _isAdmin = profile['is_admin'] as bool? ?? false;
      _loadingProfile = false;
    });
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _error = friendlyError(e);
      _loadingProfile = false;
    });
  }
}
```

#### Layout

```dart
Scaffold(
  backgroundColor: AppColors.background,
  appBar: AppBar(
    backgroundColor: AppColors.background,
    elevation: 0,
    title: Text('Edit Profile',
        style: GoogleFonts.sora(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        )),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
      onPressed: () => context.pop(),
    ),
  ),
  body: _loadingProfile
      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
      : SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [

              // ── Avatar preview ──────────────────────────────────────────
              Center(
                child: Stack(
                  children: [
                    UserAvatar(
                      name: _nameCtrl.text.isNotEmpty
                          ? _nameCtrl.text
                          : '?',
                      iconEmoji: _selectedEmoji,
                      colorIndex: 0,
                      size: 88,
                    ),
                    // Small edit badge
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.background, width: 2),
                        ),
                        child: const Icon(Icons.edit_rounded,
                            color: Colors.white, size: 13),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Section: Name ───────────────────────────────────────────
              _sectionLabel('Display Name'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary, fontSize: 15),
                decoration: _inputDecoration('Your name'),
              ),

              const SizedBox(height: 24),

              // ── Section: Icon ────────────────────────────────────────────
              _sectionLabel('Icon'),
              const SizedBox(height: 12),
              EmojiPickerGrid(
                selectedEmoji: _selectedEmoji,
                onSelected: (e) => setState(() => _selectedEmoji = e),
              ),

              const SizedBox(height: 24),

              // ── Save name + emoji button ─────────────────────────────────
              if (_error != null) ...[
                Text(_error!,
                    style: GoogleFonts.dmSans(
                        color: AppColors.error, fontSize: 13)),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _saving ? null : _saveProfile,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text('Save Changes',
                          style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                ),
              ),

              const SizedBox(height: 32),
              _divider(),
              const SizedBox(height: 32),

              // ── Section: PIN ─────────────────────────────────────────────
              _sectionLabel('PIN'),
              const SizedBox(height: 12),

              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // Change PIN row
                    ListTile(
                      leading: _iconBox(Icons.lock_rounded,
                          AppColors.textSecondary),
                      title: Text(
                          _hasPin ? 'Change PIN' : 'Add PIN',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text(
                          _hasPin
                              ? 'Update your current PIN'
                              : 'Add a PIN to protect this profile',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textSecondary,
                              fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textMuted, size: 20),
                      onTap: _showChangePinDialog,
                    ),

                    // Remove PIN row — only if PIN exists
                    if (_hasPin) ...[
                      const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: AppColors.cardBorder),
                      ListTile(
                        leading: _iconBox(Icons.lock_open_rounded,
                            AppColors.error),
                        title: Text('Remove PIN',
                            style: GoogleFonts.dmSans(
                                color: AppColors.error,
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                        subtitle: Text('No PIN needed to access this profile',
                            style: GoogleFonts.dmSans(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                        onTap: _confirmRemovePin,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),
              _divider(),
              const SizedBox(height: 32),

              // ── Section: Account actions ─────────────────────────────────
              _sectionLabel('Account'),
              const SizedBox(height: 12),

              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [

                    // Switch Profile
                    ListTile(
                      leading: _iconBox(Icons.switch_account_rounded,
                          AppColors.primary),
                      title: Text('Switch Profile',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text('Go back to the profile picker',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textSecondary,
                              fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textMuted, size: 20),
                      onTap: _switchProfile,
                    ),

                    const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: AppColors.cardBorder),

                    // Delete Profile — always last, always red
                    ListTile(
                      leading:
                          _iconBox(Icons.person_remove_rounded, AppColors.error),
                      title: Text('Delete Profile',
                          style: GoogleFonts.dmSans(
                              color: AppColors.error,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text('Permanently remove this profile',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textSecondary,
                              fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textMuted, size: 20),
                      onTap: _confirmDeleteProfile,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
)
```

#### _saveProfile

```dart
Future<void> _saveProfile() async {
  final name = _nameCtrl.text.trim();
  if (name.isEmpty) {
    setState(() => _error = 'Name cannot be empty.');
    return;
  }

  setState(() { _saving = true; _error = null; });

  try {
    await ref.read(apiServiceProvider).updateMyProfile(
      name: name,
      iconEmoji: _selectedEmoji,
    );

    // Update local session so header/avatar updates immediately
    await ref.read(authSessionProvider.notifier).updateProfile(
      username: name,
      iconEmoji: _selectedEmoji,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated')),
    );
    context.pop();
  } catch (e) {
    if (mounted) {
      setState(() { _error = friendlyError(e); _saving = false; });
    }
  }
}
```

#### _showChangePinDialog

```dart
void _showChangePinDialog() {
  final oldCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(_hasPin ? 'Change PIN' : 'Add PIN',
          style: GoogleFonts.sora(color: AppColors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Only show current PIN field if user already has one
          if (_hasPin) ...[
            TextField(
              controller: oldCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.dmSans(color: AppColors.textPrimary),
              decoration: const InputDecoration(hintText: 'Current PIN'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: newCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.dmSans(color: AppColors.textPrimary),
            decoration: const InputDecoration(
                hintText: 'New PIN (4–8 digits)', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.dmSans(color: AppColors.textPrimary),
            decoration: const InputDecoration(
                hintText: 'Confirm new PIN', counterText: ''),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel',
              style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () async {
            final newPin = newCtrl.text.trim();
            final confirmPin = confirmCtrl.text.trim();

            if (newPin.length < 4) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN must be at least 4 digits')),
              );
              return;
            }
            if (newPin != confirmPin) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PINs do not match')),
              );
              return;
            }

            try {
              await ref.read(apiServiceProvider).changePin(
                _hasPin ? oldCtrl.text.trim() : null,
                newPin,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() => _hasPin = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_hasPin
                      ? 'PIN updated'
                      : 'PIN added')),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(friendlyError(e))),
                );
              }
            }
          },
          child: Text('Save',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}
```

#### _confirmRemovePin

```dart
void _confirmRemovePin() {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Remove PIN?',
          style: GoogleFonts.sora(color: AppColors.textPrimary)),
      content: Text(
        'Anyone on this device will be able to access your profile without a PIN.',
        style: GoogleFonts.dmSans(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel',
              style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () async {
            try {
              await ref.read(apiServiceProvider).removePin();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() => _hasPin = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN removed')),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(friendlyError(e))),
                );
              }
            }
          },
          child: Text('Remove PIN',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}
```

#### _switchProfile

```dart
void _switchProfile() {
  final session = ref.read(authSessionProvider);
  if (session == null) {
    context.go('/');
    return;
  }
  // Go to user picker — user can tap a different profile there
  context.go('/user-picker', extra: session.host);
}
```

#### _confirmDeleteProfile

```dart
void _confirmDeleteProfile() {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Delete Profile?',
          style: GoogleFonts.sora(color: AppColors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This will permanently delete your profile and all your personal files stored on this device.',
            style: GoogleFonts.dmSans(
                color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This cannot be undone.',
                    style: GoogleFonts.dmSans(
                        color: AppColors.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel',
              style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () async {
            Navigator.pop(ctx);
            await _deleteProfile();
          },
          child: Text('Delete Profile',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

Future<void> _deleteProfile() async {
  try {
    await ref.read(apiServiceProvider).deleteMyProfile();

    // Log out — profile is gone
    await ref.read(apiServiceProvider).logout();
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.clear();
    ref.read(isSetupDoneProvider.notifier).state = false;

    if (!mounted) return;
    // Go to user picker — other profiles may still exist
    final session = ref.read(authSessionProvider);
    final host = session?.host ?? '';
    await ref.read(authSessionProvider.notifier).logout();

    if (!mounted) return;
    if (host.isNotEmpty) {
      context.go('/user-picker', extra: host);
    } else {
      context.go('/');
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }
}
```

#### Helper methods

```dart
Widget _sectionLabel(String text) => Text(text,
    style: GoogleFonts.dmSans(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5));

Widget _divider() => const Divider(color: AppColors.cardBorder, height: 1);

Widget _iconBox(IconData icon, Color color) => Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 18),
    );

InputDecoration _inputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle:
          GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 14),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
```

Required imports at top of file:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/emoji_picker_grid.dart';
import '../../widgets/user_avatar.dart';
```

---

## Part F — Router: add /profile-edit route

### File: `lib/navigation/app_router.dart`

Add import:
```dart
import '../screens/main/profile_edit_screen.dart';
```

Add route inside the `ShellRoute` routes list (alongside dashboard, files, etc.):
```dart
GoRoute(
  path: '/profile-edit',
  builder: (_, __) => const ProfileEditScreen(),
),
```

Also add it to the `onOnboarding` check so authenticated users aren't
redirected away from it — actually `/profile-edit` is a main app route
inside the shell, so no redirect change is needed.

---

## Part G — Wire up navigation from More screen

### File: `lib/screens/main/more_screen.dart`

Find `_ProfileCard` — the top row (avatar + name + "Tap to switch profile").

The `onProfileTap` currently goes to `/user-picker`. Change it so tapping
the profile row goes to `/profile-edit` instead, and add a separate
"Switch Profile" action within the profile edit screen:

```dart
// In _MoreScreenState.build(), update the _ProfileCard call:
_ProfileCard(
  userName: userName,
  onChangePinTap: _changePin,
  onProfileTap: () => context.push('/profile-edit'),   // ← was /user-picker
),
```

Also update the subtitle in `_ProfileCard` from:
```dart
Text('Tap to switch profile', ...)
```
to:
```dart
Text('Edit name, icon and PIN', ...)
```

---

## Validation

```bash
# Backend
python3 -m py_compile backend/app/routes/auth_routes.py && echo OK
python3 -m py_compile backend/app/store.py && echo OK
pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py

# Flutter
flutter analyze lib/screens/main/profile_edit_screen.dart
flutter analyze lib/services/auth_session.dart
flutter analyze lib/navigation/app_router.dart
flutter build apk --debug
```

## Manual test checklist

**Opening the screen:**
- Tap profile card on More tab → Profile Edit screen opens ✅
- Screen loads with current name, emoji pre-selected, correct PIN state ✅
- Avatar preview shows current emoji (or first letter if no emoji set) ✅

**Editing name + emoji:**
- Type new name → avatar preview updates in real time ✅
- Tap different emoji → preview updates ✅
- Tap Save Changes → snackbar "Profile updated" → back to More tab ✅
- Name shown on More tab profile card is updated immediately ✅
- Saving empty name → error message shown, no API call ✅
- Saving a name already taken → "That name is already taken" error ✅

**PIN management:**
- User with PIN: sees "Change PIN" + "Remove PIN" ✅
- User without PIN: sees "Add PIN" only, no Remove PIN row ✅
- Change PIN: old PIN field shown, wrong old PIN → error ✅
- Add PIN: no old PIN field, confirm field matches ✅
- PINs don't match → snackbar error, dialog stays open ✅
- PIN < 4 digits → snackbar error ✅
- Remove PIN: warning dialog → confirm → PIN removed, row updates ✅

**Switch Profile:**
- Tap Switch Profile → user picker screen ✅
- Can select a different user and log in as them ✅

**Delete Profile:**
- Tap Delete Profile → warning dialog with amber warning box ✅
- Cancel → dialog closes, nothing happens ✅
- Confirm → profile deleted → navigates to user picker if other users exist ✅
- Only user: backend returns error → snackbar "Cannot delete the only profile" ✅
- Only admin: backend returns error → snackbar shown ✅
- After deletion: personal folder gone from SBC ✅
