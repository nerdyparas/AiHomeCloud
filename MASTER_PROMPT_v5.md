# AiHomeCloud — Agent Prompt v5
# Model: claude-opus-4-6 via Aider
# Run: aider --model claude-opus-4-6 --no-auto-commit

## Context
AiHomeCloud is a FastAPI + Flutter home cloud app.
Device is always on ethernet (LAN-only). Phone and device are on same home network.
Login works. Upload works. Focus is refining what's broken and simplifying UX.
Do NOT touch: Telegram, AdGuard, Tailscale, auto_ap, onboarding/pairing flow.

## Architecture rules — never break these
- run_command() returns tuple: `rc, stdout, stderr = await run_command([...])`
- friendlyError(e) not e.toString() in Flutter
- settings.nas_root and settings.data_dir — never hardcode paths
- logger not print() in backend
- All HTTP calls via ApiService — never raw http in widgets

---

## TASK 1 — Add GET /api/v1/network/status endpoint
### Problem
Flutter dashboard calls GET /api/v1/network/status but it doesn't exist in the backend.
This causes an error card on dashboard AND a duplicate display alongside the speed tile.
network_routes.py only has GET/PUT /api/v1/network/wifi.

### Files to edit
- backend/app/routes/network_routes.py

### Implementation
Add this endpoint. For LAN-only device it returns ethernet status only.
All WiFi/hotspot fields return disabled/null since we removed WiFi from main branch.

```python
from ..models import NetworkStatus

@router.get("/network/status", response_model=NetworkStatus)
async def network_status(_user: dict = Depends(get_current_user)):
    """Return LAN-only network state for ethernet-connected device."""
    # Read LAN state from /sys/class/net/
    lan_connected = False
    lan_ip = None
    lan_speed = None

    net_dir = Path("/sys/class/net")
    if net_dir.exists():
        for iface in net_dir.iterdir():
            name = iface.name
            if name == "lo" or name.startswith("wl") or name.startswith("docker") or name.startswith("veth"):
                continue
            operstate = iface / "operstate"
            if operstate.exists() and operstate.read_text().strip() == "up":
                lan_connected = True
                # Get IP address
                rc, out, _ = await run_command(["ip", "-4", "addr", "show", name])
                for line in out.splitlines():
                    line = line.strip()
                    if line.startswith("inet "):
                        lan_ip = line.split()[1].split("/")[0]
                        break
                # Get link speed
                speed_file = iface / "speed"
                if speed_file.exists():
                    try:
                        speed_val = speed_file.read_text().strip()
                        if speed_val.lstrip("-").isdigit() and int(speed_val) > 0:
                            lan_speed = f"{speed_val} Mb/s"
                    except OSError:
                        pass
                break

    return NetworkStatus(
        wifiEnabled=False,
        wifiConnected=False,
        wifiSsid=None,
        wifiIp=None,
        hotspotEnabled=False,
        hotspotSsid=None,
        bluetoothEnabled=False,
        lanConnected=lan_connected,
        lanIp=lan_ip,
        lanSpeed=lan_speed,
        gateway=None,
        dns=None,
    )
```

Also add missing import at top of network_routes.py:
  from pathlib import Path
  from ..subprocess_runner import run_command

### Validation
  grep -n "network/status" backend/app/routes/network_routes.py  # must exist
  pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py

---

## TASK 2 — Fix StatTile overflow (system stats tiles)
### Problem
childAspectRatio: 1.45 in the 2×2 SliverGrid is too tight when helperText is present.
With 4 content rows (icon, label, value, helperText) items overflow the tile boundary.

### Files to edit
- lib/screens/main/dashboard_screen.dart
- lib/widgets/stat_tile.dart

### Implementation in dashboard_screen.dart
Change childAspectRatio from 1.45 to 1.25. This gives each tile more vertical room.

```dart
// Find: childAspectRatio: 1.45,
// Replace with:
childAspectRatio: 1.25,
```

### Implementation in stat_tile.dart
Wrap the entire Column in a LayoutBuilder and ensure it never overflows.
Replace the outer Column with:

```dart
child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    // Icon badge — make it smaller to save space
    Container(
      padding: const EdgeInsets.all(6),   // was 8
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),  // was 10
      ),
      child: Icon(icon, color: colour, size: 18),  // was 20
    ),
    const SizedBox(height: 8),  // was 12
    Text(
      label,
      style: GoogleFonts.dmSans(
        color: AppColors.textSecondary,
        fontSize: 11,   // was 12
        fontWeight: FontWeight.w500,
      ),
    ),
    const SizedBox(height: 2),  // was 4
    Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: GoogleFonts.sora(
            color: AppColors.textPrimary,
            fontSize: 20,   // was 22
            fontWeight: FontWeight.w700,
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: 2),
          Text(
            unit!,
            style: GoogleFonts.dmSans(
              color: AppColors.textSecondary,
              fontSize: 12,  // was 13
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    ),
    if (helperText != null) ...[
      const SizedBox(height: 2),  // was 4
      Text(
        helperText!,
        style: GoogleFonts.dmSans(
          color: helperColor ?? AppColors.textSecondary,
          fontSize: 11,   // was 12
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    ],
  ],
),
```

### Validation
  flutter analyze lib/widgets/stat_tile.dart lib/screens/main/dashboard_screen.dart

---

## TASK 3 — Fix admin showing 0GB in family view
### Problem
admin user's personal folder may not exist on the mounted NAS drive
because add_user() runs at startup before the NAS drive is necessarily mounted.
_folder_size_gb_sync does os.walk on a path that doesn't exist → returns 0.

### Files to edit
- backend/app/routes/family_routes.py

### Implementation
Ensure the personal folder and its sub-folders exist before calculating size.
Add this helper at the top of the file (after imports):

```python
def _ensure_personal_folder(path: str) -> None:
    """Create personal folder and standard sub-folders if missing."""
    p = Path(path)
    if not p.exists():
        try:
            p.mkdir(parents=True, exist_ok=True)
            for sub in ("Photos", "Videos", "Documents", "Others", ".inbox"):
                (p / sub).mkdir(exist_ok=True)
        except OSError:
            pass
```

In list_family(), add one line before the gather call:
```python
    personal_dirs = [str(settings.personal_path / u["name"]) for u in users]
    # Ensure each user's personal folder exists on the currently mounted NAS
    for d in personal_dirs:
        _ensure_personal_folder(d)
    sizes = await asyncio.gather(*[_folder_size_gb(d) for d in personal_dirs])
```

Also add missing import: `from pathlib import Path`

### Validation
  pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py

---

## TASK 4 — Speed up file uploads
### Problem
20MB file takes ~15 seconds. Root cause: 1MB chunk size means 20 async
read→TLS-encrypt→write cycles on ARM. Larger chunks = fewer round-trips.

### Files to edit
- backend/app/config.py
- backend/app/routes/file_routes.py

### Implementation in config.py
```python
# Find:
upload_chunk_size: int = 1024 * 1024  # 1 MB
# Replace with:
upload_chunk_size: int = 4 * 1024 * 1024  # 4 MB — fewer async cycles on ARM
```

### Implementation in file_routes.py
```python
# Find:
_UPLOAD_WRITE_BUF = 256 * 1024
# Replace with:
_UPLOAD_WRITE_BUF = 2 * 1024 * 1024  # 2 MB write buffer
```

### Validation
  grep -n "upload_chunk_size" backend/app/config.py   # should show 4 * 1024 * 1024
  grep -n "_UPLOAD_WRITE_BUF" backend/app/routes/file_routes.py  # should show 2 * 1024 * 1024

---

## TASK 5 — Move Family tab into More screen
### Problem
Family tab occupies a permanent bottom nav slot but family management is occasional.
Move it into More screen as a navigation item. Bottom nav becomes: Home, Files, More.

### Files to edit
- lib/navigation/main_shell.dart
- lib/screens/main/more_screen.dart

### Implementation in main_shell.dart

Replace the 4-destination NavigationBar with a 3-destination one:

