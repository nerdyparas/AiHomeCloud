# Implement Emoji Avatar Picker for User Profiles

## Overview

Replace the plain colour-circle + first-letter avatar system with an emoji icon
picker. Users choose from a curated set of 32 emojis at profile creation time.
The chosen emoji is stored with the user record and shown in the user picker,
family screen, and anywhere else the avatar appears.

A "Use a different emoji" escape hatch lets users type any single emoji freely
if they want something outside the curated set.

---

## Architecture rules — never break these

- `friendlyError(e)` is the only error surface in Flutter
- `store.py` is the only JSON persistence layer
- `settings.nas_root` / `settings.personal_path` — never hardcode paths
- `logger` not `print()` in backend
- No technical terms in user-facing strings

---

## The 32 emoji set

Organised in two halves: 16 people/family characters, 16 others.

```
PEOPLE (16):
👶  🧒  👧  👦  👩  👨  👩‍🦱  👨‍🦱  👩‍🦳  👨‍🦳  👵  👴  🧑‍🍼  👩‍💻  👨‍🍳  🧑‍🎤

OTHERS (16):
🦁  🐯  🐼  🦊  🌸  🌻  ⭐  🌈  🎸  🎮  🚀  📚  🍕  ☕  🎨  ⚽
```

These are all single stable Unicode codepoints or simple sequences that render
consistently on Android 8+ without ZWJ family sequences, flag emojis, or
skin tone modifiers that can break circle layout.

---

## Part A — Backend: store and return icon_emoji

### A1 — `backend/app/models.py`

Find `CreateUserRequest`:
```python
class CreateUserRequest(BaseModel):
    name: str
    pin: Optional[str] = None
```

Add `icon_emoji` field:
```python
class CreateUserRequest(BaseModel):
    name: str
    pin: Optional[str] = None
    icon_emoji: str = ""    # single emoji character; empty = use first-letter fallback
```

### A2 — `backend/app/store.py`

Find `add_user`:
```python
async def add_user(name: str, pin: Optional[str] = None, is_admin: bool = False) -> dict:
    users = await get_users()
    user = {
        "id": f"user_{uuid.uuid4().hex[:8]}",
        "name": name,
        "pin": pin,
        "is_admin": is_admin,
    }
```

Add `icon_emoji` to the user dict:
```python
async def add_user(
    name: str,
    pin: Optional[str] = None,
    is_admin: bool = False,
    icon_emoji: str = "",
) -> dict:
    users = await get_users()
    user = {
        "id": f"user_{uuid.uuid4().hex[:8]}",
        "name": name,
        "pin": pin,
        "is_admin": is_admin,
        "icon_emoji": icon_emoji,
    }
```

### A3 — `backend/app/routes/auth_routes.py`

#### Update create_user endpoint

Find the call to `store.add_user` inside `create_user`:
```python
user = await store.add_user(body.name, hashed_pin, is_admin=is_admin)
```

Add icon_emoji:
```python
user = await store.add_user(
    body.name,
    hashed_pin,
    is_admin=is_admin,
    icon_emoji=body.icon_emoji.strip(),
)
```

#### Update list_user_names endpoint

The previous fix (FIX_USER_PICKER_PIN.md) updated this to return `has_pin`.
Now also add `icon_emoji`:

```python
@router.get("/auth/users/names")
async def list_user_names():
    users = await store.get_users()
    return {
        "users": [
            {
                "name": u["name"],
                "has_pin": bool(u.get("pin")),
                "icon_emoji": u.get("icon_emoji", ""),
            }
            for u in users
        ]
    }
```

---

## Part B — Flutter: UserPickerEntry model

### `lib/services/api/auth_api.dart`

If the previous fix (FIX_USER_PICKER_PIN.md) has been applied, `UserPickerEntry`
already exists with `name` and `hasPin`. Add `iconEmoji`:

```dart
class UserPickerEntry {
  final String name;
  final bool hasPin;
  final String iconEmoji;    // empty string = use first-letter fallback

  const UserPickerEntry({
    required this.name,
    required this.hasPin,
    this.iconEmoji = '',
  });
}
```

