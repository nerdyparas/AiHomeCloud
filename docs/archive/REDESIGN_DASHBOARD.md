# Dashboard Redesign — Implement New Layout

## Reference design

The new dashboard has this exact scroll order:
1. Hero status card (replaces greeting)
2. Storage section + device card with progress bar
3. System compact single-row card
4. Network combined card (connectivity + speed in one)
5. Bottom nav unchanged

The user avatar (letter initial) stays top-right. Search bar stays below the
hero card. Ad blocking badge stays where it is. Nothing else changes.

---

## Architecture rules — never break these

- `friendlyError(e)` is the only error surface shown to users
- No hardcoded paths or IPs
- `logger` not `print()` in backend
- All colours from `AppColors` — do not introduce new hex literals inline

Add these two colour constants to `lib/core/theme.dart` if not already present:
```dart
static const Color surface = Color(0xFF161B22);   // card background
static const Color cardBorder = Color(0xFF21262D); // border
```

---

## Task 1 — Replace greeting with Hero Status Card

### File: `lib/screens/main/dashboard_screen.dart`

#### Remove the current header block

Find and delete this entire `SliverToBoxAdapter`:
```dart
// ── Header ──────────────────────────────────────────────────────
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: Row(
      children: [
        Expanded(
          child: Column( ...  'Hey, $userName 👋' ... ),
        ),
        Container( ... avatar circle ... ),
      ],
    ).animate().fadeIn(duration: 400.ms),
  ),
),
```

#### Replace with new header + hero card

```dart
// ── Top bar: avatar only ─────────────────────────────────────────
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: Row(
      children: [
        const Spacer(),
        GestureDetector(
          onTap: () => context.go('/user-picker',
              extra: ref.read(apiServiceProvider).host),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                style: GoogleFonts.sora(
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms),
  ),
),

// ── Hero status card ─────────────────────────────────────────────
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: _HeroStatusCard(
      deviceAsync: deviceAsync,
      statsAsync: statsAsync,
    ),
  ),
),
```

#### Add _HeroStatusCard widget at the bottom of the file

```dart
class _HeroStatusCard extends StatelessWidget {
  final AsyncValue deviceAsync;
  final AsyncValue statsAsync;

  const _HeroStatusCard({
    required this.deviceAsync,
    required this.statsAsync,
  });

  @override
  Widget build(BuildContext context) {
    final stats = statsAsync.valueOrNull;
    final device = deviceAsync.valueOrNull;

    // Determine overall health
    final cpuHigh = (stats?.cpuPercent ?? 0) >= 80;
    final ramHigh = (stats?.ramPercent ?? 0) >= 85;
    final tempHigh = (stats?.tempCelsius ?? 0) >= 65;
    final allGood = !cpuHigh && !ramHigh && !tempHigh;

    final statusColor = allGood ? AppColors.success : AppColors.error;
    final statusText = allGood
        ? 'Everything is running fine'
        : [
            if (cpuHigh) 'CPU high',
            if (ramHigh) 'RAM high',
            if (tempHigh) 'Temperature high',
          ].join('  ·  ');

    // Subtitle line: uptime · temp · connection
    final uptimePart = stats != null ? _uptime(stats.uptime) : '—';
    final tempPart = stats != null
        ? '${stats.tempCelsius.toStringAsFixed(0)}°C'
        : '—';
    // Connection: prefer LAN label from network, fall back to generic
    const connPart = 'LAN';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allGood
              ? AppColors.success.withValues(alpha: 0.35)
              : AppColors.error.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.06),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Text block
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      device?.name ?? 'AiHomeCloud',
                      style: GoogleFonts.sora(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  statusText,
                  style: GoogleFonts.dmSans(
                    color: statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Uptime $uptimePart  ·  $tempPart  ·  $connPart',
                  style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms);
  }

  String _uptime(Duration d) {
    final days = d.inDays;
    final hrs = d.inHours.remainder(24);
    final mins = d.inMinutes.remainder(60);
    if (days > 0) return '${days}d ${hrs}h';
    if (hrs > 0) return '${hrs}h ${mins}m';
    return '${mins}m';
  }
}
```

#### Remove the old _uptime helper from _DashboardScreenState

The `_uptime` method is now inside `_HeroStatusCard`. Delete the duplicate
from `_DashboardScreenState`.

---