```dart
// Remove case 2 (family) from onDestinationSelected:
onDestinationSelected: (i) {
  switch (i) {
    case 0: context.go('/dashboard');
    case 1: context.go('/files');
    case 2: context.go('/more');
  }
},

// Remove Family from destinations list — keep only Home, Files, More:
destinations: [
  _dest(Icons.home_outlined, Icons.home_rounded, 'Home', idx == 0),
  _dest(Icons.folder_outlined, Icons.folder_rounded, 'Files', idx == 1),
  _dest(Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More', idx == 2),
],
```

Fix the index calculation at top of build():
```dart
// Find the idx computation — update to 3-tab mapping:
int idx = 0;
if (loc.startsWith('/files')) idx = 1;
// remove the family case
if (loc.startsWith('/more')) idx = 2;
```

### Implementation in more_screen.dart

Add a "Family" entry near the top of the settings list (before Storage Drive).
Import family_screen.dart and add a ListTile that navigates to /family:

```dart
// Add near top of settings sections (before Storage Drive section):
AppCard(
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.people_rounded, color: AppColors.primary, size: 20),
    ),
    title: Text('Family', style: GoogleFonts.dmSans(
      color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
    subtitle: Text('Manage family members and storage',
      style: GoogleFonts.dmSans(color: AppColors.textSecondary, fontSize: 12)),
    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
    onTap: () => context.go('/family'),
  ),
),
```

### Validation
  flutter analyze lib/navigation/main_shell.dart lib/screens/main/more_screen.dart

---

## TASK 6 — Replace Files tabs with simple file explorer
### Problem
Files screen has 3 segments (My Files | Shared | Videos). User should see a clean
explorer with exactly 2 root entries per user: their personal folder and Shared.
No tabs. No segment control. Just a folder list they can navigate into.

### Files to edit
- lib/screens/main/files_screen.dart  (rewrite)

### Backend change needed first — folder info endpoint
Add to backend/app/routes/file_routes.py a quick folder-info response.
When listing a directory, the backend currently returns sizeBytes: 0 for dirs.
For the 2 root folders only, we need item count. Do this client-side:
the item count is already available from the file list response (count the items).

### Flutter implementation — rewrite files_screen.dart

The new FilesScreen shows:
1. A header "Files"
2. Two folder cards: "{currentUser's name}" and "Shared"
3. Each card shows: folder icon, name, item count (loaded async), chevron
4. Tapping navigates into that folder using the existing FolderView widget

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../providers/core_providers.dart';
import '../../services/auth_session.dart';
import '../../widgets/folder_view.dart';
import '../../widgets/app_card.dart';

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});
  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  // null = root view, non-null = inside a folder
  String? _currentPath;
  String? _currentTitle;

  void _openFolder(String path, String title) {
    setState(() {
      _currentPath = path;
      _currentTitle = title;
    });
  }

  void _goBack() {
    setState(() {
      _currentPath = null;
      _currentTitle = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPath != null) {
      // Show folder contents using existing FolderView
      return WillPopScope(
        onWillPop: () async { _goBack(); return false; },
        child: FolderView(
          title: _currentTitle ?? 'Files',
          folderPath: _currentPath!,
          readOnly: false,
          showHeader: true,
          onBack: _goBack,
        ),
      );
    }

    // Root view: show 2 folder entries
    final session = ref.watch(authSessionProvider);
    final username = session?.username ?? 'My Files';
    final personalPath = '/personal/$username/';
    const sharedPath = '/shared/';

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
                    path: personalPath,
                    icon: Icons.person_rounded,
                    color: AppColors.primary,
                    onTap: () => _openFolder(personalPath, username),
                  ),
                  const SizedBox(height: 12),
                  _FolderCard(
                    name: 'Shared',
                    path: sharedPath,
                    icon: Icons.people_rounded,
                    color: AppColors.secondary,
                    onTap: () => _openFolder(sharedPath, 'Shared'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderCard extends ConsumerWidget {
  final String name;
  final String path;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FolderCard({
    required this.name,
    required this.path,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textMuted),
        onTap: onTap,
      ),
    );
  }
}
```

Check FolderView widget signature — if it doesn't have an `onBack` parameter, add one:
In folder_view.dart, add `final VoidCallback? onBack;` to the constructor and use it
in the back button if present, otherwise use Navigator.pop.

### Validation
  flutter analyze lib/screens/main/files_screen.dart
  flutter analyze lib/widgets/folder_view.dart

---

## TASK 7 — Netflix-style user picker (replace dropdown PIN entry)
### Problem
pin_entry_screen.dart shows a DropdownButton to select user then a PIN field.
For a family product this should feel like Netflix: avatar circles per user, tap one,
then enter PIN. First-time feel: welcoming, not technical.

### Files to edit
- lib/screens/onboarding/pin_entry_screen.dart  (rewrite the UI, keep logic)

### Implementation
Keep all existing logic: fetchUserNames(), _login(), _selectedUser, _pinController.
Replace only the UI portion.

The screen shows:
1. "Who's using AiHomeCloud?" title
2. A Wrap of avatar circles, one per user
3. Each avatar: colored circle with first letter, name below
4. Tapping an avatar: sets _selectedUser, animates to PIN entry row
5. PIN entry row appears below avatars with: "Enter PIN for {name}" + digit field + Connect button
6. If only 1 user: skip picker, go straight to PIN entry

Avatar colors: cycle through
  [0xFFE8A84C, 0xFF4C9BE8, 0xFF4CE88A, 0xFFE84CA8, 0xFF9B59B6, 0xFF1ABC9C]

```dart
// Key structural change — replace the build() content:

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(
      child: _isLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _buildBody(),
    ),
  );
}

