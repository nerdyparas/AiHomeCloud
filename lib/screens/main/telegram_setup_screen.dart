import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../providers.dart';
import '../../widgets/cubie_card.dart';

/// Admin-only Telegram Bot setup screen.
/// Accessible from More tab → Telegram Bot row.
class TelegramSetupScreen extends ConsumerStatefulWidget {
  const TelegramSetupScreen({super.key});

  @override
  ConsumerState<TelegramSetupScreen> createState() =>
      _TelegramSetupScreenState();
}

class _TelegramSetupScreenState extends ConsumerState<TelegramSetupScreen> {
  final _tokenCtrl = TextEditingController();
  final _idsCtrl = TextEditingController();
  bool _obscureToken = true;
  bool _loading = true;
  bool _saving = false;
  bool _botRunning = false;
  bool _configured = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _idsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final cfg =
          await ref.read(apiServiceProvider).getTelegramConfig();
      if (mounted) {
        setState(() {
          _configured = cfg['configured'] as bool? ?? false;
          _botRunning = cfg['bot_running'] as bool? ?? false;
          // Don't fill token field with masked value — leave blank for security.
          // Fill allowed_ids so user can see and edit existing list.
          _idsCtrl.text = cfg['allowed_ids'] as String? ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final token = _tokenCtrl.text.trim();
    final ids = _idsCtrl.text.trim();

    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bot Token is required.')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    try {
      await ref.read(apiServiceProvider).saveTelegramConfig(token, ids);
      if (mounted) {
        _tokenCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Telegram Bot configured! Bot is now active.'),
          ),
        );
        await _loadConfig();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = friendlyError(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text('Telegram Bot',
            style: GoogleFonts.sora(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Status card
                _StatusCard(configured: _configured, running: _botRunning),
                const SizedBox(height: 24),

                // Instructions
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How to set up',
                          style: GoogleFonts.sora(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _stepText('1', 'Open Telegram and search for @BotFather'),
                      _stepText('2', 'Send /newbot and follow the instructions'),
                      _stepText(
                          '3', 'Copy the bot token and paste it below'),
                      _stepText(
                          '4',
                          'Optionally add your Telegram chat ID to restrict access'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Token input
                Text('Bot Token',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenCtrl,
                  obscureText: _obscureToken,
                  style: GoogleFonts.dmSans(
                      color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _configured
                        ? 'Enter new token to replace existing'
                        : '1234567890:ABCdefGHIjklMNOpqrSTUvwxyz',
                    hintStyle: GoogleFonts.dmSans(
                        color: AppColors.textMuted, fontSize: 13),
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
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscureToken
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: AppColors.textMuted,
                          size: 18),
                      onPressed: () =>
                          setState(() => _obscureToken = !_obscureToken),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),

                // Allowed IDs input
                Text('Allowed Chat IDs (optional)',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text('Comma-separated — leave empty to allow anyone',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textMuted, fontSize: 11)),
                const SizedBox(height: 8),
                TextField(
                  controller: _idsCtrl,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.dmSans(
                      color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '123456789, 987654321',
                    hintStyle: GoogleFonts.dmSans(
                        color: AppColors.textMuted, fontSize: 13),
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
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),

                // Error message
                if (_errorMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(_errorMsg!,
                      style: GoogleFonts.dmSans(
                          color: AppColors.error, fontSize: 13)),
                ],
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Save & Activate',
                            style: GoogleFonts.dmSans(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _stepText(String num, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(num,
                    style: GoogleFonts.dmSans(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: GoogleFonts.dmSans(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4)),
            ),
          ],
        ),
      );
}

class _StatusCard extends StatelessWidget {
  final bool configured;
  final bool running;
  const _StatusCard({required this.configured, required this.running});

  @override
  Widget build(BuildContext context) {
    final color = running
        ? AppColors.success
        : configured
            ? AppColors.primary
            : AppColors.textMuted;
    final icon = running
        ? Icons.check_circle_rounded
        : configured
            ? Icons.warning_amber_rounded
            : Icons.smart_toy_outlined;
    final label = running
        ? 'Bot is active and polling'
        : configured
            ? 'Configured but not running'
            : 'Not configured';

    return AppCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Telegram Bot',
                    style: GoogleFonts.dmSans(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(label,
                    style: GoogleFonts.dmSans(
                        color: color, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
