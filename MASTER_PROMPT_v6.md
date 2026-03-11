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

## TASK 8 — Fix upload card stuck at 100%
### Problem
In folder_view.dart `_startUpload()`, the `onDone` callback does this in order:
  1. marks task as completed
  2. calls _loadFiles(reset: true)       ← network round trip
  3. await sortedToCompleter.future      ← waits for backend JSON response
  4. THEN shows snackbar
  5. THEN removes card after 3s

Steps 2+3 together take 2–20 seconds on ARM+TLS+pen drive. The card sits
frozen at 100% the entire time. The sortedTo folder name is a nice-to-have —
it should not block the UI.

### Files to edit
- lib/widgets/folder_view.dart

### Implementation
In the `onDone` callback inside `_startUpload()`, reorder so the snackbar and
card removal happen immediately, and the sortedTo is shown only if it arrives
within 2 seconds:

```dart
onDone: () async {
  _uploadSubscriptions.remove(task.id);
  if (!mounted) return;

  // 1. Mark done and refresh file list immediately
  ref.read(uploadTasksProvider.notifier).updateTask(task.id, status: UploadStatus.completed);
  _loadFiles(reset: true);

  // 2. Show immediate snackbar — don't wait for sortedTo
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ ${task.fileName} uploaded')),
    );
  }

  // 3. Remove card after 2s (was 3s)
  Future.delayed(const Duration(seconds: 2), () {
    if (mounted) ref.read(uploadTasksProvider.notifier).removeTask(task.id);
  });

  // 4. If sortedTo arrives quickly, show a second snackbar (bonus info)
  try {
    final sortedTo = await sortedToCompleter.future
        .timeout(const Duration(seconds: 3));
    if (sortedTo != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_uploadSnackMessage(task.fileName, sortedTo))),
      );
    }
  } catch (_) {
    // sortedTo timeout — fine, already showed success snackbar
  }
},
```

### Validation
  flutter analyze lib/widgets/folder_view.dart

---

## TASK 9 — HTTP keep-alive: reuse TLS sessions between folder navigations
### Problem
`_createPinnedHttpClient()` only sets `connectionTimeout = 8s`.
No `idleTimeout` is set, so the Dart HttpClient may close the TLS connection
between requests. Each folder tap potentially renegotiates TLS from scratch
(30–80ms on ARM per handshake). Setting idleTimeout keeps the connection warm.