Widget _buildBody() {
  if (_userNames.isEmpty) {
    return Center(child: Text(_error ?? 'No users found.',
      style: GoogleFonts.dmSans(color: AppColors.error)));
  }

  final colors = [
    const Color(0xFFE8A84C), const Color(0xFF4C9BE8), const Color(0xFF4CE88A),
    const Color(0xFFE84CA8), const Color(0xFF9B59B6), const Color(0xFF1ABC9C),
  ];

  return Column(
    children: [
      const Spacer(),
      Text('Who\'s using\nAiHomeCloud?',
        textAlign: TextAlign.center,
        style: GoogleFonts.sora(
          color: AppColors.textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: 1.2,
        )),
      const SizedBox(height: 40),
      // Avatar grid
      Wrap(
        spacing: 24,
        runSpacing: 24,
        alignment: WrapAlignment.center,
        children: [
          for (int i = 0; i < _userNames.length; i++)
            GestureDetector(
              onTap: () => setState(() {
                _selectedUser = _userNames[i];
                _pinController.clear();
                _error = null;
              }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      shape: BoxShape.circle,
                      border: _selectedUser == _userNames[i]
                        ? Border.all(color: AppColors.primary, width: 3)
                        : null,
                      boxShadow: _selectedUser == _userNames[i]
                        ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 12)]
                        : null,
                    ),
                    child: Center(
                      child: Text(
                        _userNames[i][0].toUpperCase(),
                        style: GoogleFonts.sora(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_userNames[i],
                    style: GoogleFonts.dmSans(
                      color: _selectedUser == _userNames[i]
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: _selectedUser == _userNames[i]
                        ? FontWeight.w600
                        : FontWeight.w400,
                    )),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 40),
      // PIN entry — shown only after user is selected
      if (_selectedUser != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              Text('Enter PIN for $_selectedUser',
                style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 8,
                autofocus: true,
                textAlign: TextAlign.center,
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
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                  style: GoogleFonts.dmSans(color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _login,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                    : Text('Connect',
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        )),
                ),
              ),
            ],
          ),
        ),
      ],
      const Spacer(),
    ],
  );
}
```

Keep the existing _login() method and all state variables unchanged.
Add `bool _isSubmitting = false;` state variable if not present.
Set `_isSubmitting = true` before the login API call, `false` in finally block.

### Validation
  flutter analyze lib/screens/onboarding/pin_entry_screen.dart

---

## Final validation — run all of these before done
  pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py
  flutter analyze
  flutter build apk --debug

## Commit when all pass
  git add -A
  git commit -m "feat: network status endpoint, StatTile fix, family→more, file explorer, Netflix picker, upload speed"
