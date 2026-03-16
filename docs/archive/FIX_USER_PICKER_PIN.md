# Fix: User picker shows PIN entry only when account has a PIN set

## What is broken right now

`lib/screens/onboarding/pin_entry_screen.dart` auto-selects the first user
on load and immediately shows the PIN input field for everyone. This means:
- Users with no PIN are confused — there is nothing to type
- The `_submit()` guard `if (pin.isEmpty) return` silently blocks no-PIN users
- There is no way to proceed without typing something

## What the correct behaviour should be

1. Screen loads → show ONLY avatar circles with names, nothing selected
2. User taps an avatar → two paths based on whether that account has a PIN:
   - **Has PIN** → PIN input field slides in below the avatars, user types and submits
   - **No PIN** → skip PIN entirely, login immediately, go to dashboard
3. Tapping a different avatar while PIN field is visible → collapse field,
   evaluate the newly selected user the same way

---

## Architecture rules — do not break these

- `friendlyError(e)` is the only error shown to users — no raw exceptions
- No hardcoded paths or IPs
- `logger` not `print()` in backend code

---

## Part A — Backend: expose has_pin in the users/names endpoint

### File: `backend/app/routes/auth_routes.py`

Find the `list_user_names` endpoint:

```python
@router.get("/auth/users/names")
async def list_user_names():
    """Return just the user names (no auth required) so the login screen can show a picker."""
    users = await store.get_users()
    return {"names": [u["name"] for u in users]}
```

Replace it with:

```python
@router.get("/auth/users/names")
async def list_user_names():
    """
    Return user names and PIN status for the login picker.
    has_pin is True when the account has a PIN set, False when no PIN required.
    No auth required — this is public so the picker can show before login.
    The actual PIN hash is never returned.
    """
    users = await store.get_users()
    return {
        "users": [
            {
                "name": u["name"],
                "has_pin": bool(u.get("pin")),
            }
            for u in users
        ]
    }
```

---

## Part B — Flutter: update fetchUserNames to return has_pin

### File: `lib/services/api/auth_api.dart`

#### B1 — Add a model class at the top of the file (or in models/user_models.dart):

```dart
class UserPickerEntry {
  final String name;
  final bool hasPin;
  const UserPickerEntry({required this.name, required this.hasPin});
}
```

#### B2 — Replace fetchUserNames method:

Find:
```dart
Future<List<String>> fetchUserNames(String host) async {
  final base = 'https://$host:${AppConstants.apiPort}';
  final res = await _client
      .get(Uri.parse('$base${AppConstants.apiVersion}/auth/users/names'))
      .timeout(ApiService._timeout);
  _check(res);
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  return (data['names'] as List).cast<String>();
}
```

Replace with:

```dart
Future<List<UserPickerEntry>> fetchUserEntries(String host) async {
  final base = 'https://$host:${AppConstants.apiPort}';
  final res = await _client
      .get(Uri.parse('$base${AppConstants.apiVersion}/auth/users/names'))
      .timeout(ApiService._timeout);
  _check(res);
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final list = data['users'] as List<dynamic>;
  return list.map((e) => UserPickerEntry(
    name: e['name'] as String,
    hasPin: e['has_pin'] as bool? ?? false,
  )).toList();
}
```

---

## Part C — Flutter: rewrite PinEntryScreen UI and logic

### File: `lib/screens/onboarding/pin_entry_screen.dart`

### C1 — Update state variables

Remove `_userNames` and `_selectedUser`. Add:

```dart
List<UserPickerEntry> _users = [];
UserPickerEntry? _selectedUser;
bool _showPin = false;        // true after a user with PIN is tapped
bool _loggingIn = false;      // true while auto-login (no-PIN path) is running
```

Keep: `_pinController`, `_loading`, `_error`, `_loadingUsers`

### C2 — Update _fetchUsers

```dart
Future<void> _fetchUsers() async {
  setState(() { _loadingUsers = true; _error = null; });
  try {
    final entries = await ApiService.instance.fetchUserEntries(widget.deviceIp);
    if (!mounted) return;
    setState(() {
      _users = entries;
      _selectedUser = null;   // nothing selected on load
      _showPin = false;
      _loadingUsers = false;
    });
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _loadingUsers = false;
      _error = friendlyError(e);
    });
  }
}
```

### C3 — Add _onUserTapped

This is the core logic. Called when an avatar is tapped.

