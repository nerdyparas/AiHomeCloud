# AiHomeCloud — Sessions 1–4 Master Prompt
# Model: claude-opus-4-6 (GitHub Copilot)
# Complete one session at a time. Test on device before starting the next.

---

## ARCHITECTURE RULES — never break these across all sessions

- `run_command()` always returns tuple: `rc, stdout, stderr = await run_command([...])`
- `friendlyError(e)` is the only error surface in Flutter — no raw exceptions shown to users
- `settings.nas_root` / `settings.shared_path` / `settings.personal_path` — never hardcode `/srv/nas`
- `store.py` is the only JSON persistence layer — no direct file reads for user/service data
- No technical terms in UI strings: no `/dev/`, `/srv/nas/`, `ext4`, `NVMe`, `partition`
- All new config fields go in `backend/app/config.py` as Pydantic fields
- `logger` not `print()` in all backend code

---

# SESSION 1 — Onboarding: Auto-scan + Profile Creation

## Context

`splash_screen.dart` currently shows a welcome screen with a "Find My AiHomeCloud" button
that appears after 1.5s. The user taps it and is sent to `network_scan_screen.dart`.
`network_scan_screen.dart` already performs an mDNS/IP scan and shows results.
`pin_entry_screen.dart` shows the Netflix-style user picker with PIN entry.

The goal is: remove the manual button tap, merge the scan into the splash screen itself,
and add a profile creation page that appears after device selection when no users exist yet.

---

## Task 1A — Merge auto-scan into splash_screen.dart

### File to rewrite: `lib/screens/onboarding/splash_screen.dart`

**Current behaviour:**
- Shows logo + title + subtitle
- After 1.5s shows "Find My AiHomeCloud" button
- Button navigates to `/scan-network`

**New behaviour:**
1. Show logo + title + subtitle centered (existing animation, unchanged)
2. After 2 seconds: animate the logo+title block upward to the top third of screen
   using `AnimatedAlign` or `AnimatedPositioned` with 400ms ease-out curve
3. Below the shifted content, show a scanning section that appears as content moves up:
   - A `LinearProgressIndicator` while scanning
   - Device tiles appearing as they are found (same `_DeviceTile` widget from
     `network_scan_screen.dart` — copy it into this file)
   - If no device found after scan completes: show "No device found on this network"
     with a "Try again" text button
   - If already authenticated (`authSessionProvider != null`): skip everything,
     go to `/user-picker` immediately (800ms delay for splash feel)
4. Tapping a device tile goes to `/user-picker` with the device IP as `extra`

**State variables needed:**
```dart
bool _scanning = false;
bool _scanComplete = false;
bool _contentShifted = false;    // drives the upward animation
List<DiscoveredHost> _hosts = [];
String? _error;
```

**Scan logic:** import `NetworkScanner` from `network_scan_screen.dart` (or
`services/network_scanner.dart` — check the import). Start scan at `_contentShifted = true`
moment (2s after mount). Stream results into `_hosts` list as they arrive.

**Do not delete `network_scan_screen.dart`** — it is still reachable from settings
for reconnecting to a different device.

**Layout structure:**
```
Scaffold
  SafeArea
    Column
      AnimatedAlign (alignment shifts from center to topCenter over 400ms)
        → logo + title + subtitle block (existing _Illustration + Text widgets)
      Expanded
        → scanning area: progress bar while scanning, device tiles as found
```

---

## Task 1B — Create profile creation screen

### New file: `lib/screens/onboarding/profile_creation_screen.dart`

This screen appears after selecting a device **only when no users exist yet** (first boot).
On subsequent boots it goes straight to the user picker.

**How to detect first boot:** After getting the device IP, call
`api.fetchUserNames(ip)` before navigating. If the list is empty → go to
`/profile-creation`. If non-empty → go to `/user-picker`.

**Profile creation screen layout (Netflix account creation style):**

