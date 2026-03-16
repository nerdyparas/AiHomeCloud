import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/emoji_picker_grid.dart';
import '../../widgets/user_avatar.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late TextEditingController _nameCtrl;
  String _selectedEmoji = '';
  bool _userChangedEmoji = false;
  bool _saving = false;
  bool _loadingProfile = true;
  String? _error;
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    // Pre-populate from session synchronously — screen appears instantly.
    final session = ref.read(authSessionProvider);
    _nameCtrl.text = session?.username ?? '';
    _selectedEmoji = session?.iconEmoji ?? '';
    _loadingProfile = false;
    // Only fetch has_pin (and confirm server values) silently in background.
    _loadProfileSilently();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfileSilently() async {
    try {
      final profile = await ref.read(apiServiceProvider).getMyProfile();
      if (!mounted) return;
      setState(() {
        // Accept server values in case session data is stale
        _nameCtrl.text = profile['name'] as String? ?? _nameCtrl.text;
        if (!_userChangedEmoji) {
          _selectedEmoji = profile['icon_emoji'] as String? ?? _selectedEmoji;
        }
        _hasPin = profile['has_pin'] as bool? ?? false;
      });
    } catch (_) {
      // Non-critical: has_pin stays false; name/emoji from session are shown.
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = AppLocalizations.of(context)!.profileNameEmptyError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

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
        SnackBar(content: Text(AppLocalizations.of(context)!.profileUpdatedSnackbar)),
      );
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _saving = false;
        });
      }
    }
  }

  void _showChangePinDialog() {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          _hasPin ? l10n.profileChangePinTitle : l10n.profileAddPinTitle,
          style: GoogleFonts.sora(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasPin) ...[
              TextField(
                controller: oldCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.dmSans(color: AppColors.textPrimary),
                decoration: InputDecoration(hintText: l10n.profileCurrentPinHint),
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
              decoration: InputDecoration(
                hintText: l10n.profileNewPinHint,
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.dmSans(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.profileConfirmPinHint,
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.buttonCancel,
              style: GoogleFonts.dmSans(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final newPin = newCtrl.text.trim();
              final confirmPin = confirmCtrl.text.trim();

              if (newPin.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(l10n.profilePinMinLengthError)),
                );
                return;
              }
              if (newPin != confirmPin) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.profilePinsDoNotMatchError)),
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
                  final wasHasPin = _hasPin;
                  setState(() => _hasPin = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text(wasHasPin ? l10n.profilePinUpdatedSnackbar : l10n.profilePinAddedSnackbar)),
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
            child: Text(
              l10n.buttonSave,
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemovePin() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          l10n.profileRemovePinTitle,
          style: GoogleFonts.sora(color: AppColors.textPrimary),
        ),
        content: Text(
          l10n.profileRemovePinMessage,
          style: GoogleFonts.dmSans(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.buttonCancel,
              style: GoogleFonts.dmSans(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            onPressed: () async {
              try {
                await ref.read(apiServiceProvider).removePin();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  setState(() => _hasPin = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.profilePinRemovedSnackbar)),
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
            child: Text(
              l10n.profileRemovePinButton,
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _switchProfile() {
    final session = ref.read(authSessionProvider);
    if (session == null) {
      context.go('/');
      return;
    }
    context.go('/user-picker', extra: session.host);
  }

  void _confirmDeleteProfile() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          l10n.profileDeleteTitle,
          style: GoogleFonts.sora(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.profileDeleteMessage,
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
                      l10n.profileDeleteWarning,
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
            child: Text(
              l10n.buttonCancel,
              style: GoogleFonts.dmSans(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteProfile();
            },
            child: Text(
              l10n.profileDeleteButton,
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
            ),
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

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.dmSans(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      );

  Widget _divider() =>
      const Divider(color: AppColors.cardBorder, height: 1);

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
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          l10n.profileEditTitle,
          style: GoogleFonts.sora(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loadingProfile
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Avatar preview ───────────────────────────────────────
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

                  // ── Section: Name ────────────────────────────────────────
                  _sectionLabel(l10n.profileDisplayNameLabel),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.dmSans(
                        color: AppColors.textPrimary, fontSize: 15),
                    decoration: _inputDecoration(l10n.profileDisplayNameHint),
                  ),

                  const SizedBox(height: 24),

                  // ── Section: Icon ────────────────────────────────────────────────
                  _sectionLabel(l10n.profileIconLabel),
                  const SizedBox(height: 12),
                  EmojiPickerGrid(
                    selectedEmoji: _selectedEmoji,
                    onSelected: (e) => setState(() {
                      _selectedEmoji = e;
                      _userChangedEmoji = true;
                    }),
                  ),

                  const SizedBox(height: 24),

                  // ── Error ────────────────────────────────────────────────
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: GoogleFonts.dmSans(
                          color: AppColors.error, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // ── Save button ──────────────────────────────────────────
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
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              l10n.profileSaveChangesButton,
                              style: GoogleFonts.dmSans(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15),
                            ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  _divider(),
                  const SizedBox(height: 32),

                  // ── Section: PIN ─────────────────────────────────────────
                  _sectionLabel(l10n.profilePinLabel),
                  const SizedBox(height: 12),

                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListTile(
                          leading: _iconBox(
                              Icons.lock_rounded, AppColors.textSecondary),
                          title: Text(
                            _hasPin ? l10n.profileChangePinTitle : l10n.profileAddPinTitle,
                            style: GoogleFonts.dmSans(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            _hasPin
                                ? l10n.profileChangePinSubtitle
                                : l10n.profileAddPinSubtitle,
                            style: GoogleFonts.dmSans(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppColors.textMuted, size: 20),
                          onTap: _showChangePinDialog,
                        ),
                        if (_hasPin) ...[
                          const Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: AppColors.cardBorder),
                          ListTile(
                            leading: _iconBox(
                                Icons.lock_open_rounded, AppColors.error),
                            title: Text(
                              l10n.profileRemovePinButton,
                              style: GoogleFonts.dmSans(
                                  color: AppColors.error,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              l10n.profileNoPin,
                              style: GoogleFonts.dmSans(
                                  color: AppColors.textSecondary,
                                  fontSize: 12),
                            ),
                            onTap: _confirmRemovePin,
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  _divider(),
                  const SizedBox(height: 32),

                  // ── Section: Account ─────────────────────────────────────
                  _sectionLabel(l10n.profileAccountLabel),
                  const SizedBox(height: 12),

                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListTile(
                          leading: _iconBox(
                              Icons.switch_account_rounded, AppColors.primary),
                          title: Text(
                            l10n.profileSwitchProfileTitle,
                            style: GoogleFonts.dmSans(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            l10n.profileSwitchProfileSubtitle,
                            style: GoogleFonts.dmSans(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppColors.textMuted, size: 20),
                          onTap: _switchProfile,
                        ),
                        const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: AppColors.cardBorder),
                        ListTile(
                          leading: _iconBox(
                              Icons.person_remove_rounded, AppColors.error),
                          title: Text(
                            l10n.profileDeleteListTitle,
                            style: GoogleFonts.dmSans(
                                color: AppColors.error,
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            l10n.profileDeleteListSubtitle,
                            style: GoogleFonts.dmSans(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
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
    );
  }
}
