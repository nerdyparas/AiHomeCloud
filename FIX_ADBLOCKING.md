# Fix Ad Blocking — Audit, State Machine, and Working Toggle

## What is broken and why

**Root cause:** `adguard_enabled: bool = False` is the default in `config.py`.
Every call to `GET /api/v1/adguard/stats` hits `_require_enabled()` which
immediately raises HTTP 503 before contacting AdGuard at all.

The Flutter `_AdBlockingCardState._load()` catches any exception and sets
`_unavailable = true`. The card shows "Not configured — run install-adguard.sh"
and a refresh icon. When the user taps refresh, `_load()` runs again, gets the
same 503, sets `_unavailable = true` again, and re-renders identically.
Nothing visible happens — the button appears broken.

**Secondary problem:** The app cannot distinguish between three real states:

| State | Meaning | Right UI |
|---|---|---|
| A | Binary not installed | "Set up Ad Blocking" + setup instructions |
| B | Installed, service running, but `CUBIE_ADGUARD_ENABLED=false` | "Almost ready — finish setup" |
| C | Installed, enabled, AdGuard running | Stats card with toggle |

All three currently show the same "Not configured" text with a silent refresh.

---

## Architecture rules — never break these

- `friendlyError(e)` is the only error surface shown to users
- `settings.nas_root` / `settings.data_dir` — never hardcode paths
- `logger` not `print()` in backend
- No technical terms in user-facing strings — no systemd, no env vars, no port numbers
- `run_command()` always returns `(rc, stdout, stderr)` — always unpack all three
- All colours from `AppColors` — no hex literals inline
- All HTTP calls need `.timeout(ApiService._timeout)`

---

## Part A — Backend: add a status probe endpoint

### File: `backend/app/routes/adguard_routes.py`

Add this endpoint **before** the existing `/stats` endpoint.
It does NOT call `_require_enabled()` — it is the check that tells the app
whether setup has been completed at all.

```python
class AdGuardStatusResponse(BaseModel):
    installed: bool          # binary exists at /opt/AdGuardHome/AdGuardHome
    service_running: bool    # systemd AdGuardHome.service is active
    app_enabled: bool        # CUBIE_ADGUARD_ENABLED=true in config


@router.get("/status", response_model=AdGuardStatusResponse)
async def get_adguard_status(user: dict = Depends(get_current_user)):
    """
    Returns AdGuard installation state without requiring adguard_enabled=True.
    Used by the app to determine which UI state to show.
    Never raises 503 — always returns a response.
    """
    from pathlib import Path
    import asyncio

    # Check binary
    agh_bin = Path("/opt/AdGuardHome/AdGuardHome")
    installed = agh_bin.exists()

    # Check service — run as non-blocking subprocess
    service_running = False
    if installed:
        rc, _, _ = await run_command(
            ["systemctl", "is-active", "--quiet", "AdGuardHome"],
            timeout=5,
        )
        service_running = (rc == 0)

    return AdGuardStatusResponse(
        installed=installed,
        service_running=service_running,
        app_enabled=settings.adguard_enabled,
    )
```

Add the import at the top of the file (if not already present):
```python
from ..subprocess_runner import run_command
```

### Why this approach

The status endpoint never calls `_require_enabled()` so it always returns
200 with a JSON body. The app calls this first, then decides which of the
three UI states to render. Only state C calls `/stats`.

---

## Part B — Flutter: new API method

### File: `lib/services/api/services_network_api.dart`

Add after the existing AdGuard methods:

```dart
/// GET /api/v1/adguard/status — does NOT require adguard to be configured
/// Returns {installed, service_running, app_enabled}
Future<Map<String, dynamic>> getAdGuardStatus() async {
  final res = await _withAutoRefresh(
    () => _client
        .get(
          Uri.parse('$_baseUrl${AppConstants.apiVersion}/adguard/status'),
          headers: _headers,
        )
        .timeout(ApiService._timeout),
  );
  _check(res);
  return jsonDecode(res.body) as Map<String, dynamic>;
}
```

---

## Part C — Flutter: rewrite `_AdBlockingCard`

### File: `lib/screens/main/more_screen.dart`

Replace the entire `_AdBlockingCardState` class body with the version below.
The widget declaration (`_AdBlockingCard extends ConsumerStatefulWidget`)
and `_PauseButton` class remain untouched.

#### New state variables

```dart
class _AdBlockingCardState extends ConsumerState<_AdBlockingCard> {
  // Status probe result
  bool? _installed;        // null = not yet loaded
  bool? _serviceRunning;
  bool? _appEnabled;

  // Stats (only loaded when appEnabled == true)
  Map<String, dynamic>? _stats;

  bool _loading = true;
  String? _errorMessage;   // shown in snackbar, not in card body
```

#### New `_load()` method — two-step