```
Scaffold, AppColors.background
  SafeArea
    Column, centered, padding 32h
      SizedBox height 40
      Text "Set up your profile"   ← GoogleFonts.sora, 26sp, w700
      SizedBox height 8
      Text "You'll be the admin. Others can join later."
        ← GoogleFonts.dmSans, textSecondary, 14sp
      SizedBox height 40

      // Avatar colour picker — 6 circles in a row
      // User taps one to select their avatar colour
      // Same 6 colours as PinEntryScreen._avatarColors:
      // [0xFFE8A84C, 0xFF4C9BE8, 0xFF4CE88A, 0xFFE84CA8, 0xFF9B59B6, 0xFF1ABC9C]
      Row of 6 GestureDetector circles (48x48), selected has white border + shadow
      SizedBox height 32

      // Name field
      Text "Your name"  ← label style
      SizedBox height 8
      TextField controller: _nameCtrl
        hintText: "e.g. Mike, Mum, Dad"
        keyboard: TextInputType.name
        textCapitalization: TextCapitalization.words
        style: AppColors.textPrimary
        filled, AppColors.surface, border radius 12

      SizedBox height 20

      // PIN field — OPTIONAL
      Text "PIN (optional)"  ← label style
      SizedBox height 4
      Text "Leave blank for no PIN"
        ← GoogleFonts.dmSans, textMuted, 12sp
      SizedBox height 8
      TextField controller: _pinCtrl
        keyboardType: TextInputType.number
        obscureText: true
        maxLength: 8
        counterText: ''
        inputFormatters: [FilteringTextInputFormatter.digitsOnly]
        hintText: "••••  (optional)"

      SizedBox height 8
      if (_error != null) Text(_error!, color: AppColors.error)

      Spacer
      SizedBox width double.infinity height 56
        FilledButton "Create Profile"
          onPressed: _saving ? null : _submit
          AppColors.primary, borderRadius 12
      SizedBox height 32
```

**_submit() logic:**
```dart
Future<void> _submit() async {
  final name = _nameCtrl.text.trim();
  if (name.isEmpty) {
    setState(() => _error = 'Please enter your name.');
    return;
  }
  setState(() { _saving = true; _error = null; });
  try {
    // 1. Create user (unauthenticated — first user gets admin automatically)
    final pin = _pinCtrl.text.trim();
    await ref.read(apiServiceProvider).createUser(
      name,
      pin.isNotEmpty ? pin : null,
    );
    // 2. Login immediately
    final result = await ref.read(apiServiceProvider).loginWithPin(
      _deviceIp,      // passed via constructor
      name,
      pin.isNotEmpty ? pin : '',   // empty string PIN = no-PIN login
    );
    await ref.read(authSessionProvider.notifier).login(
      host: _deviceIp,
      port: AppConstants.apiPort,
      token: result['accessToken'] as String,
      refreshToken: result['refreshToken'] as String?,
      username: name,
      isAdmin: true,
    );
    if (!mounted) return;
    context.go('/dashboard');
  } catch (e) {
    if (mounted) setState(() { _error = friendlyError(e); _saving = false; });
  }
}
```

**Constructor:** `ProfileCreationScreen({required String deviceIp})`

---

## Task 1C — Backend: allow empty-string PIN login

**File:** `backend/app/routes/auth_routes.py`

When PIN is optional, a user with no PIN set should log in with an empty string.

Find the login endpoint (around the `LoginRequest` handling). Currently it likely
rejects empty PINs. Update the PIN check:

```python
# In the login handler, where PIN is verified:
if user.get("pin"):
    # User has a PIN set — verify it
    if not body.pin or not verify_pin(body.pin, user["pin"]):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid PIN")
else:
    # User has no PIN — any PIN input is accepted (including empty string)
    pass
```

Also in `CreateUserRequest` in `backend/app/models.py`, pin is already `Optional[str] = None`
— no change needed there.

---

## Task 1D — Router: add new routes and update redirect logic

**File:** `lib/navigation/app_router.dart`

Add these two routes:

```dart
GoRoute(
  path: '/user-picker',
  builder: (_, state) {
    final ip = state.extra as String;
    return PinEntryScreen(deviceIp: ip);
  },
),
GoRoute(
  path: '/profile-creation',
  builder: (_, state) {
    final ip = state.extra as String;
    return ProfileCreationScreen(deviceIp: ip);
  },
),
```

Update the `redirect` logic:
```dart
// Add /user-picker and /profile-creation to the onboarding set
final onOnboarding = loc == '/' ||
    loc == '/scan-network' ||
    loc == '/pin-entry' ||
    loc == '/user-picker' ||
    loc == '/profile-creation';
```

Keep `/pin-entry` route for backwards compatibility but it can point to the same
`PinEntryScreen`.

Update splash screen navigation: when device is tapped, first call `fetchUserNames`,
then route to `/profile-creation` (empty list) or `/user-picker` (non-empty list).

