import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/error_utils.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/emoji_picker_grid.dart';
import '../../widgets/user_avatar.dart';

class ProfileCreationScreen extends ConsumerStatefulWidget {
  final String deviceIp;
  final bool isAddingUser;

  const ProfileCreationScreen({
    super.key,
    required this.deviceIp,
    this.isAddingUser = false,
  });

  @override
  ConsumerState<ProfileCreationScreen> createState() =>
      _ProfileCreationScreenState();
}

class _ProfileCreationScreenState extends ConsumerState<ProfileCreationScreen> {
  String _selectedEmoji = '';
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final pin = _pinCtrl.text.trim();

      final result = await ref.read(apiServiceProvider).createUser(
            name,
            pin.isNotEmpty ? pin : null,
            hostOverride: widget.deviceIp,
            iconEmoji: _selectedEmoji,
          );

      if (!mounted) return;

      if (widget.isAddingUser) {
        // Admin added a family member — don't switch sessions, just refresh.
        context.pop(true);
      } else {
        // First-time setup — log in as the new user and go to dashboard.
        await ref.read(authSessionProvider.notifier).login(
              host: widget.deviceIp,
              port: AppConstants.apiPort,
              token: result['accessToken'] as String,
              refreshToken: result['refreshToken'] as String?,
              username: name,
              isAdmin: result['isAdmin'] as bool? ?? false,
            );

        if (!mounted) return;
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.isAddingUser
          ? AppBar(
              backgroundColor: AppColors.background,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => context.pop(false),
              ),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            Center(
              child: UserAvatar(
                name: _nameCtrl.text.isNotEmpty ? _nameCtrl.text : '?',
                iconEmoji: _selectedEmoji,
                colorIndex: 0,
                size: 88,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Set up your profile',
              textAlign: TextAlign.center,
              style: GoogleFonts.sora(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isAddingUser
                  ? 'Add a profile for this home.'
                  : 'You will be the admin. Others can join later.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            _fieldLabel('Your name'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.name,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 15),
              decoration: _inputDecoration('e.g. Mike, Mum, Dad'),
            ),
            const SizedBox(height: 24),
            _fieldLabel('Choose an icon'),
            const SizedBox(height: 12),
            EmojiPickerGrid(
              selectedEmoji: _selectedEmoji,
              onSelected: (e) => setState(() => _selectedEmoji = e),
            ),
            const SizedBox(height: 24),
            _fieldLabel('PIN'),
            const SizedBox(height: 4),
            Text(
              'Leave blank for no PIN',
              style: GoogleFonts.dmSans(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 15),
              decoration: _inputDecoration('Optional').copyWith(counterText: ''),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: GoogleFonts.dmSans(color: AppColors.error, fontSize: 13),
              ),
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Create Profile',
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