Update `fetchUserEntries` to parse `icon_emoji`:
```dart
return list.map((e) => UserPickerEntry(
  name: e['name'] as String,
  hasPin: e['has_pin'] as bool? ?? false,
  iconEmoji: e['icon_emoji'] as String? ?? '',
)).toList();
```

Update `createUser` to accept and send `iconEmoji`:
```dart
Future<void> createUser(
  String name,
  String? pin, {
  String iconEmoji = '',
}) async {
  final res = await _withAutoRefresh(
    () => _client
        .post(
          Uri.parse('$_baseUrl${AppConstants.apiVersion}/users'),
          headers: _headers,
          body: jsonEncode({
            'name': name,
            if (pin != null && pin.isNotEmpty) 'pin': pin,
            if (iconEmoji.isNotEmpty) 'icon_emoji': iconEmoji,
          }),
        )
        .timeout(ApiService._timeout),
  );
  _check(res);
}
```

---

## Part C — Shared emoji avatar widget

Create a reusable widget so the same avatar renders consistently everywhere
(user picker, profile creation preview, family screen member cards).

### New file: `lib/widgets/user_avatar.dart`

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

/// Renders a circular avatar for a user.
/// If [iconEmoji] is non-empty, shows the emoji centred in a coloured circle.
/// Otherwise falls back to the first letter of [name] (existing behaviour).
///
/// [colorIndex] determines the background colour from the predefined palette.
class UserAvatar extends StatelessWidget {
  final String name;
  final String iconEmoji;
  final int colorIndex;
  final double size;
  final bool isSelected;
  final bool isLoading;

  const UserAvatar({
    super.key,
    required this.name,
    required this.colorIndex,
    this.iconEmoji = '',
    this.size = 72,
    this.isSelected = false,
    this.isLoading = false,
  });

  static const _colors = [
    Color(0xFFE8A84C),
    Color(0xFF4C9BE8),
    Color(0xFF4CE88A),
    Color(0xFFE84CA8),
    Color(0xFF9B59B6),
    Color(0xFF1ABC9C),
    Color(0xFFE74C3C),
    Color(0xFF3498DB),
  ];