---

## Session 1 validation

```bash
flutter analyze lib/screens/onboarding/
flutter analyze lib/navigation/app_router.dart
flutter build apk --debug
```

**Manual test:**
1. Fresh install — splash → logo animates up → scan → device appears → tap →
   profile creation screen → enter name (no PIN) → lands on dashboard ✅
2. Reopen app — goes straight to user picker ✅
3. No network — scan completes with "No device found" + retry button ✅

---

---

# SESSION 2 — Folder Structure: family/ + entertainment/ at NAS root

## Context

Current NAS layout:
```
/srv/nas/
  personal/
    {username}/  Photos/ Videos/ Documents/ Others/ .inbox/
  shared/
    Photos/  Videos/  Documents/  Others/  Entertainment/  .inbox/
```

Target layout:
```
/srv/nas/
  personal/
    {username}/  Photos/ Videos/ Documents/ Others/ .inbox/
  family/          ← renamed from shared/
    Photos/  Videos/  Documents/  Others/  .inbox/
  entertainment/   ← moved from shared/Entertainment to NAS root
    Movies/  Series/  Anime/  Music/  Others/
```

---

## Task 2A — Add new path config fields

**File:** `backend/app/config.py`

In the `Settings` class, find:
```python
shared_dir: str = "shared"
```

Add below it:
```python
family_dir: str = "family"
entertainment_dir: str = "entertainment"
```

Add new properties:
```python
@property
def family_path(self) -> Path:
    return self.nas_root / self.family_dir

@property
def entertainment_path(self) -> Path:
    return self.nas_root / self.entertainment_dir
```

Keep `shared_path` property but point it to `family_path` for backwards compatibility
during migration:
```python
@property
def shared_path(self) -> Path:
    # Alias for family_path — use family_path in new code
    return self.nas_root / self.family_dir
```

---

## Task 2B — Update file_sorter.py for entertainment

**File:** `backend/app/file_sorter.py`

The sorter currently routes files from `.inbox/` into `Photos/`, `Videos/`,
`Documents/`, `Others/`. Entertainment is a separate root, not a subfolder.

Add entertainment sub-folder sort rules. After `SORT_RULES` dict, add:

```python
# Entertainment sub-folder routing (applied when base_dir is entertainment_path)
ENTERTAINMENT_SORT_RULES: dict[str, str] = {
    ".mp4": "Movies", ".mkv": "Movies", ".avi": "Movies", ".mov": "Movies",
    ".m4v": "Movies", ".wmv": "Movies",
    ".ts": "Series", ".m2ts": "Series", ".mts": "Series",
    ".mp3": "Music", ".flac": "Music", ".aac": "Music", ".wav": "Music",
    ".ogg": "Music", ".m4a": "Music",
    # Anime and Series heuristic — detect from filename patterns in _destination_folder
}
```

Update `_destination_folder()` to accept an optional `base_dir` parameter:

```python
def _destination_folder(file_path: Path, base_dir: Path | None = None) -> str:
    from .config import settings
    # If sorting into entertainment, use entertainment rules
    if base_dir is not None and base_dir == settings.entertainment_path:
        ext = file_path.suffix.lower()
        return ENTERTAINMENT_SORT_RULES.get(ext, "Others")
    # Original logic unchanged below
    ext = file_path.suffix.lower()
    ...
```

Update `_sort_file()` to pass `base_dir` through:
```python
def _sort_file(file_path: Path, base_dir: Path, *, check_age: bool = True) -> Optional[Path]:
    ...
    folder_name = _destination_folder(file_path, base_dir)
    ...
```

Update `_collect_inboxes()` to include the entertainment inbox:
```python
def _collect_inboxes() -> list[tuple[Path, Path]]:
    from .config import settings
    inboxes: list[tuple[Path, Path]] = []

    # family/.inbox/
    family_inbox = settings.family_path / ".inbox"
    if family_inbox.is_dir():
        inboxes.append((family_inbox, settings.family_path))

    # entertainment/.inbox/
    entertainment_inbox = settings.entertainment_path / ".inbox"
    if entertainment_inbox.is_dir():
        inboxes.append((entertainment_inbox, settings.entertainment_path))

    # personal/{username}/.inbox/
    if settings.personal_path.is_dir():
        for user_dir in settings.personal_path.iterdir():
            if user_dir.is_dir():
                inbox = user_dir / ".inbox"
                if inbox.is_dir():
                    inboxes.append((inbox, user_dir))

    return inboxes
```