```dart
@override
void initState() {
  super.initState();
  _load();
}

Future<void> _load() async {
  if (!mounted) return;
  setState(() {
    _loading = true;
    _errorMessage = null;
  });

  try {
    // Step 1: always fetch status first (never 503)
    final status =
        await ref.read(apiServiceProvider).getAdGuardStatus();

    if (!mounted) return;

    final installed = status['installed'] as bool? ?? false;
    final serviceRunning = status['service_running'] as bool? ?? false;
    final appEnabled = status['app_enabled'] as bool? ?? false;

    setState(() {
      _installed = installed;
      _serviceRunning = serviceRunning;
      _appEnabled = appEnabled;
    });

    // Step 2: only fetch stats if fully configured
    if (installed && serviceRunning && appEnabled) {
      final stats =
          await ref.read(apiServiceProvider).getAdGuardStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } else {
      if (mounted) setState(() => _loading = false);
    }
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _errorMessage = friendlyError(e);
    });
    // Show the actual error in a snackbar — never silently swallow
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_errorMessage!)),
    );
  }
}
```

#### New `build()` — three distinct UI states

```dart
@override
Widget build(BuildContext context) {
  // ── Loading ────────────────────────────────────────────────────────
  if (_loading) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: _iconBox(Icons.shield_rounded, AppColors.primary),
        title: Text('Ad Blocking',
            style: GoogleFonts.dmSans(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        trailing: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.primary),
        ),
      ),
    );
  }

  // ── State A: not installed ─────────────────────────────────────────
  if (_installed == false) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: _iconBox(Icons.shield_outlined, AppColors.textMuted),
        title: Text('Ad Blocking',
            style: GoogleFonts.dmSans(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        subtitle: Text(
          'Not set up on this device',
          style: GoogleFonts.dmSans(
              color: AppColors.textMuted, fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.info_outline_rounded,
              color: AppColors.primary, size: 20),
          tooltip: 'Setup instructions',
          onPressed: _showSetupInstructions,
        ),
      ),
    );
  }

  // ── State B: installed but backend flag not set ────────────────────
  if (_appEnabled == false) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: _iconBox(Icons.shield_rounded, const Color(0xFFE8A84C)),
        title: Text('Ad Blocking',
            style: GoogleFonts.dmSans(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        subtitle: Text(
          'Installed — finish setup to activate',
          style: GoogleFonts.dmSans(
              color: const Color(0xFFE8A84C), fontSize: 12),
        ),
        trailing: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE8A84C), // amber dot
          ),
        ),
        onTap: _showSetupInstructions,
      ),
    );
  }

  // ── State B variant: installed + enabled but service not running ───
  if (_serviceRunning == false) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: _iconBox(Icons.shield_rounded, AppColors.error),
        title: Text('Ad Blocking',
            style: GoogleFonts.dmSans(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        subtitle: Text(
          'Service stopped',
          style: GoogleFonts.dmSans(
              color: AppColors.error, fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.refresh_rounded,
              color: AppColors.primary, size: 20),
          tooltip: 'Retry',
          onPressed: _load,
        ),
      ),
    );
  }

  // ── State C: fully working — stats card ───────────────────────────
  final blocked = _stats?['blocked_today'] as int? ?? 0;
  final queries = _stats?['dns_queries'] as int? ?? 0;
  final percent = _stats?['blocked_percent'] as double? ?? 0.0;
  final topBlocked =
      (_stats?['top_blocked'] as List<dynamic>? ?? []).cast<String>();
  final protectionEnabled =
      _stats?['protection_enabled'] as bool? ?? true;

  return AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            _iconBox(Icons.shield_rounded,
                protectionEnabled ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ad Blocking',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  Text(
                    protectionEnabled
                        ? '$blocked of $queries blocked today'
                            ' (${percent.toStringAsFixed(0)}%)'
                        : 'Protection paused',
                    style: GoogleFonts.dmSans(
                        color: protectionEnabled
                            ? AppColors.textSecondary
                            : AppColors.error,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            // Refresh
            GestureDetector(
              onTap: _load,
              child: const Icon(Icons.refresh_rounded,
                  color: AppColors.textMuted, size: 18),
            ),
          ],
        ),

        // Top blocked domains
        if (topBlocked.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Top blocked:',
              style: GoogleFonts.dmSans(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: topBlocked.take(5).map((domain) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.cardBorder.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(domain,
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary,
                        fontSize: 11)),
              );
            }).toList(),
          ),
        ],

        // Pause buttons + admin toggle
        const SizedBox(height: 12),
        Row(
          children: [
            _PauseButton(minutes: 5),
            const SizedBox(width: 8),
            _PauseButton(minutes: 30),
            const SizedBox(width: 8),
            _PauseButton(minutes: 60),
            if (widget.isAdmin) ...[
              const Spacer(),
              Text('On',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(width: 4),
              Switch(
                value: protectionEnabled,
                onChanged: _toggle,
                activeThumbColor: AppColors.primary,
              ),
            ],
          ],
        ),
      ],
    ),
  );
}
```