## Task 2 — Remove the active storage badge below search bar

Find and delete the entire `SliverToBoxAdapter` block that starts with:
```dart
// ── Active storage badge / no-drive indicator (POL-01) ────────
```

Delete it in full including all its `data`, `loading`, `error` branches.

---

## Task 3 — Storage card with Windows-style progress bar

Replace the entire `_StorageDeviceTile` class with:

```dart
class _StorageDeviceTile extends StatelessWidget {
  final StorageDevice device;
  final double? usedGB;
  final double? totalGB;

  const _StorageDeviceTile({
    required this.device,
    this.usedGB,
    this.totalGB,
  });

  @override
  Widget build(BuildContext context) {
    final usedFraction = (usedGB != null && totalGB != null && totalGB! > 0)
        ? (usedGB! / totalGB!).clamp(0.0, 1.0)
        : null;
    final freeGB = (usedGB != null && totalGB != null)
        ? (totalGB! - usedGB!).clamp(0.0, totalGB!)
        : null;

    final barColor = usedFraction == null
        ? AppColors.primary
        : usedFraction >= 0.95
            ? AppColors.error
            : usedFraction >= 0.80
                ? const Color(0xFFE8A84C)
                : AppColors.primary;

    return AppCard(
      glowing: device.isNasActive,
      onTap: () => context.push('/storage-explorer'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(device.icon, color: _color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.label ?? device.model ?? device.name,
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.typeLabel,
                      style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_statusText,
                    style: GoogleFonts.dmSans(
                        color: _statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted, size: 18),
            ],
          ),

          if (usedFraction != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: usedFraction,
                minHeight: 6,
                backgroundColor: AppColors.surface,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${usedGB!.toStringAsFixed(1)} GB used',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  '${freeGB!.toStringAsFixed(1)} GB free',
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              device.sizeDisplay,
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Color get _color => switch (device.transport) {
        'usb' => AppColors.primary,
        'nvme' => AppColors.secondary,
        _ => AppColors.textSecondary,
      };

  String get _statusText {
    if (device.isNasActive) return 'Active';
    if (device.mounted) return 'Activated';
    if (device.fstype == null) return 'Not ready yet';
    return 'Ready';
  }

  Color get _statusColor {
    if (device.isNasActive) return AppColors.success;
    if (device.mounted) return AppColors.secondary;
    if (device.fstype == null) return AppColors.primary;
    return AppColors.textSecondary;
  }
}
```

Update the call site inside the storage builder to pass stats:
```dart
_StorageDeviceTile(
  device: show[i],
  usedGB: show[i].isNasActive ? statsAsync.value?.storage.usedGB : null,
  totalGB: show[i].isNasActive ? statsAsync.value?.storage.totalGB : null,
)
```

---

## Task 4 — System: collapse 2×2 grid into one compact card

### Remove the existing SliverGrid block

Find and delete:
```dart
// ── Compact stat tiles (2x2 grid) ──────────────────────────────
SliverPadding(
  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
  sliver: statsAsync.when( ...SliverGrid.count... ),
),
```

Delete the entire `SliverPadding` including the `statsAsync.when` inside it.

### Replace with a single compact row card

```dart
// ── System compact row ──────────────────────────────────────────
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: statsAsync.when(
      data: (s) => _SystemCompactCard(stats: s).animate().fadeIn(delay: 200.ms),
      loading: () => const SizedBox(height: 52),
      error: (e, __) => AppCard(
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(friendlyError(e),
                  style: GoogleFonts.dmSans(
                      color: AppColors.error, fontSize: 13)),
            ),
            TextButton(
              onPressed: () => ref.invalidate(systemStatsStreamProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
  ),
),
```

### Add _SystemCompactCard widget at the bottom of the file