This is safe for Tailscale (it uses a different IP/port, same HttpClient works)
and has no effect on AdGuard or Telegram (they don't use this HTTP client).

### Files to edit
- lib/services/api_service.dart

### Implementation
In `_createPinnedHttpClient()`, add one line after `connectionTimeout`:

```dart
HttpClient _createPinnedHttpClient() {
  // ... existing SSL context setup ...
  final httpClient = HttpClient(context: context)
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 25);  // ADD THIS LINE
  return httpClient;
}
```

25 seconds is safe: longer than the WebSocket ping interval (2s) so the
connection stays alive between dashboard stats updates.

### Validation
  flutter analyze lib/services/api_service.dart

---

## TASK 10 — In-memory folder listing cache (30s TTL)
### Problem
`fileListProvider` is a bare `FutureProvider.family` — every folder navigation
fires a new HTTP request. Navigating back to a parent folder re-fetches it.
On a pen drive with TLS overhead, this is 300ms–1s per tap even for folders
the user just visited.

This is a pure Flutter-side cache. No backend changes. Safe for all future
features — Tailscale just changes the host, same cache works. AdGuard and
Telegram don't use file listing.

### Files to edit
- lib/providers/file_providers.dart

### Implementation
Replace the bare `FutureProvider.family` with a manual cache in a Notifier:

```dart
// Add at top of file:
class _CacheEntry {
  final FileListResponse data;
  final DateTime fetchedAt;
  _CacheEntry(this.data) : fetchedAt = DateTime.now();
  bool get isStale => DateTime.now().difference(fetchedAt).inSeconds > 30;
}

class FileListNotifier extends AutoDisposeFamilyAsyncNotifier<FileListResponse, FileListQuery> {
  static final _cache = <String, _CacheEntry>{};

  static String _key(FileListQuery q) => '${q.path}|${q.page}|${q.sortBy}|${q.sortDir}';

  static void invalidate(String pathPrefix) {
    _cache.removeWhere((k, _) => k.startsWith(pathPrefix));
  }

  @override
  Future<FileListResponse> build(FileListQuery arg) async {
    final key = _key(arg);
    final cached = _cache[key];
    if (cached != null && !cached.isStale) return cached.data;

    final api = ref.read(apiServiceProvider);
    final result = await api.listFiles(
      arg.path,
      page: arg.page,
      pageSize: arg.pageSize,
      sortBy: arg.sortBy,
      sortDir: arg.sortDir,
    );
    _cache[key] = _CacheEntry(result);
    return result;
  }
}

final fileListProvider =
    AsyncNotifierProvider.autoDispose.family<FileListNotifier, FileListResponse, FileListQuery>(
  FileListNotifier.new,
);
```

After a successful upload or delete, call `FileListNotifier.invalidate(affectedPath)`
to clear the cache for that folder so the user sees fresh content immediately.

In folder_view.dart, after `_loadFiles(reset: true)` add:
```dart
FileListNotifier.invalidate(_currentPath);
```

### Validation
  flutter analyze lib/providers/file_providers.dart
  flutter analyze lib/widgets/folder_view.dart

---

## TASK 11 — Fix false disconnect banner during slow folder loads
### Problem
In system_api.dart, the WebSocket `onError` and `onDone` callbacks immediately
call `_connectionStatusCallback?.call(ConnectionStatus.reconnecting)`.
When the backend is slow (pen drive + heavy directory scan), the WS stream can
stall or drop momentarily. A single missed beat fires `reconnecting` instantly,
which triggers the banner in main_shell.dart (even though the 12s Timer there
delays showing the full banner, the ConnectionStatus.reconnecting state still
causes a UI flicker/grey overlay).

The fix: require 2 consecutive errors/dones before escalating to reconnecting.
One missed beat on a busy ARM board is normal — not a real disconnect.

### Files to edit
- lib/services/api/system_api.dart

### Implementation
In `monitorSystemStats()`, add a consecutive-miss counter:

```dart
Stream<SystemStats> monitorSystemStats() {
  // ... existing uri/channel setup unchanged ...

  int _missedBeats = 0;  // consecutive error/done count

  _connectionStatusCallback?.call(ConnectionStatus.connected);
  final ctrl = StreamController<SystemStats>();
  channel.stream.listen(
    (raw) {
      _missedBeats = 0;  // reset on any successful message
      _connectionStatusCallback?.call(ConnectionStatus.connected);
      // ... existing JSON parse unchanged ...
    },
    onError: (e, st) {
      _missedBeats++;
      if (_missedBeats >= 2) {
        _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
      }
      ctrl.addError(e, st);
    },
    onDone: () {
      _missedBeats++;
      if (_missedBeats >= 2) {
        _connectionStatusCallback?.call(ConnectionStatus.reconnecting);
      }
      ctrl.close();
    },
    cancelOnError: false,
  );
  return ctrl.stream;
}
```

Apply the same pattern to `notificationStream()` — same `onError`/`onDone`
handlers, same 2-miss threshold.

### Validation
  flutter analyze lib/services/api/system_api.dart

---

## TASK 12 — Telegram bot: token-only setup + auto-auth via /auth command

### What changes and why
Current setup asks for two fields: bot token + comma-separated chat IDs.
Chat IDs are a developer concept — normal users don't know their Telegram chat ID
and shouldn't need to. Replace with auto-auth: anyone who sends /auth to the bot
gets linked. Token field is the only thing the admin configures in the app.

No Tailscale required. Bot uses outbound polling to api.telegram.org — works
behind home NAT with no public IP or inbound ports.

---

### TASK 12A — Backend: remove allowed_ids, add /auth command + linked_chat_ids store

#### Files to edit
- backend/app/telegram_bot.py
- backend/app/routes/telegram_routes.py

#### Implementation — telegram_bot.py

Replace `_is_allowed()` with a version that reads `linked_chat_ids` from the
KV store. An empty list means nobody is linked yet — the bot responds asking
them to send /auth first. This is safer than the old "empty = allow all" logic.

```python
# Replace the entire _is_allowed function:

async def _get_linked_ids() -> set[int]:
    """Return set of linked Telegram chat IDs from KV store."""
    from .store import get_value
    ids = await get_value("telegram_linked_ids", default=[])
    return {int(i) for i in ids if str(i).lstrip("-").isdigit()}


async def _add_linked_id(chat_id: int) -> None:
    """Persistently link a new chat_id."""
    from .store import get_value, set_value
    ids = await get_value("telegram_linked_ids", default=[])
    if chat_id not in ids:
        ids.append(chat_id)
        await set_value("telegram_linked_ids", ids)


async def _is_allowed(chat_id: int) -> bool:
    """Return True if chat_id has linked their account via /auth."""
    linked = await _get_linked_ids()
    return chat_id in linked
```

Remove the old synchronous `_is_allowed(chat_id: int) -> bool` function entirely.

Add `/auth` command handler (add before `start_bot()`):

```python
async def _handle_auth(update, context) -> None:
    chat_id = update.effective_chat.id
    first_name = update.effective_user.first_name or "there"

    if await _is_allowed(chat_id):
        await update.message.reply_text(
            f"✅ You're already linked, {first_name}!\n"
            "Type anything to search your files, or /list for recent documents."
        )
        return

    await _add_linked_id(chat_id)
    await update.message.reply_text(
        f"✅ Linked! Welcome, {first_name}.\n\n"
        "You can now:\n"
        "• Type anything to search documents\n"
        "• /list — see recent files\n"
        "• /help — show all commands"
    )
```

Add `/help` command handler:

```python
async def _handle_help(update, context) -> None:
    chat_id = update.effective_chat.id
    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            "Send /auth first to link your account to AiHomeCloud."
        )
        return
    await update.message.reply_text(
        "🏠 AiHomeCloud Bot\n\n"
        "Commands:\n"
        "• /list — last 10 documents\n"
        "• /help — this message\n\n"
        "Search:\n"
        "• Type any word to search your files\n"
        "• Reply with a number to receive that file\n\n"
        "Examples: aadhaar, pan card, invoice, passport"
    )
```

Update `_handle_start` to always show the /auth prompt if not linked:

```python
async def _handle_start(update, context) -> None:
    chat_id = update.effective_chat.id
    first_name = update.effective_user.first_name or "there"

    if not await _is_allowed(chat_id):
        await update.message.reply_text(
            f"👋 Hi {first_name}! This is a private AiHomeCloud.\n\n"
            "Send /auth to link your Telegram account and get access."
        )
        return

    await update.message.reply_text(
        f"👋 Welcome back, {first_name}!\n\n"
        "Type anything to search your documents, or /help for all commands."
    )
```

Update `_handle_list` and `_handle_message` to use `await _is_allowed(chat_id)`
instead of the old synchronous `_is_allowed(chat_id)`. Change every occurrence:

```python
# Old (remove these):
if not _is_allowed(chat_id):

# New (replace with):
if not await _is_allowed(chat_id):
```

Register the new handlers inside `start_bot()`:

```python
# Add these two lines alongside the existing add_handler calls:
_application.add_handler(CommandHandler("auth", _handle_auth))
_application.add_handler(CommandHandler("help", _handle_help))
```

#### Implementation — telegram_routes.py

Remove `allowed_ids` from both models. Add `linked_count` to output:

```python
# Replace TelegramConfigIn:
class TelegramConfigIn(BaseModel):
    bot_token: str
    # allowed_ids removed — auth is now done via /auth command in Telegram

# Replace TelegramConfigOut:
class TelegramConfigOut(BaseModel):
    configured: bool
    token_preview: str
    linked_count: int       # number of Telegram accounts that have sent /auth
    bot_running: bool
```

Update `get_config` endpoint:

```python
@router.get("/config", response_model=TelegramConfigOut)
async def get_config(user: dict = Depends(require_admin)):
    saved: dict = await _store.get_value("telegram_config", default={})
    token = saved.get("bot_token", "") or settings.telegram_bot_token
    linked_ids = await _store.get_value("telegram_linked_ids", default=[])

    return TelegramConfigOut(
        configured=bool(token),
        token_preview=_mask_token(token) if token else "",
        linked_count=len(linked_ids),
        bot_running=_bot_is_running(),
    )
```

Update `save_config` endpoint — only save token, never touch linked_ids:

```python
@router.post("/config", status_code=status.HTTP_204_NO_CONTENT)
async def save_config(body: TelegramConfigIn, user: dict = Depends(require_admin)):
    token = body.bot_token.strip()
    if not token:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "bot_token must not be empty",
        )

    # Persist only the token — linked_ids are managed by /auth command
    await _store.set_value("telegram_config", {"bot_token": token})
    settings.telegram_bot_token = token  # type: ignore[misc]

    try:
        from ..telegram_bot import stop_bot, start_bot
        await stop_bot()
        await start_bot()
        logger.info("Telegram bot restarted via API config save")
    except Exception as exc:
        logger.warning("Telegram bot restart failed: %s", exc)
```

Also add an admin endpoint to unlink a specific chat_id if needed in future —
but leave it as a stub for now (not wired to UI yet):

```python
@router.delete("/linked/{chat_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unlink_account(chat_id: int, user: dict = Depends(require_admin)):
    """Unlink a Telegram account (admin only)."""
    ids = await _store.get_value("telegram_linked_ids", default=[])
    ids = [i for i in ids if int(i) != chat_id]
    await _store.set_value("telegram_linked_ids", ids)
```

#### Validation
  pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py

---

### TASK 12B — Flutter: simplify Telegram setup screen to token-only

#### Files to edit
- lib/screens/main/telegram_setup_screen.dart
- lib/services/api/services_network_api.dart

#### Implementation — services_network_api.dart

Update `saveTelegramConfig` to not take `allowedIds`:

```dart
/// POST /api/v1/telegram/config  body: {bot_token}
Future<void> saveTelegramConfig(String botToken) async {
  final res = await _withAutoRefresh(
    () => _client
        .post(
          Uri.parse('$_baseUrl${AppConstants.apiVersion}/telegram/config'),
          headers: _headers,
          body: jsonEncode({'bot_token': botToken}),
        )
        .timeout(ApiService._timeout),
  );
  _check(res);
}
```

Update `getTelegramConfig` to read `linked_count` instead of `allowed_ids`:
The return type is already `Map<String, dynamic>` so no model change needed —
just make sure the UI reads `cfg['linked_count']` not `cfg['allowed_ids']`.

#### Implementation — telegram_setup_screen.dart

Remove `_idsCtrl` controller and everything referencing it. Rewrite the screen:

State variables to keep: `_tokenCtrl`, `_obscureToken`, `_loading`, `_saving`,
`_botRunning`, `_configured`, `_errorMsg`

State variables to add: `int _linkedCount = 0`

State variables to remove: `_idsCtrl`

In `_loadConfig()`, replace:
```dart
// Remove:
_idsCtrl.text = cfg['allowed_ids'] as String? ?? '';
// Add:
_linkedCount = cfg['linked_count'] as int? ?? 0;
```

In `_save()`, update the call:
```dart
// Remove:
await ref.read(apiServiceProvider).saveTelegramConfig(token, ids);
// Replace with:
await ref.read(apiServiceProvider).saveTelegramConfig(token);
```

In `dispose()`, remove `_idsCtrl.dispose()`.

Replace the instructions card with a cleaner 3-step version:

```dart
AppCard(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Setup in 3 steps',
          style: GoogleFonts.sora(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      _stepText('1',
          'Open Telegram and search @BotFather'),
      _stepText('2',
          'Send /newbot — follow the steps and copy the token'),
      _stepText('3',
          'Paste the token below and tap Save. Then open your bot and send /auth to link your account.'),
    ],
  ),
),
```

Remove the entire "Allowed Chat IDs" section (label, hint text, TextField,
and its SizedBox spacers).

After the Save button, add a linked accounts status row (only shown when configured):

```dart
if (_configured) ...[
  const SizedBox(height: 20),
  AppCard(
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.people_rounded,
              color: AppColors.success, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _linkedCount == 0
                    ? 'No accounts linked yet'
                    : '$_linkedCount account${_linkedCount == 1 ? '' : 's'} linked',
                style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              if (_linkedCount == 0)
                Text(
                  'Open your bot in Telegram and send /auth',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    ),
  ),
],
```

#### Validation
  flutter analyze lib/screens/main/telegram_setup_screen.dart
  flutter analyze lib/services/api/services_network_api.dart

---

## Final validation — run all of these before done
  pytest -q backend/tests --ignore=backend/tests/test_hardware_integration.py
  flutter analyze
  flutter build apk --debug

## Commit when all pass
  git add -A
  git commit -m "feat: network status, StatTile fix, family→more, file explorer, Netflix picker, upload speed, telegram token-only setup + /auth auto-link, perf: keep-alive + folder cache, fix: upload stuck@100%, false disconnect"