```dart
Future<void> _onUserTapped(UserPickerEntry user) async {
  // Tapping the already-selected user with PIN visible → do nothing
  if (_selectedUser?.name == user.name && _showPin) return;

  setState(() {
    _selectedUser = user;
    _pinController.clear();
    _error = null;
    _showPin = false;
  });

  if (user.hasPin) {
    // Show PIN entry field
    setState(() => _showPin = true);
  } else {
    // No PIN — login immediately
    setState(() => _loggingIn = true);
    try {
      final result = await ApiService.instance.loginWithPin(
        widget.deviceIp,
        user.name,
        '',    // empty string accepted by backend for no-PIN accounts
      );
      final accessToken = result['accessToken'] as String;
      final refreshToken = result['refreshToken'] as String?;
      final userData = result['user'] as Map<String, dynamic>;

      await ref.read(authSessionProvider.notifier).login(
        host: widget.deviceIp,
        port: AppConstants.apiPort,
        token: accessToken,
        refreshToken: refreshToken,
        username: userData['name'] as String? ?? user.name,
        isAdmin: userData['isAdmin'] as bool? ?? false,
      );
      if (!mounted) return;
      context.go('/dashboard');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loggingIn = false;
        _selectedUser = null;
      });
    }
  }
}
```

### C4 — Update _submit (PIN path only)

```dart
Future<void> _submit() async {
  final pin = _pinController.text.trim();
  if (pin.isEmpty || _selectedUser == null) return;

  setState(() { _loading = true; _error = null; });
  try {
    final result = await ApiService.instance.loginWithPin(
      widget.deviceIp,
      _selectedUser!.name,
      pin,
    );
    final accessToken = result['accessToken'] as String;
    final refreshToken = result['refreshToken'] as String?;
    final user = result['user'] as Map<String, dynamic>;

    await ref.read(authSessionProvider.notifier).login(
      host: widget.deviceIp,
      port: AppConstants.apiPort,
      token: accessToken,
      refreshToken: refreshToken,
      username: user['name'] as String? ?? _selectedUser!.name,
      isAdmin: user['isAdmin'] as bool? ?? false,
    );
    if (!mounted) return;
    context.go('/dashboard');
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _error = friendlyError(e);
      _loading = false;
    });
  }
}
```

### C5 — Rewrite _buildBody

Replace the entire `_buildBody()` method with:

```dart
Widget _buildBody() {
  if (_users.isEmpty && _error != null) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(_error!, style: GoogleFonts.dmSans(color: AppColors.error)),
      ),
    );
  }

  return Column(
    children: [
      const Spacer(),

      // Title
      Text(
        'Who\'s using\nAiHomeCloud?',
        textAlign: TextAlign.center,
        style: GoogleFonts.sora(
          color: AppColors.textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),

      const SizedBox(height: 40),

      // Avatar grid — names and icons only, nothing selected on load
      Wrap(
        spacing: 24,
        runSpacing: 24,
        alignment: WrapAlignment.center,
        children: [
          for (int i = 0; i < _users.length; i++)
            _AvatarTile(
              user: _users[i],
              color: _avatarColors[i % _avatarColors.length],
              isSelected: _selectedUser?.name == _users[i].name,
              isLoggingIn: _loggingIn &&
                  _selectedUser?.name == _users[i].name,
              onTap: _loggingIn ? null : () => _onUserTapped(_users[i]),
            ),
        ],
      ),

      // PIN section — slides in only for has_pin users
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: _showPin && _selectedUser != null
            ? Padding(
                padding: const EdgeInsets.fromLTRB(40, 32, 40, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PIN for ${_selectedUser!.name}',
                      style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 8,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: GoogleFonts.sora(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        letterSpacing: 8,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '••••',
                        hintStyle: GoogleFonts.sora(
                          color: AppColors.textMuted,
                          fontSize: 24,
                          letterSpacing: 8,
                        ),
                        filled: true,
                        fillColor: AppColors.card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.cardBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 2),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: GoogleFonts.dmSans(
                            color: AppColors.error, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                'Enter',
                                style: GoogleFonts.dmSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),

      const Spacer(),
    ],
  );
}
```

### C6 — Add _AvatarTile as a private widget at the bottom of the file

```dart
class _AvatarTile extends StatelessWidget {
  final UserPickerEntry user;
  final Color color;
  final bool isSelected;
  final bool isLoggingIn;   // show spinner on this tile while auto-login runs
  final VoidCallback? onTap;

  const _AvatarTile({
    required this.user,
    required this.color,
    required this.isSelected,
    required this.isLoggingIn,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: AppColors.primary, width: 3)
                  : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                      )
                    ]
                  : null,
            ),
            child: Center(
              child: isLoggingIn
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(
                      user.name[0].toUpperCase(),
                      style: GoogleFonts.sora(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            user.name,
            style: GoogleFonts.dmSans(
              color: isSelected
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
              fontSize: 13,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## Validation

```bash
# Backend
python3 -m py_compile backend/app/routes/auth_routes.py && echo "auth_routes OK"
pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py

# Flutter
flutter analyze lib/screens/onboarding/pin_entry_screen.dart
flutter analyze lib/services/api/auth_api.dart
flutter build apk --debug
```

## Manual test on device

**User with PIN:**
Tap avatar → PIN field slides in → type PIN → dashboard ✅

**User without PIN:**
Tap avatar → spinner shows on avatar → dashboard opens immediately, no PIN field ✅

**Tap different user while PIN field is open:**
PIN field collapses → evaluates new user → PIN or auto-login ✅

**Wrong PIN:**
Error message appears below PIN field, field stays open ✅