---

## Task 2C — Update telegram_bot.py destination paths

**File:** `backend/app/telegram_bot.py`

Find `_store_entertainment_file()`:
```python
async def _store_entertainment_file(bot, pending: PendingUpload) -> Path:
    from .file_sorter import _unique_dest
    from .config import settings

    entertainment_dir = settings.shared_path / "Entertainment"   # ← OLD
```

Replace with:
```python
    entertainment_dir = settings.entertainment_path   # ← NEW
```

Find `_pending_upload_prompt` — update the labels to match new structure:
```python
def _pending_upload_prompt(filename: str) -> str:
    return (
        f"Received: {filename}\n\n"
        "Choose where to save:\n"
        "1. My personal folder\n"
        "2. Family shared folder\n"
        "3. Entertainment\n\n"
        "Reply with 1, 2, or 3."
    )
```

Find `_handle_pending_upload_choice` — update label strings:
```python
dest_map = {
    "1": ("private", "personal"),
    "2": ("shared", "family"),
    "3": ("entertainment", "entertainment"),
}
```

---

## Task 2D — Update telegram_upload_routes.py

**File:** `backend/app/routes/telegram_upload_routes.py`

Find the upload_file endpoint where it sets `dest_dir` for entertainment:
```python
if ut.destination == "entertainment":
    dest_dir = settings.shared_path / "Entertainment"   # ← OLD
```

Replace with:
```python
    dest_dir = settings.entertainment_path              # ← NEW
```

---

## Task 2E — Update first-boot-setup.sh directories

**File:** `scripts/first-boot-setup.sh`

Find the DIRS array in Step 4:
```bash
DIRS=(
    "$NAS_ROOT/personal"
    "$NAS_ROOT/shared"
    ...
)
```

Replace with:
```bash
DIRS=(
    "$NAS_ROOT/personal"
    "$NAS_ROOT/family"
    "$NAS_ROOT/entertainment"
    "$NAS_ROOT/entertainment/Movies"
    "$NAS_ROOT/entertainment/Series"
    "$NAS_ROOT/entertainment/Anime"
    "$NAS_ROOT/entertainment/Music"
    "$NAS_ROOT/entertainment/Others"
    "$DATA_DIR/tls"
    "$APP_HOME"
    "$BACKEND_SRC"
)
```

---

## Task 2F — Update minidlna config in first-boot-setup.sh

**File:** `scripts/first-boot-setup.sh`

In the minidlna config block written during setup, update `media_dir` lines:

```bash
# Old:
media_dir=V,${NAS_ROOT}/shared/Videos
media_dir=V,${NAS_ROOT}/shared/Entertainment
media_dir=P,${NAS_ROOT}/shared/Photos
media_dir=A,${NAS_ROOT}/shared/Music

# New:
media_dir=V,${NAS_ROOT}/entertainment/Movies
media_dir=V,${NAS_ROOT}/entertainment/Series
media_dir=V,${NAS_ROOT}/entertainment/Anime
media_dir=V,${NAS_ROOT}/family/Videos
media_dir=P,${NAS_ROOT}/family/Photos
media_dir=P,${NAS_ROOT}/personal
media_dir=A,${NAS_ROOT}/entertainment/Music
```

---

## Task 2G — Update Flutter constants

**File:** `lib/core/constants.dart`

Find:
```dart
static const String personalBasePath = '/srv/nas/personal/';
static const String sharedPath = '/srv/nas/shared/';
```

Add / update:
```dart
static const String personalBasePath = '/srv/nas/personal/';
static const String familyPath = '/srv/nas/family/';
static const String entertainmentPath = '/srv/nas/entertainment/';
// Keep sharedPath as alias during transition
static const String sharedPath = '/srv/nas/family/';
```

---

## Task 2H — Data migration note (add as comment in main.py startup)

**File:** `backend/app/main.py`

In the lifespan startup block, add a one-time migration that runs if the old
`shared/` path exists and new `family/` does not:

```python
# One-time migration: shared/ → family/
import shutil as _shutil
old_shared = settings.nas_root / "shared"
new_family = settings.family_path
old_entertainment = old_shared / "Entertainment"
new_entertainment = settings.entertainment_path

if old_shared.exists() and not new_family.exists():
    logger.info("Migrating shared/ → family/ and entertainment/")
    if old_entertainment.exists():
        new_entertainment.mkdir(parents=True, exist_ok=True)
        for item in old_entertainment.iterdir():
            _shutil.move(str(item), str(new_entertainment / item.name))
        old_entertainment.rmdir()
    _shutil.move(str(old_shared), str(new_family))
    logger.info("Migration complete")
```

---

## Session 2 validation

```bash
python3 -m py_compile backend/app/config.py && echo OK
python3 -m py_compile backend/app/file_sorter.py && echo OK
python3 -m py_compile backend/app/telegram_bot.py && echo OK
pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py
bash -n scripts/first-boot-setup.sh && echo OK
```

---

---

# SESSION 3 — Files Tab: 3 Folder Cards

## Context

`files_screen.dart` currently shows 2 folder cards: personal (username) and Shared.
Target: show 3 cards — Personal, Family, Entertainment — matching the new NAS layout.

---

## Task 3A — Rewrite FilesScreen root view

**File:** `lib/screens/main/files_screen.dart`

The `_currentPath == null` branch (root view) currently renders 2 `_FolderCard` tiles.
Replace that `ListView` content with 3 tiles:

```dart
// Root view: 3 folder cards
final session = ref.watch(authSessionProvider);
final username = session?.username ?? 'Personal';
final personalPath = '${AppConstants.personalBasePath}$username/';

return Scaffold(
  backgroundColor: AppColors.background,
  body: SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Text('Files',
              style: GoogleFonts.sora(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              )),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _FolderCard(
                name: username,
                subtitle: 'Your private files',
                icon: Icons.person_rounded,
                color: AppColors.primary,
                onTap: () => _openFolder(personalPath, username),
              ),
              const SizedBox(height: 12),
              _FolderCard(
                name: 'Family',
                subtitle: 'Shared with everyone',
                icon: Icons.people_rounded,
                color: const Color(0xFF4CE88A),
                onTap: () => _openFolder(AppConstants.familyPath, 'Family'),
              ),
              const SizedBox(height: 12),
              _FolderCard(
                name: 'Entertainment',
                subtitle: 'Movies, series, music',
                icon: Icons.movie_rounded,
                color: const Color(0xFFE84CA8),
                onTap: () => _openFolder(
                    AppConstants.entertainmentPath, 'Entertainment'),
              ),
            ],
          ),
        ),
      ],
    ),
  ),
);
```

Update `_FolderCard` widget to accept an optional `subtitle` parameter:

```dart
class _FolderCard extends StatelessWidget {
  final String name;
  final String? subtitle;    // ← add this
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FolderCard({
    required this.name,
    this.subtitle,            // ← add this
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(name,
            style: GoogleFonts.dmSans(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            )),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ))
            : null,
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}
```

---

## Task 3B — Remove entertainment from family/shared folder backend routes

**File:** `backend/app/routes/file_routes.py`

Find any hardcoded references to `shared/Entertainment` or `shared_path / "Entertainment"`
and replace with `settings.entertainment_path`. Use grep to locate:

```bash
grep -n "Entertainment\|shared.*entertain\|entertain.*shared" \
  backend/app/routes/file_routes.py
```

Replace every occurrence of `settings.shared_path / "Entertainment"` with
`settings.entertainment_path`.

---

## Task 3C — Update family_routes.py path references

**File:** `backend/app/routes/family_routes.py`

Find any references to `settings.shared_path` that should now be `settings.family_path`.
The family admin screen shows folder sizes for shared content — this should reflect
the `family/` folder, not `entertainment/`.

```bash
grep -n "shared_path\|shared_dir" backend/app/routes/family_routes.py
```

Replace `settings.shared_path` → `settings.family_path` throughout.

---

## Session 3 validation

```bash
flutter analyze lib/screens/main/files_screen.dart
flutter analyze lib/core/constants.dart
flutter build apk --debug
```

**Manual test:**
1. Files tab shows 3 cards: (username), Family, Entertainment ✅
2. Tap username card → opens personal folder with Photos/Videos/Documents/Others ✅
3. Tap Family → opens family shared folder ✅
4. Tap Entertainment → opens entertainment with Movies/Series/Anime/Music/Others ✅

---

---

# SESSION 4 — User Picker on Every App Open + Add User Flow

## Context

