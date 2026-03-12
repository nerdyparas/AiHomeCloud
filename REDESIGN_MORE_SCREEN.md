# More Screen Redesign — Clean Grouped Layout

## What is changing and why

Current screen has 9 section headers for 9 items — every item got its own
category. Chrome outnumbers content. The redesign groups by user intent into
4 cards + a minimal footer, reducing section headers from 9 to 4 and cutting
scroll length by roughly half.

New structure:
1. **Profile card** — avatar, name, Change PIN row (replaces cold "Account" section)
2. **Sharing card** — TV Sharing + Remote Access + Telegram Bot (admin only)
3. **Privacy & Security card** — Ad Blocking + Server Certificate + Trash
4. **Family & Storage card** — Family Members + Storage Drive + Device (admin only)
5. **Footer** — "AiHomeCloud v1.0.0" small text + Log Out + Restart/Shutdown (admin only)

## What must NOT change

- All dialog methods: `_verifyServerCertificate`, `_changePin`, `_confirmReboot`,
  `_confirmShutdown`, `_confirmLogout`, `_performReboot`, `_performShutdown` —
  copy them verbatim into the new file, zero changes
- `_TailscaleCard` widget — keep entirely, just move inside Sharing card
- `_AdBlockingCard` widget and `_PauseButton` — keep entirely, move inside Privacy card
- `_TrashCard` widget — keep entirely, move inside Privacy card
- All admin visibility rules (`if (isAdmin)`) — same conditions, same items
- All provider watches: `servicesProvider`, `tailscaleStatusProvider`,
  `certFingerprintProvider`, `authSessionProvider`
- `friendlyError(e)` is the only error surface shown to users
- No hardcoded paths or IPs
- All colours from `AppColors` — no new hex literals inline

---

## New _MoreScreenState.build() method

Replace the entire `build()` method body with the following. All helper
methods (`_sectionLabel`, `_divider`, `_iconBox`, `_navTile`) and all dialog
methods stay in the class unchanged.