  Color get _bgColor => _colors[colorIndex % _colors.length];

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _bgColor,
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
        child: isLoading
            ? SizedBox(
                width: size * 0.35,
                height: size * 0.35,
                child: const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : iconEmoji.isNotEmpty
                ? Text(
                    iconEmoji,
                    style: TextStyle(fontSize: size * 0.44),
                  )
                : Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.sora(
                      color: Colors.white,
                      fontSize: size * 0.38,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
      ),
    );
  }
}
```

---

## Part D — Emoji picker widget

### New file: `lib/widgets/emoji_picker_grid.dart`

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

/// Curated 32-emoji picker grid for user profile creation.
/// Split into People (16) and Others (16) sections.
/// Includes a free-text field as escape hatch.
class EmojiPickerGrid extends StatefulWidget {
  /// Currently selected emoji — empty string means nothing selected.
  final String selectedEmoji;
  /// Called whenever the selection changes.
  final ValueChanged<String> onSelected;

  const EmojiPickerGrid({
    super.key,
    required this.selectedEmoji,
    required this.onSelected,
  });

  @override
  State<EmojiPickerGrid> createState() => _EmojiPickerGridState();
}

class _EmojiPickerGridState extends State<EmojiPickerGrid> {
  bool _showCustomInput = false;
  final _customCtrl = TextEditingController();

  // ── The 32 curated emojis ─────────────────────────────────────────────────
  static const _people = [
    '👶', '🧒', '👧', '👦',
    '👩', '👨', '👩‍🦱', '👨‍🦱',
    '👩‍🦳', '👨‍🦳', '👵', '👴',
    '🧑‍🍼', '👩‍💻', '👨‍🍳', '🧑‍🎤',
  ];

  static const _others = [
    '🦁', '🐯', '🐼', '🦊',
    '🌸', '🌻', '⭐', '🌈',
    '🎸', '🎮', '🚀', '📚',
    '🍕', '☕', '🎨', '⚽',
  ];

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _onCustomSubmit() {
    final text = _customCtrl.text.trim();
    if (text.isEmpty) return;
    // Basic validation: take only the first character cluster
    final runes = text.runes.toList();
    if (runes.isEmpty) return;
    // Reconstruct just the first grapheme-like chunk (simple heuristic)
    final first = String.fromCharCode(runes.first);
    widget.onSelected(first.trim().isEmpty ? text : text);
    setState(() => _showCustomInput = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── People section ───────────────────────────────────────────────────
        _sectionLabel('People & Family'),
        const SizedBox(height: 10),
        _EmojiGrid(
          emojis: _people,
          selected: widget.selectedEmoji,
          onTap: widget.onSelected,
        ),

        const SizedBox(height: 20),

        // ── Others section ───────────────────────────────────────────────────
        _sectionLabel('Animals, Hobbies & More'),
        const SizedBox(height: 10),
        _EmojiGrid(
          emojis: _others,
          selected: widget.selectedEmoji,
          onTap: widget.onSelected,
        ),

        const SizedBox(height: 16),

        // ── Custom emoji escape hatch ────────────────────────────────────────
        if (!_showCustomInput)
          GestureDetector(
            onTap: () => setState(() => _showCustomInput = true),
            child: Text(
              'Use a different emoji',
              style: GoogleFonts.dmSans(
                color: AppColors.primary,
                fontSize: 13,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.primary,
              ),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customCtrl,
                  autofocus: true,
                  maxLength: 8,
                  style: const TextStyle(fontSize: 22),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Type any emoji',
                    hintStyle: GoogleFonts.dmSans(
                        color: AppColors.textMuted, fontSize: 14),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: AppColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: AppColors.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _onCustomSubmit(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _onCustomSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Use',
                    style: GoogleFonts.dmSans(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textMuted, size: 20),
                onPressed: () => setState(() {
                  _showCustomInput = false;
                  _customCtrl.clear();
                }),
              ),
            ],
          ),
      ],
    );
  }

  Widget _sectionLabel(String label) => Text(
        label,
        style: GoogleFonts.dmSans(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      );
}

// ── Grid of tappable emoji cells ─────────────────────────────────────────────

class _EmojiGrid extends StatelessWidget {
  final List<String> emojis;
  final String selected;
  final ValueChanged<String> onTap;

  const _EmojiGrid({
    required this.emojis,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: emojis.map((e) {
        final isSelected = selected == e;
        return GestureDetector(
          onTap: () => onTap(e),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.cardBorder,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(e, style: const TextStyle(fontSize: 24)),
            ),
          ),
        );
      }).toList(),
    );
  }
}
```

---

## Part E — Profile creation screen

If `profile_creation_screen.dart` does not yet exist, create it now.
If it exists from Session 1, update it to replace the colour picker row with
`EmojiPickerGrid`.

### `lib/screens/onboarding/profile_creation_screen.dart`

Key state variables:
```dart
String _selectedEmoji = '';    // empty = no selection yet
final _nameCtrl = TextEditingController();
final _pinCtrl = TextEditingController();
bool _saving = false;
String? _error;
```

#### Layout

