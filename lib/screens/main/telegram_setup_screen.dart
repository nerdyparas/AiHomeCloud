import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../widgets/app_card.dart';

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
  final _apiIdCtrl = TextEditingController();
  final _apiHashCtrl = TextEditingController();
  bool _obscureToken = true;
  bool _obscureApiHash = true;
  bool _loading = true;
  bool _saving = false;
  bool _botRunning = false;
  bool _configured = false;
  bool _localApiEnabled = false;
  int _linkedCount = 0;
  int _maxFileMb = 20;
  int _apiId = 0;
  String? _errorMsg;
  List<Map<String, dynamic>> _pendingApprovals = [];
  bool _pendingLoading = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _apiIdCtrl.dispose();
    _apiHashCtrl.dispose();
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
          _localApiEnabled = cfg['local_api_enabled'] as bool? ?? false;
          _linkedCount = cfg['linked_count'] as int? ?? 0;
          _maxFileMb = cfg['max_file_mb'] as int? ?? 20;
          _apiId = cfg['api_id'] as int? ?? 0;
          if (_apiId > 0) _apiIdCtrl.text = _apiId.toString();
          _loading = false;
        });
        // Load pending approvals (admin only)
        _loadPending();
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

  Future<void> _loadPending() async {
    setState(() => _pendingLoading = true);
    try {
      final list = await ref.read(apiServiceProvider).getTelegramPending();
      if (mounted) setState(() => _pendingApprovals = list);
    } catch (_) {
      // non-critical: silently ignore
    } finally {
      if (mounted) setState(() => _pendingLoading = false);
    }
  }

  Future<void> _approvePending(int chatId) async {
    try {
      await ref.read(apiServiceProvider).approveTelegramRequest(chatId);
      await _loadPending();
      await _loadConfig();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  Future<void> _denyPending(int chatId) async {
    try {
      await ref.read(apiServiceProvider).denyTelegramRequest(chatId);
      await _loadPending();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  List<Widget> _buildPendingSection() {
    final l10n = AppLocalizations.of(context)!;
    return [
      Text(
        l10n.telegramPendingRequestsLabel,
        style: GoogleFonts.dmSans(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5),
      ),
      const SizedBox(height: 8),
      AppCard(
        child: _pendingLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                ),
              )
            : Column(
                children: _pendingApprovals.asMap().entries.map((e) {
                  final i = e.key;
                  final p = e.value;
                  final chatId = p['chat_id'] as int;
                  final firstName = p['first_name'] as String? ?? 'Unknown';
                  final username = p['username'] as String? ?? '';
                  return Column(
                    children: [
                      if (i > 0)
                        const Divider(color: AppColors.cardBorder, height: 16),
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(30),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                firstName.isNotEmpty
                                    ? firstName[0].toUpperCase()
                                    : '?',
                                style: GoogleFonts.dmSans(
                                    color: AppColors.primary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(firstName,
                                    style: GoogleFonts.dmSans(
                                        color: AppColors.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                  username.isNotEmpty
                                      ? '@$username · ID: $chatId'
                                      : 'ID: $chatId',
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.textSecondary,
                                      fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _denyPending(chatId),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.error,
                                minimumSize: const Size(0, 32),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10)),
                            child: Text(l10n.telegramDenyButton,
                                style: GoogleFonts.dmSans(fontSize: 12)),
                          ),
                          const SizedBox(width: 4),
                          FilledButton(
                            onPressed: () => _approvePending(chatId),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.success,
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(l10n.telegramApproveButton,
                                style: GoogleFonts.dmSans(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  );
                }).toList(),
              ),
      ),
    ];
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final token = _tokenCtrl.text.trim();

    if (token.isEmpty && !_configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.telegramBotTokenRequiredError)),
      );
      return;
    }

    final apiId = int.tryParse(_apiIdCtrl.text.trim()) ?? 0;
    final apiHash = _apiHashCtrl.text.trim();

    if (_localApiEnabled && (apiId == 0 || apiHash.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(l10n.telegramLargeFileModeRequiredError),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    try {
      await ref.read(apiServiceProvider).saveTelegramConfig(
            token.isNotEmpty ? token : '',
            apiId: apiId,
            apiHash: apiHash,
            localApiEnabled: _localApiEnabled,
          );
      if (mounted) {
        _tokenCtrl.clear();
        _apiHashCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.telegramConfiguredSnackbar),
          ),
        );
        await _loadConfig();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = friendlyError(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text(l10n.moreTelegramBot,
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
                      Text(l10n.telegramSetupStepsTitle,
                          style: GoogleFonts.sora(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      _stepText('1',
                          l10n.telegramSetupStep1),
                      _stepText('2',
                          l10n.telegramSetupStep2),
                      _stepText('3',
                          l10n.telegramSetupStep3),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Token input
                Text(l10n.telegramBotTokenLabel,
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
                        ? l10n.telegramTokenHintConfigured
                        : l10n.telegramTokenHintExample,
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
                        : Text(l10n.telegramSaveActivateButton,
                            style: GoogleFonts.dmSans(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 24),

                // Linked accounts status
                if (_configured) ...[
                  AppCard(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (_linkedCount > 0
                                    ? AppColors.success
                                    : AppColors.textMuted)
                                .withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.people_rounded,
                              color: _linkedCount > 0
                                  ? AppColors.success
                                  : AppColors.textMuted,
                              size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _linkedCount == 0
                                    ? l10n.telegramNoAccountsLinked
                                    : l10n.telegramAccountsLinked(_linkedCount),
                                style: GoogleFonts.dmSans(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                              if (_linkedCount == 0)
                                Text(l10n.telegramOpenBotSendAuth,
                                    style: GoogleFonts.dmSans(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Pending approval requests (shown when there are any)
                  if (_pendingApprovals.isNotEmpty || _pendingLoading) ...[
                    ..._buildPendingSection(),
                    const SizedBox(height: 8),
                  ],
                ],

                // File limit info card
                AppCard(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(30),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.upload_file_rounded,
                            color: AppColors.primary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.telegramFileLimitLabel(_maxFileMb),
                                style: GoogleFonts.dmSans(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(
                              _localApiEnabled
                                  ? l10n.telegramLargeFileModeActive
                                  : l10n.telegramLargeFileModeInactive,
                              style: GoogleFonts.dmSans(
                                  color: AppColors.textSecondary,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Large file mode toggle + api_id/api_hash fields
                AppCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _localApiEnabled,
                        onChanged: (v) =>
                            setState(() => _localApiEnabled = v),
                        activeThumbColor: AppColors.primary,
                        activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                        title: Text(l10n.telegramLargeFileModeTitle,
                            style: GoogleFonts.dmSans(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          l10n.telegramLargeFileModeSubtitle,
                          style: GoogleFonts.dmSans(
                              color: AppColors.textSecondary,
                              fontSize: 12),
                        ),
                      ),
                      if (_localApiEnabled) ...[
                        const Divider(
                            color: AppColors.cardBorder, height: 24),
                        Text(
                          l10n.telegramApiCredentialsHint,
                          style: GoogleFonts.dmSans(
                              color: AppColors.textSecondary,
                              fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _apiIdCtrl,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.dmSans(
                              color: AppColors.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: l10n.telegramApiIdLabel,
                            labelStyle: GoogleFonts.dmSans(
                                color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: AppColors.cardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: AppColors.cardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: AppColors.primary, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _apiHashCtrl,
                          obscureText: _obscureApiHash,
                          style: GoogleFonts.dmSans(
                              color: AppColors.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            labelText: l10n.telegramApiHashLabel,
                            labelStyle: GoogleFonts.dmSans(
                                color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: AppColors.cardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: AppColors.cardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: AppColors.primary, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _obscureApiHash
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: AppColors.textMuted,
                                  size: 18),
                              onPressed: () => setState(
                                  () => _obscureApiHash = !_obscureApiHash),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.telegramScriptHint,
                          style: GoogleFonts.dmSans(
                              color: AppColors.primary, fontSize: 11),
                        ),
                      ],
                    ],
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
    final l10n = AppLocalizations.of(context)!;
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
        ? l10n.telegramBotActiveStatus
        : configured
            ? l10n.telegramBotConfiguredStatus
            : l10n.telegramBotNotConfiguredStatus;

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
                Text(l10n.moreTelegramBot,
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