```dart
@override
Widget build(BuildContext context) {
  final session = ref.watch(authSessionProvider);
  final isAdmin = session?.isAdmin ?? false;
  final userName = session?.username ?? 'User';
  final fingerprint = ref.watch(certFingerprintProvider);
  final servicesAsync = ref.watch(servicesProvider);
  final tailscaleAsync = ref.watch(tailscaleStatusProvider);

  return Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          const SizedBox(height: 16),

          // ── Screen title ────────────────────────────────────────────────
          Text('More',
              style: GoogleFonts.sora(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700))
              .animate()
              .fadeIn(duration: 400.ms),

          const SizedBox(height: 20),

          // ── 1. PROFILE CARD ─────────────────────────────────────────────
          _ProfileCard(
            userName: userName,
            onChangePinTap: _changePin,
          ).animate().fadeIn(delay: 50.ms),

          const SizedBox(height: 8),
          _sectionLabel('Sharing'),
          const SizedBox(height: 8),

          // ── 2. SHARING CARD ──────────────────────────────────────────────
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [

                // TV & Computer Sharing — toggle row
                servicesAsync.when(
                  data: (services) {
                    final media = services.cast<ServiceInfo?>().firstWhere(
                        (s) => s?.id == 'media',
                        orElse: () => null);

                    if (media == null) {
                      return ListTile(
                        leading: _iconBox(
                            Icons.tv_rounded, AppColors.secondary),
                        title: Text('TV & Computer Sharing',
                            style: GoogleFonts.dmSans(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                        subtitle: Text('Not available',
                            style: GoogleFonts.dmSans(
                                color: AppColors.textMuted, fontSize: 12)),
                        trailing: const Icon(Icons.info_outline_rounded,
                            color: AppColors.textMuted, size: 18),
                      );
                    }

                    return ListTile(
                      leading:
                          _iconBox(Icons.tv_rounded, AppColors.secondary),
                      title: Text('TV & Computer Sharing',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text(
                          media.isEnabled
                              ? 'DLNA + SMB active'
                              : 'Stream to TVs and computers',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textSecondary, fontSize: 12)),
                      trailing: Switch(
                        value: media.isEnabled,
                        onChanged: (v) async {
                          try {
                            await ref
                                .read(apiServiceProvider)
                                .toggleService(media.id, v);
                            ref.invalidate(servicesProvider);
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(friendlyError(e))),
                              );
                            }
                          }
                        },
                        activeThumbColor: AppColors.primary,
                      ),
                    );
                  },
                  loading: () => ListTile(
                    leading:
                        _iconBox(Icons.tv_rounded, AppColors.secondary),
                    title: Text('TV & Computer Sharing',
                        style: GoogleFonts.dmSans(
                            color: AppColors.textPrimary, fontSize: 14)),
                    trailing: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  ),
                  error: (e, _) => ListTile(
                    leading: _iconBox(
                        Icons.tv_rounded, AppColors.textSecondary),
                    title: Text('TV & Computer Sharing',
                        style: GoogleFonts.dmSans(
                            color: AppColors.textPrimary, fontSize: 14)),
                    subtitle: Text(friendlyError(e),
                        style: GoogleFonts.dmSans(
                            color: AppColors.textMuted, fontSize: 12)),
                    // Amber dot instead of loud retry icon
                    trailing: GestureDetector(
                      onTap: () => ref.invalidate(servicesProvider),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFE8A84C),
                        ),
                      ),
                    ),
                  ),
                ),

                _divider(),

                // Remote Access (Tailscale) — existing card inlined as ListTile
                _TailscaleRow(
                    isAdmin: isAdmin, statusAsync: tailscaleAsync),

                _divider(),

                // Telegram Bot (admin only)
                if (isAdmin)
                  ListTile(
                    leading: _iconBox(
                        Icons.send_rounded, AppColors.primary),
                    title: Text('Telegram Bot',
                        style: GoogleFonts.dmSans(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    subtitle: Text('Send files from anywhere',
                        style: GoogleFonts.dmSans(
                            color: AppColors.textSecondary, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                    onTap: () => context.push('/telegram-setup'),
                  ),

                // If not admin, no Telegram row — no divider needed
              ],
            ),
          ).animate().fadeIn(delay: 80.ms),

          const SizedBox(height: 8),
          _sectionLabel('Privacy & Security'),
          const SizedBox(height: 8),

          // ── 3. PRIVACY & SECURITY CARD ───────────────────────────────────
          // Ad Blocking uses its own rich widget — embed it here
          // When configured: shows stats inline. When not: shows subtitle + dot.
          _AdBlockingCard(isAdmin: isAdmin).animate().fadeIn(delay: 110.ms),

          const SizedBox(height: 4),

          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [

                // Server Certificate
                ListTile(
                  leading: _iconBox(
                      Icons.verified_user_rounded, AppColors.success),
                  title: Text('Server Certificate',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    fingerprint != null
                        ? fingerprint.toUpperCase()
                        : 'Not pinned yet',
                    style: GoogleFonts.dmSans(
                        color: fingerprint != null
                            ? AppColors.textSecondary
                            : AppColors.textMuted,
                        fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 20),
                  onTap: () => _verifyServerCertificate(fingerprint),
                ),

                _divider(),

                // Change PIN
                ListTile(
                  leading:
                      _iconBox(Icons.lock_rounded, AppColors.textSecondary),
                  title: Text('Change PIN',
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 20),
                  onTap: _changePin,
                ),

                _divider(),

                // Trash — inline using existing _TrashCard logic as a ListTile
                const _TrashCard(),

              ],
            ),
          ).animate().fadeIn(delay: 120.ms),

          const SizedBox(height: 8),
          _sectionLabel('Family & Storage'),
          const SizedBox(height: 8),

          // ── 4. FAMILY & STORAGE CARD ─────────────────────────────────────
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [

                // Family Members
                _navTile(
                  icon: Icons.people_rounded,
                  color: const Color(0xFFE8A84C),
                  title: 'Family Members',
                  subtitle: 'Manage users and storage',
                  onTap: () => context.go('/family'),
                ),

                _divider(),

                // Storage Drive
                _navTile(
                  icon: Icons.storage_rounded,
                  color: AppColors.secondary,
                  title: 'Storage Drive',
                  subtitle: 'Manage drives and storage',
                  onTap: () => context.push('/storage-explorer'),
                ),

                // Device (admin only)
                if (isAdmin) ...[
                  _divider(),
                  _navTile(
                    icon: Icons.developer_board_rounded,
                    color: AppColors.textSecondary,
                    title: 'Device',
                    subtitle: 'Device info and name',
                    onTap: () => context.push('/settings/device'),
                  ),
                ],

              ],
            ),
          ).animate().fadeIn(delay: 140.ms),

          // ── 5. FOOTER ────────────────────────────────────────────────────
          const SizedBox(height: 32),

          // About — plain text, not a card
          Center(
            child: Text(
              'AiHomeCloud v1.0.0',
              style: GoogleFonts.dmSans(
                  color: AppColors.textMuted,
                  fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Your personal home cloud',
              style: GoogleFonts.dmSans(
                  color: AppColors.textMuted,
                  fontSize: 11),
            ),
          ),

          const SizedBox(height: 24),

          // Log Out — text button, no card
          Center(
            child: GestureDetector(
              onTap: _confirmLogout,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.logout_rounded,
                      color: AppColors.error, size: 16),
                  const SizedBox(width: 6),
                  Text('Log Out',
                      style: GoogleFonts.dmSans(
                          color: AppColors.error,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),

          // Restart and Shutdown (admin only) — text buttons below Log Out
          if (isAdmin) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _confirmReboot,
                  icon: const Icon(Icons.restart_alt_rounded,
                      color: AppColors.primary, size: 16),
                  label: Text('Restart',
                      style: GoogleFonts.dmSans(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: _confirmShutdown,
                  icon: const Icon(Icons.power_settings_new_rounded,
                      color: AppColors.error, size: 16),
                  label: Text('Shut Down',
                      style: GoogleFonts.dmSans(
                          color: AppColors.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    ),
  );
}
```