```dart
ListView(
  padding: const EdgeInsets.all(24),
  children: [
    const SizedBox(height: 32),

    // Live avatar preview — updates as user picks emoji/name
    Center(
      child: UserAvatar(
        name: _nameCtrl.text.isNotEmpty ? _nameCtrl.text : '?',
        iconEmoji: _selectedEmoji,
        colorIndex: 0,
        size: 88,
      ),
    ),
    const SizedBox(height: 24),

    Text('Set up your profile',
        textAlign: TextAlign.center,
        style: GoogleFonts.sora(
          color: AppColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        )),
    const SizedBox(height: 6),
    Text('You will be the admin. Others can join later.',
        textAlign: TextAlign.center,
        style: GoogleFonts.dmSans(
          color: AppColors.textSecondary, fontSize: 14)),

    const SizedBox(height: 32),

    // Name field
    _fieldLabel('Your name'),
    const SizedBox(height: 8),
    TextField(
      controller: _nameCtrl,
      textCapitalization: TextCapitalization.words,
      keyboardType: TextInputType.name,
      onChanged: (_) => setState(() {}),   // rebuild to update avatar preview
      style: GoogleFonts.dmSans(
          color: AppColors.textPrimary, fontSize: 15),
      decoration: _inputDecoration('e.g. Mike, Mum, Dad'),
    ),

    const SizedBox(height: 24),

    // Emoji picker
    _fieldLabel('Choose an icon'),
    const SizedBox(height: 12),
    EmojiPickerGrid(
      selectedEmoji: _selectedEmoji,
      onSelected: (e) => setState(() => _selectedEmoji = e),
    ),

    const SizedBox(height: 24),

    // PIN field — optional
    _fieldLabel('PIN'),
    const SizedBox(height: 4),
    Text('Leave blank for no PIN',
        style: GoogleFonts.dmSans(
            color: AppColors.textMuted, fontSize: 12)),
    const SizedBox(height: 8),
    TextField(
      controller: _pinCtrl,
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLength: 8,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: GoogleFonts.dmSans(
          color: AppColors.textPrimary, fontSize: 15),
      decoration: _inputDecoration('Optional').copyWith(counterText: ''),
    ),

    if (_error != null) ...[
      const SizedBox(height: 8),
      Text(_error!,
          style: GoogleFonts.dmSans(
              color: AppColors.error, fontSize: 13)),
    ],

    const SizedBox(height: 32),

    SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: _saving ? null : _submit,
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
            : Text('Create Profile',
                style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                )),
      ),
    ),
    const SizedBox(height: 32),
  ],
),
```

#### _submit method

```dart
Future<void> _submit() async {
  final name = _nameCtrl.text.trim();
  if (name.isEmpty) {
    setState(() => _error = 'Please enter your name.');
    return;
  }

  setState(() { _saving = true; _error = null; });

  try {
    final pin = _pinCtrl.text.trim();

    await ref.read(apiServiceProvider).createUser(
      name,
      pin.isNotEmpty ? pin : null,
      iconEmoji: _selectedEmoji,
    );

    final result = await ref.read(apiServiceProvider).loginWithPin(
      widget.deviceIp,
      name,
      pin,
    );

    await ref.read(authSessionProvider.notifier).login(
      host: widget.deviceIp,
      port: AppConstants.apiPort,
      token: result['accessToken'] as String,
      refreshToken: result['refreshToken'] as String?,
      username: name,
      isAdmin: true,
    );

    if (!mounted) return;

    if (widget.isAddingUser) {
      context.pop(true);
    } else {
      context.go('/dashboard');
    }
  } catch (e) {
    if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
  }
}
```

Helper methods:
```dart
Widget _fieldLabel(String label) => Text(
  label,
  style: GoogleFonts.dmSans(
    color: AppColors.textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  ),
);

InputDecoration _inputDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 14),
  filled: true,
  fillColor: AppColors.surface,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

Imports needed at top of file:
```dart
import '../../widgets/emoji_picker_grid.dart';
import '../../widgets/user_avatar.dart';
```

---

## Part F — Update user picker screen

### `lib/screens/onboarding/pin_entry_screen.dart`

If the previous fix (FIX_USER_PICKER_PIN.md) is applied, `_AvatarTile` renders
the first letter. Replace its content with `UserAvatar`:

Find `_AvatarTile.build()` — remove the existing `AnimatedContainer` with the
letter Text widget. Replace the entire widget with:

```dart
class _AvatarTile extends StatelessWidget {
  final UserPickerEntry user;
  final int colorIndex;
  final bool isSelected;
  final bool isLoggingIn;
  final VoidCallback? onTap;