#### `_toggle` and `_showSetupInstructions`

```dart
Future<void> _toggle(bool enabled) async {
  try {
    await ref.read(apiServiceProvider).toggleAdGuard(enabled);
    await _load();
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

void _showSetupInstructions() {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Set Up Ad Blocking',
          style: GoogleFonts.sora(color: AppColors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ad Blocking blocks ads and trackers for every device on '
            'your home network — phones, TVs, and computers.',
            style: GoogleFonts.dmSans(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5),
          ),
          const SizedBox(height: 16),
          Text('To enable it:',
              style: GoogleFonts.dmSans(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _setupStep(
            '1',
            'Open a terminal and connect to your AiHomeCloud device over SSH',
          ),
          const SizedBox(height: 8),
          _setupStep(
            '2',
            'Run:  sudo bash scripts/install-adguard.sh',
            isCode: true,
          ),
          const SizedBox(height: 8),
          _setupStep(
            '3',
            'Point your router\'s DNS to this device\'s IP address — '
            'the script will print exact instructions when it finishes',
          ),
          const SizedBox(height: 8),
          _setupStep(
            '4',
            'Come back here and tap the refresh icon',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Got it',
              style: GoogleFonts.dmSans(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

Widget _setupStep(String number, String text, {bool isCode = false}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(number,
              style: GoogleFonts.dmSans(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: isCode
              ? GoogleFonts.robotoMono(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  backgroundColor:
                      AppColors.cardBorder.withValues(alpha: 0.5),
                )
              : GoogleFonts.dmSans(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4),
        ),
      ),
    ],
  );
}

Widget _iconBox(IconData icon, Color color) => Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 18),
    );
```

---

## Part D — Backend test

### File: `backend/tests/test_adguard.py`

Create this file:

```python
"""Tests for AdGuard status and proxy endpoints."""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock


@pytest.mark.asyncio
async def test_status_not_installed(client, admin_token):
    """When binary is absent, installed=False, others False."""
    with patch("pathlib.Path.exists", return_value=False):
        resp = await client.get(
            "/api/v1/adguard/status",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
    assert resp.status_code == 200
    data = resp.json()
    assert data["installed"] is False
    assert data["service_running"] is False


@pytest.mark.asyncio
async def test_status_installed_service_running(client, admin_token):
    """When binary exists and service is active, reflect that correctly."""
    with (
        patch("pathlib.Path.exists", return_value=True),
        patch(
            "backend.app.subprocess_runner.run_command",
            new_callable=AsyncMock,
            return_value=(0, "", ""),
        ),
    ):
        resp = await client.get(
            "/api/v1/adguard/status",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
    assert resp.status_code == 200
    assert resp.json()["service_running"] is True


@pytest.mark.asyncio
async def test_stats_returns_503_when_disabled(client, admin_token):
    """stats endpoint still returns 503 when adguard_enabled=False."""
    resp = await client.get(
        "/api/v1/adguard/stats",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert resp.status_code == 503


@pytest.mark.asyncio
async def test_status_requires_auth(client):
    """status endpoint requires a valid JWT."""
    resp = await client.get("/api/v1/adguard/status")
    assert resp.status_code == 401
```

---

## Validation

```bash
# Backend
python3 -m py_compile backend/app/routes/adguard_routes.py && echo OK
pytest -q backend/tests/test_adguard.py --ignore=backend/tests/test_hardware_integration.py

# Flutter
flutter analyze lib/screens/main/more_screen.dart
flutter analyze lib/services/api/services_network_api.dart
flutter build apk --debug
```

## Manual test checklist

**State A — AdGuard not installed:**
- Card shows "Not set up on this device" subtitle ✅
- Info icon visible on right ✅
- Tapping card or info icon opens setup instructions dialog ✅
- Dialog shows 4 numbered steps with the install command in monospace ✅
- Refresh icon not shown (no point retrying) ✅

**State B — Installed but backend flag off:**
- Card shows amber dot indicator ✅
- Subtitle says "Installed — finish setup to activate" in amber ✅
- Tapping card opens the setup instructions dialog ✅
- No stats shown ✅

**State B variant — Service stopped:**
- Card shows red "Service stopped" subtitle ✅
- Refresh icon visible and tappable ✅
- Tapping refresh shows spinner then updates state ✅

**State C — Fully working:**
- Stats show "X of Y blocked today (Z%)" ✅
- Top blocked domains shown as chips ✅
- Pause 5m / 30m / 1h buttons work, snackbar confirms ✅
- Admin toggle switches protection on/off, subtitle updates ✅
- Small refresh icon in top-right reloads stats ✅

**Retry button (was broken):**
- In any error state, tapping refresh shows a spinner ✅
- On failure, a snackbar shows the actual error message ✅
- Never silently swallows errors ✅