Currently `pin_entry_screen.dart` is only reached from the scan flow.
On subsequent opens `splash_screen.dart` detects an existing session and goes
straight to `/dashboard`.

Target: on every cold open where session exists → go to `/user-picker` instead of
`/dashboard`. The user picker shows existing profiles + an "Add" tile. Selecting
a profile asks for PIN (or skips if no PIN set). Adding a profile creates it
and logs in as the new user.

---

## Task 4A — Update splash screen session-exists flow

**File:** `lib/screens/onboarding/splash_screen.dart`

In `_init()`, find:
```dart
if (session != null) {
  await Future.delayed(const Duration(milliseconds: 800));
  if (!mounted) return;
  final api = ref.read(apiServiceProvider);
  try {
    await api.getDeviceInfo();
    if (!mounted) return;
    context.go('/dashboard');     // ← change this
  } catch (_) {
    if (!mounted) return;
    context.go('/scan-network');
  }
  return;
}
```

Change `context.go('/dashboard')` to `context.go('/user-picker', extra: session!.host)`.

The user picker will verify the session is still valid. If the SBC is unreachable
it will fall back gracefully (see Task 4B).

---

## Task 4B — Update PinEntryScreen to handle offline + add "Add User" tile

**File:** `lib/screens/onboarding/pin_entry_screen.dart`

### B1 — Add offline error handling

In `_fetchUsers()`, if the network call fails, show a card:
```
"Can't reach your AiHomeCloud"
"Make sure you're on the same Wi-Fi network."
[Retry]  [Find Device]
```

```dart
} catch (e) {
  if (!mounted) return;
  setState(() {
    _loadingUsers = false;
    _offlineError = true;    // new bool state variable
  });
}
```

In `_buildBody()`, if `_offlineError == true`:
```dart
return Center(
  child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(children: [
            const Icon(Icons.wifi_off_rounded,
                color: AppColors.textMuted, size: 48),
            const SizedBox(height: 16),
            Text("Can't reach your AiHomeCloud",
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text("Make sure you're on the same Wi-Fi network.",
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton(
                onPressed: _fetchUsers,
                child: const Text('Retry'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => context.go('/scan-network'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: const Text('Find Device'),
              ),
            ]),
          ]),
        ),
      ],
    ),
  ),
);
```

### B2 — Add "Add User" tile to the avatar grid

In `_buildBody()`, inside the `Wrap` of avatar tiles, add one more tile after
the existing users loop:

```dart
// Add User tile — always shown at the end
GestureDetector(
  onTap: () async {
    // Navigate to profile creation, passing current device IP
    final result = await context.push<bool>(
      '/profile-creation',
      extra: widget.deviceIp,
    );
    // If a new user was created, refresh the user list
    if (result == true && mounted) {
      await _fetchUsers();
    }
  },
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
          border: Border.all(
              color: AppColors.cardBorder, width: 2),
        ),
        child: const Icon(Icons.add_rounded,
            color: AppColors.textSecondary, size: 30),
      ),
      const SizedBox(height: 8),
      Text('Add',
          style: GoogleFonts.dmSans(
              color: AppColors.textSecondary,
              fontSize: 13)),
    ],
  ),
),
```

### B3 — Handle no-PIN login (user has no PIN set)

Currently `_submit()` requires a non-empty PIN. Update to allow empty:

```dart
Future<void> _submit() async {
  // Allow empty PIN — backend accepts it for no-PIN users
  final pin = _pinController.text.trim();
  if (_selectedUser == null) return;

  setState(() { _loading = true; _error = null; });
  try {
    final result = await ApiService.instance.loginWithPin(
      widget.deviceIp,
      _selectedUser!,
      pin,   // empty string is valid for no-PIN users
    );
    ...
  }
}
```

Also add a "Skip PIN" button that appears after 2s of no input if the PIN field
is still empty, so no-PIN users don't wonder what to do:

```dart
// After PIN field, add:
if (_pinController.text.isEmpty)
  TextButton(
    onPressed: () => _submit(),
    child: Text('No PIN? Tap here to continue',
        style: GoogleFonts.dmSans(
            color: AppColors.textSecondary, fontSize: 12)),
  ),
```

---

## Task 4C — Update ProfileCreationScreen to return true on success

**File:** `lib/screens/onboarding/profile_creation_screen.dart`

When navigated to via `context.push` (from Add User tile), it should pop and
return `true` instead of `context.go('/dashboard')`.

