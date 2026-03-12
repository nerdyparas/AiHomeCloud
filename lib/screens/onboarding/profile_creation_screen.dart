import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants.dart';
import '../../core/error_utils.dart';
import '../../core/theme.dart';
import '../../providers.dart';

class ProfileCreationScreen extends ConsumerStatefulWidget {
  final String deviceIp;

  /// When true, pops back to the caller instead of navigating to /dashboard.
  /// Used from the "Add User" tile in the user picker.
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

class _ProfileCreationScreenState
    extends ConsumerState<ProfileCreationScreen> {
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  int _selectedColorIndex = 0;

  static const _avatarColors = [
    Color(0xFFE8A84C),
    Color(0xFF4C9BE8),
    Color(0xFF4CE88A),
    Color(0xFFE84CA8),
    Color(0xFF9B59B6),
    Color(0xFF1ABC9C),
  ];

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
      final api = ref.read(apiServiceProvider);
      final pin = _pinCtrl.text.trim();

      // 1. Create user — first user gets admin automatically, no auth needed.
      await api.createUser(
        name,
        pin.isNotEmpty ? pin : null,
        hostOverride: widget.deviceIp,
      );

      // 2. Login immediately.
      final result = await api.loginWithPin(
        widget.deviceIp,
        name,
        pin, // empty string = no-PIN login
      );

      final user = result['user'] as Map<String, dynamic>?;

      await ref.read(authSessionProvider.notifier).login(
        host: widget.deviceIp,
        port: AppConstants.apiPort,
        token: result['accessToken'] as String,
        refreshToken: result['refreshToken'] as String?,
        username: user?['name'] as String? ?? name,
        isAdmin: user?['isAdmin'] as bool? ?? false,
          );

      if (!mounted) return;

      if (widget.isAddingUser) {
        context.pop(true); // return true to signal user was created
      } else {
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.isAddingUser
          ? AppBar(
              backgroundColor: AppColors.background,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.textSecondary),
                onPressed: () => context.pop(false),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),

                Text(
                  'Set up your profile',
                  style: GoogleFonts.sora(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  widget.isAddingUser
                      ? 'Add a new profile to your AiHomeCloud.'
                      : "You'll be the admin. Others can join later.",
                  style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 40),

                // Avatar colour picker — 6 circles
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < _avatarColors.length; i++)
                      GestureDetector(
                        onTap: () => setState(() => _selectedColorIndex = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 48,
                          height: 48,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: _avatarColors[i],
                            shape: BoxShape.circle,
                            border: _selectedColorIndex == i
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                            boxShadow: _selectedColorIndex == i
                                ? [
                                    BoxShadow(
                                      color: _avatarColors[i]
                                          .withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    )
                                  ]
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 32),

                // Name field
                Text(
                  'Your name',
                  style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  style: GoogleFonts.dmSans(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g. Mike, Mum, Dad',
                    hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.surface,
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
                          const BorderSide(color: AppColors.primary, width: 2),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // PIN field — optional
                Text(
                  'PIN (optional)',
                  style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
                  style: GoogleFonts.dmSans(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '••••  (optional)',
                    hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted),
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.surface,
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
                          const BorderSide(color: AppColors.primary, width: 2),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                if (_error != null)
                  Text(
                    _error!,
                    style: GoogleFonts.dmSans(
                      color: AppColors.error,
                      fontSize: 13,
                    ),
                  ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 56,
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
                            height: 20,
                            width: 20,
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
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
