# Dashboard: Remove Redundant Badge, Windows-Style Storage Bar, Compact Stat Tiles

## What to change — three isolated tasks, do them in order

---

## Task 1 — Remove the active storage badge below the search bar

### File: `lib/screens/main/dashboard_screen.dart`

Find the `SliverToBoxAdapter` that renders the green/amber badge just below the
search bar. It starts with this comment:

```dart
// ── Active storage badge / no-drive indicator (POL-01) ────────
SliverToBoxAdapter(
  child: storageAsync.when(
    data: (devices) {
      final activeDevices = ...
```

**Delete this entire `SliverToBoxAdapter` block** including all its `data`,
`loading`, and `error` branches. The "Connect a USB drive" prompt that appears
when no drive is detected (the amber/blue warning) is also inside this block —
remove it too. The storage section below already communicates both states
(active drive and empty state).

Do not touch anything else — only remove this one `SliverToBoxAdapter`.

---

## Task 2 — Windows-style storage card with progress bar

### File: `lib/screens/main/dashboard_screen.dart`

The `_StorageDeviceTile` widget at the bottom of the file currently shows:
- Device icon + name
- Type label and total size ("USB Drive  •  57.8 GB")
- Active/Ready badge + chevron

It does not show free space or used/free ratio.

Replace the entire `_StorageDeviceTile` class with the version below. It adds:
- A horizontal filled progress bar (blue = used, surface = free) — Windows style
- Used GB and free GB text below the bar
- Keeps all existing info (name, type, status badge, chevron)

```dart
class _StorageDeviceTile extends StatelessWidget {
  final StorageDevice device;
  final double? usedGB;    // null when StorageStats not yet available
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

    // Bar colour shifts to amber above 80%, red above 95%
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
          // ── Top row: icon + name + status badge + chevron ────────────────
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

          // ── Storage bar (only when stats available) ───────────────────────
          if (usedFraction != null) ...[
            const SizedBox(height: 14),

            // Progress bar
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

            // Used / Free text
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
            // No stats yet — show total size as before
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

### Pass storage stats into _StorageDeviceTile

The tile now needs `usedGB` and `totalGB`. These come from `statsAsync`
(the `systemStatsStreamProvider` already watched on the dashboard).

In the dashboard `build()` method, find the storage card builder that calls
`_StorageDeviceTile(device: show[i])` and update it to:

```dart
// Inside the storageAsync.when data: branch, where show[i] is built:
_StorageDeviceTile(
  device: show[i],
  // Pass stats only for the active NAS device — others show no bar
  usedGB: show[i].isNasActive
      ? statsAsync.value?.storage.usedGB
      : null,
  totalGB: show[i].isNasActive
      ? statsAsync.value?.storage.totalGB
      : null,
)
```

`statsAsync.value?.storage` is `StorageStats` which already has `usedGB` and
`totalGB` fields — no backend changes needed.

---

## Task 3 — Compact stat tiles: two-column layout

### File: `lib/widgets/stat_tile.dart`

Restructure the tile so the icon+label are on the left and the value+unit+helper
are on the right. This eliminates the blank right-side space and reduces tile
height so the 2×2 grid takes less vertical space on the dashboard.

Replace the entire `StatTile.build()` method with:

```dart
@override
Widget build(BuildContext context) {
  final colour = accentColor ?? AppColors.primary;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder, width: 1),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Left: icon + label ────────────────────────────────────────────
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colour.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: colour, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.dmSans(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),

        const Spacer(),

        // ── Right: value + unit + helper ──────────────────────────────────
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: GoogleFonts.sora(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 2),
                  Text(
                    unit!,
                    style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            if (helperText != null) ...[
              const SizedBox(height: 2),
              Text(
                helperText!,
                style: GoogleFonts.dmSans(
                  color: helperColor ?? AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}
```

### Also update the grid aspect ratio in dashboard_screen.dart

Find:
```dart
childAspectRatio: 1.25,
```

Change to:
```dart
childAspectRatio: 1.7,
```

The tiles are now wider than tall — this fits the new horizontal layout and
reduces the total height of the 2×2 grid.

---

## Validation

```bash
flutter analyze lib/widgets/stat_tile.dart
flutter analyze lib/screens/main/dashboard_screen.dart
flutter build apk --debug
```

## Manual test checklist

**Badge removal:**
- Green USB_DISK badge below search bar is gone ✅
- "Connect a USB drive" warning below search bar is gone ✅
- Storage section below still shows correctly ✅

**Storage bar:**
- Active NAS device card now shows a blue horizontal bar ✅
- Bar fills proportionally to used/free ratio ✅
- "X.X GB used" on left, "X.X GB free" on right below bar ✅
- Bar turns amber above 80% used, red above 95% ✅
- Non-active drives (no stats available) show no bar, just total size ✅

**Stat tiles:**
- Icon+label on left, value+helper on right within each tile ✅
- Numbers still large and readable ✅
- "Normal" / "Hot" / "High" helper text still colour-coded ✅
- 2×2 grid is noticeably shorter vertically than before ✅
- No content clipped or overflowing ✅