Add a `bool isAddingUser` constructor param defaulting to `false`:

```dart
class ProfileCreationScreen extends ConsumerStatefulWidget {
  final String deviceIp;
  final bool isAddingUser;    // ← add this
  const ProfileCreationScreen({
    super.key,
    required this.deviceIp,
    this.isAddingUser = false,
  });
}
```

In `_submit()`, after successful creation:
```dart
if (widget.isAddingUser) {
  if (!mounted) return;
  context.pop(true);    // return to user picker
} else {
  if (!mounted) return;
  context.go('/dashboard');   // first-boot flow
}
```

Update the router to pass `isAddingUser: true` when pushed from the Add User tile.
Since `context.push` passes `extra`, update the profile-creation route:

```dart
GoRoute(
  path: '/profile-creation',
  builder: (_, state) {
    final extra = state.extra as Map<String, dynamic>;
    return ProfileCreationScreen(
      deviceIp: extra['ip'] as String,
      isAddingUser: extra['isAddingUser'] as bool? ?? false,
    );
  },
),
```

Update the Add User onTap in PinEntryScreen to pass:
```dart
context.push('/profile-creation', extra: {
  'ip': widget.deviceIp,
  'isAddingUser': true,
});
```

Update first-boot splash navigation to pass:
```dart
context.go('/profile-creation', extra: {
  'ip': deviceIp,
  'isAddingUser': false,
});
```

---

## Task 4D — Update router redirect for user-picker

**File:** `lib/navigation/app_router.dart`

The redirect currently sends authenticated users to `/dashboard` from any
onboarding route. Update to allow `/user-picker` as a pass-through for
authenticated users:

```dart
// Allow user-picker even when authenticated (it IS the post-auth gate)
if (authSession != null && onOnboarding &&
    loc != '/scan-network' &&
    loc != '/user-picker' &&
    loc != '/profile-creation') {
  return '/user-picker';    // send to picker, not dashboard
}
```

Wait — this creates a loop. Better logic:

```dart
redirect: (_, state) {
  final loc = state.matchedLocation;
  final onOnboarding = loc == '/' ||
      loc == '/scan-network' ||
      loc == '/pin-entry' ||
      loc == '/user-picker' ||
      loc == '/profile-creation';

  // Not logged in and trying to access main app → go to splash
  if (authSession == null && !onOnboarding) return '/';

  // Logged in but on splash root → go to user picker
  // (splash handles this itself, but belt-and-suspenders)
  if (authSession != null && loc == '/') return null;

  return null;
},
```

The splash screen handles the `/dashboard` vs `/user-picker` decision itself
(Task 4A). The router just needs to not block it.

---

## Session 4 validation

```bash
flutter analyze lib/screens/onboarding/
flutter analyze lib/navigation/app_router.dart
flutter build apk --debug
```

**Manual test flow:**
1. Existing session, open app → splash animates → goes to user picker ✅
2. Tap a user with no PIN → "No PIN? Tap here" appears → tap → lands on dashboard ✅
3. Tap a user with PIN → PIN field → enter → dashboard ✅
4. Tap Add → profile creation screen → enter name → back to picker with new user ✅
5. SBC offline → "Can't reach your AiHomeCloud" screen with Retry + Find Device ✅
6. New user created from Add flow → their personal folder
   (personal/{name}/Photos/Videos/Documents/Others/.inbox/) exists on SBC ✅

---

---

# FINAL COMMIT SEQUENCE

Run after all sessions are complete and tested on device:

```bash
# Run all tests
pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py
flutter analyze
flutter test --exclude-tags golden

# Commit
git add -A
git commit -m "feat: new onboarding, family/entertainment folder structure, 3-folder files tab, user picker on every open"
```

---

# QUICK REFERENCE

```
Backend test:   pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py
Flutter test:   flutter test --exclude-tags golden
Flutter build:  flutter build apk --debug
Deploy:         TARGET_HOST=192.168.x.x ./deploy.sh

NAS paths after Session 2:
  Personal:       /srv/nas/personal/{username}/
  Family:         /srv/nas/family/
  Entertainment:  /srv/nas/entertainment/

New routes after Session 4:
  /              → SplashScreen (auto-scan)
  /scan-network  → NetworkScanScreen (manual rescan)
  /user-picker   → PinEntryScreen (every open)
  /profile-creation → ProfileCreationScreen (first boot + add user)
  /dashboard     → main app
```