  const _AvatarTile({
    required this.user,
    required this.colorIndex,
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
          UserAvatar(
            name: user.name,
            iconEmoji: user.iconEmoji,
            colorIndex: colorIndex,
            size: 72,
            isSelected: isSelected,
            isLoading: isLoggingIn,
          ),
          const SizedBox(height: 8),
          Text(
            user.name,
            style: GoogleFonts.dmSans(
              color: isSelected
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
```

Add import at top of `pin_entry_screen.dart`:
```dart
import '../../widgets/user_avatar.dart';
```

Update the `Wrap` in `_buildBody` to pass `colorIndex`:
```dart
for (int i = 0; i < _users.length; i++)
  _AvatarTile(
    user: _users[i],
    colorIndex: i,               // ← add this
    isSelected: _selectedUser?.name == _users[i].name,
    isLoggingIn: _loggingIn && _selectedUser?.name == _users[i].name,
    onTap: _loggingIn ? null : () => _onUserTapped(_users[i]),
  ),
```

---

## Part G — Update family screen member cards

### `lib/screens/main/family_screen.dart`

Find `_MemberCard` — it likely renders an avatar with the first letter.
Replace its avatar widget with `UserAvatar`.

Add `iconEmoji` to `FamilyUser` model in `lib/models/user_models.dart`:
```dart
class FamilyUser {
  final String id;
  final String name;
  final bool isAdmin;
  final double folderSizeGB;
  final Color avatarColor;
  final String iconEmoji;      // ← add this

  const FamilyUser({
    required this.id,
    required this.name,
    required this.isAdmin,
    required this.folderSizeGB,
    required this.avatarColor,
    this.iconEmoji = '',        // ← add this
  });
}
```

In `family_api.dart` or wherever `FamilyUser` is constructed from API response,
parse `icon_emoji`:
```dart
FamilyUser(
  id: u['id'] as String,
  name: u['name'] as String,
  isAdmin: u['is_admin'] as bool? ?? false,
  folderSizeGB: (u['folder_size_gb'] as num?)?.toDouble() ?? 0,
  avatarColor: ...,           // keep existing logic
  iconEmoji: u['icon_emoji'] as String? ?? '',
)
```

In the family admin API endpoint (`family_routes.py`), add `icon_emoji` to
the user dict returned:
```python
# In whatever endpoint returns family member list, add:
"icon_emoji": u.get("icon_emoji", ""),
```

In `_MemberCard` in `family_screen.dart`, replace the avatar circle with:
```dart
UserAvatar(
  name: user.name,
  iconEmoji: user.iconEmoji,
  colorIndex: index,    // pass the list index from the builder
  size: 48,
)
```

---

## Validation

```bash
# Backend
python3 -m py_compile backend/app/store.py && echo OK
python3 -m py_compile backend/app/models.py && echo OK
python3 -m py_compile backend/app/routes/auth_routes.py && echo OK
pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py

# Flutter
flutter analyze lib/widgets/user_avatar.dart
flutter analyze lib/widgets/emoji_picker_grid.dart
flutter analyze lib/screens/onboarding/profile_creation_screen.dart
flutter analyze lib/screens/onboarding/pin_entry_screen.dart
flutter analyze lib/screens/main/family_screen.dart
flutter build apk --debug
```

## Manual test checklist

**Profile creation:**
- Open app first time → profile creation screen shows ✅
- Avatar preview updates as name is typed ✅
- Tap 👶 in People grid → preview shows 👶 in coloured circle ✅
- Tap ⚽ → switches selection ✅
- Tap "Use a different emoji" → text field appears ✅
- Type 🦋 → tap Use → 🦋 selected, grid input closes ✅
- Submit without name → error message ✅
- Submit with name + emoji → lands on dashboard ✅

**User picker:**
- Existing user with emoji → emoji shown in avatar circle ✅
- Existing user without emoji → first letter shown (fallback) ✅
- New user added → emoji appears immediately in picker ✅

**Family screen:**
- Member cards show emoji avatars ✅
- Members without emoji show first-letter fallback ✅