```dart
class _SystemCompactCard extends StatelessWidget {
  final SystemStats stats;
  const _SystemCompactCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cpuOk = stats.cpuPercent < 80;
    final ramOk = stats.ramPercent < 85;
    final tempOk = stats.tempCelsius < 65;

    return AppCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.memory_rounded,
                color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary, fontSize: 13),
                children: [
                  _statSpan(
                      'CPU ${stats.cpuPercent.toStringAsFixed(0)}%', cpuOk),
                  _sep(),
                  _statSpan(
                      'RAM ${stats.ramPercent.toStringAsFixed(0)}%', ramOk),
                  _sep(),
                  _statSpan(
                      '${stats.tempCelsius.toStringAsFixed(0)}°C', tempOk),
                  _sep(),
                  TextSpan(
                    text: _uptime(stats.uptime),
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 18),
        ],
      ),
    );
  }

  InlineSpan _statSpan(String text, bool ok) => TextSpan(
        text: text,
        style: GoogleFonts.dmSans(
          color: ok ? AppColors.textPrimary : AppColors.error,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );

  InlineSpan _sep() => TextSpan(
        text: '  ·  ',
        style: GoogleFonts.dmSans(
            color: AppColors.textMuted, fontSize: 13),
      );

  String _uptime(Duration d) {
    final days = d.inDays;
    final hrs = d.inHours.remainder(24);
    final mins = d.inMinutes.remainder(60);
    if (days > 0) return '${days}d ${hrs}h';
    if (hrs > 0) return '${hrs}h ${mins}m';
    return '${mins}m';
  }
}
```

---

## Task 5 — Network: merge speed row into the connectivity card

### Find the network speed card

Find this `SliverToBoxAdapter`:
```dart
// ── Network speed card ──────────────────────────────────────────
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
    child: statsAsync.when( ... Upload/Download row ... ),
  ),
),
```

Delete this entire block.

### Update _NetworkStatusCard to include speed at the bottom

Find `_NetworkStatusCard` widget. Inside its `data:` branch, after the
Bluetooth row, add a divider and the speed row:

```dart
// After the Bluetooth _netStatusRow, still inside the AppCard Column:
const Divider(color: AppColors.cardBorder, height: 1),
Consumer(
  builder: (context, ref, _) {
    final statsAsync = ref.watch(systemStatsStreamProvider);
    return statsAsync.when(
      data: (s) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: _speedCol(
                Icons.arrow_upward_rounded,
                'Upload',
                '${s.networkUpMbps.toStringAsFixed(1)} Mbps',
                AppColors.success,
              ),
            ),
            Container(
                width: 1, height: 36, color: AppColors.cardBorder),
            Expanded(
              child: _speedCol(
                Icons.arrow_downward_rounded,
                'Download',
                '${s.networkDownMbps.toStringAsFixed(1)} Mbps',
                AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
      loading: () => const SizedBox(height: 44),
      error: (_, __) => const SizedBox.shrink(),
    );
  },
),
```

Add `_speedCol` as a method on `_NetworkStatusCard`:
```dart
Widget _speedCol(IconData icon, String label, String value, Color c) {
  return Column(
    children: [
      Icon(icon, color: c, size: 18),
      const SizedBox(height: 4),
      Text(value,
          style: GoogleFonts.sora(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
      Text(label,
          style: GoogleFonts.dmSans(
              color: AppColors.textSecondary, fontSize: 11)),
    ],
  );
}
```

Update the bottom padding on the Network status card from `10` to `0` since
the speed row now lives inside it. Find the last network `SliverToBoxAdapter`
padding and change `bottom: 24` to `bottom: 24` on the outer wrapper — no
change needed there, the inner card handles its own spacing.

---

## Cleanup

After all tasks are done, check for any orphaned helper methods in
`_DashboardScreenState` that are no longer used:

- `_uptime()` — now lives in `_HeroStatusCard` and `_SystemCompactCard`, delete from state class
- `_healthLabel()` — no longer used, delete
- `_healthColor()` — no longer used, delete
- `_netCol()` — replaced by `_speedCol` inside `_NetworkStatusCard`, delete

---

## Validation

```bash
flutter analyze lib/screens/main/dashboard_screen.dart
flutter build apk --debug
```

## Manual test checklist

- Hero card shows green dot + "Everything is running fine" when all stats normal ✅
- Hero card shows red dot + specific issue when CPU/RAM/temp is high ✅
- Subtitle line shows uptime + temp + LAN ✅
- Avatar top-right shows user initial, no greeting text ✅
- Green USB badge below search bar is gone ✅
- Storage card shows blue progress bar with used/free GB ✅
- System section is a single compact row card, not a 2×2 grid ✅
- CPU/RAM/temp values turn red in the row when elevated ✅
- Network section is one card with connectivity rows + speed row at bottom ✅
- Separate network speed card is gone ✅
- Total dashboard scrolls noticeably shorter than before ✅