---

## New widgets to add to the file

### _ProfileCard

Add this new widget at the bottom of the file:

```dart
class _ProfileCard extends StatelessWidget {
  final String userName;
  final VoidCallback onChangePinTap;

  const _ProfileCard({
    required this.userName,
    required this.onChangePinTap,
  });

  static const _avatarColors = [
    Color(0xFFE8A84C), Color(0xFF4C9BE8), Color(0xFF4CE88A),
    Color(0xFFE84CA8), Color(0xFF9B59B6), Color(0xFF1ABC9C),
  ];

  Color get _avatarColor =>
      _avatarColors[userName.isNotEmpty ? userName.codeUnitAt(0) % _avatarColors.length : 0];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Profile row — avatar + name + switch profile hint
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _avatarColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: GoogleFonts.sora(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userName,
                          style: GoogleFonts.sora(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('Tap to switch profile',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted, size: 20),
              ],
            ),
          ),

          const Divider(
              height: 1, indent: 16, endIndent: 16,
              color: AppColors.cardBorder),

          // Change PIN row
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_rounded,
                  color: AppColors.textSecondary, size: 18),
            ),
            title: Text('Change PIN',
                style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 20),
            onTap: onChangePinTap,
          ),
        ],
      ),
    );
  }
}
```

**Wire up the profile row tap** — the "Tap to switch profile" row should navigate
to the user picker. Inside `_ProfileCard`, wrap the top `Padding` row in a
`GestureDetector`. Since `_ProfileCard` is a `StatelessWidget` without router
access, pass an optional `onProfileTap` callback:

```dart
// Add to constructor:
final VoidCallback? onProfileTap;

// Add to build: wrap the top Padding in GestureDetector(onTap: onProfileTap, ...)
```

In `_MoreScreenState.build()`, pass the tap handler:
```dart
_ProfileCard(
  userName: userName,
  onChangePinTap: _changePin,
  onProfileTap: () => context.go(
    '/user-picker',
    extra: ref.read(apiServiceProvider).host,
  ),
),
```

---

### _TailscaleRow

The existing `_TailscaleCard` is a full standalone card. We now need the same
logic as a `ListTile` that sits inside the Sharing card. Add this widget:

```dart
class _TailscaleRow extends ConsumerStatefulWidget {
  final bool isAdmin;
  final AsyncValue<Map<String, dynamic>?> statusAsync;
  const _TailscaleRow({required this.isAdmin, required this.statusAsync});

  @override
  ConsumerState<_TailscaleRow> createState() => _TailscaleRowState();
}

class _TailscaleRowState extends ConsumerState<_TailscaleRow> {
  bool _loading = false;

  Future<void> _enable() async {
    if (!widget.isAdmin) return;
    setState(() => _loading = true);
    try {
      final result = await ref.read(apiServiceProvider).tailscaleUp();
      final ip = result['tailscaleIp'] as String?;
      if (ip != null && ip.isNotEmpty) {
        final prefs = ref.read(sharedPreferencesProvider);
        await prefs.setString(AppConstants.prefTailscaleIp, ip);
        ref.read(apiServiceProvider).setTailscaleIp(ip);
      }
      ref.invalidate(tailscaleStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ip != null
              ? 'Remote access active — $ip'
              : 'Tailscale connected'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.statusAsync.value;
    final connected = status?['connected'] as bool? ?? false;
    final ip = status?['tailscaleIp'] as String?;
    final installed = status?['installed'] as bool? ?? false;

    final subtitle = switch ((connected, installed)) {
      (true, _) => 'Connected — $ip',
      (false, false) => 'Not installed on device',
      _ => 'Tap to connect',
    };

    Widget? trailing;
    if (connected) {
      trailing = const Icon(Icons.check_circle_rounded,
          color: AppColors.success, size: 20);
    } else if (widget.isAdmin && installed) {
      trailing = _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            )
          : TextButton(
              onPressed: _enable,
              child: Text('Enable',
                  style: GoogleFonts.dmSans(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            );
    }

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (connected ? AppColors.success : AppColors.textSecondary)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.vpn_lock_rounded,
            color: connected ? AppColors.success : AppColors.textSecondary,
            size: 18),
      ),
      title: Text('Remote Access',
          style: GoogleFonts.dmSans(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: GoogleFonts.dmSans(
              color: connected ? AppColors.success : AppColors.textSecondary,
              fontSize: 12)),
      trailing: trailing,
    );
  }
}
```

**Keep the old `_TailscaleCard` class in the file** — do not delete it.
It may be used elsewhere. The new `_TailscaleRow` is additive.

---

## Cleanup inside Sharing card — conditional divider before Telegram

The Sharing card has a `_divider()` before the Telegram row which is wrapped
in `if (isAdmin)`. When `isAdmin` is false the Tailscale row is the last row
and no divider should follow it. The structure handles this correctly because
the `_divider()` is inside the `if (isAdmin)` block — confirm this is the case
after implementation. If the divider falls outside the `if`, move it inside.

---

## Remove Change PIN from Security card

The Security card is being removed entirely — its two items (`Verify Server
Certificate` and `Change PIN`) are now in the Privacy & Security card. There
is no standalone Security card in the new layout. Confirm the old Security
`AppCard` block (with the comment `// ── Security`) is fully deleted.

---

## Validation

```bash
flutter analyze lib/screens/main/more_screen.dart
flutter build apk --debug
```

## Manual test checklist

**Profile card:**
- Shows avatar circle with first letter in colour ✅
- Shows username bold + "Tap to switch profile" subtitle ✅
- Tapping the profile row goes to user picker ✅
- Change PIN row opens the PIN dialog ✅

**Sharing card:**
- TV Sharing toggle works, subtitle updates to "DLNA + SMB active" ✅
- TV Sharing error shows amber dot, tapping dot retries ✅
- Remote Access shows correct state (Not installed / Enable button / Connected) ✅
- Telegram Bot row visible for admin only ✅
- Telegram Bot tap goes to /telegram-setup ✅

**Privacy & Security card:**
- Ad Blocking shows full stats card when configured ✅
- Ad Blocking shows "Not configured" subtitle when unavailable ✅
- Server Certificate shows fingerprint or "Not pinned yet" ✅
- Tapping Server Certificate opens the verify dialog ✅
- Change PIN row opens dialog ✅
- Trash row shows size and Empty button when items exist ✅

**Family & Storage card:**
- Family Members tap goes to /family ✅
- Storage Drive tap goes to /storage-explorer ✅
- Device row visible for admin only ✅

**Footer:**
- "AiHomeCloud v1.0.0" and tagline centred in grey ✅
- Log Out button in red, opens confirmation dialog ✅
- Restart and Shut Down buttons visible for admin only ✅
- Restart confirmation dialog works ✅
- Shutdown confirmation dialog works ✅

**Section headers:**
- Only 3 section labels visible: Sharing, Privacy & Security, Family & Storage ✅
- No standalone Remote Access / Ad Blocking / Telegram / Security / Family /
  Storage & Network / About / Account section headers ✅
