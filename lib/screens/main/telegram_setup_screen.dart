import 'dart:async';

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
  bool _savingToken = false;
  bool _botRunning = false;
  bool _configured = false;
  int _linkedCount = 0;
  int _maxFileMb = 20;
  int _apiId = 0;
  String? _errorMsg;
  List<Map<String, dynamic>> _pendingApprovals = [];
  bool _pendingLoading = false;

  // 2 GB setup job state
  String? _setup2gbJobId;
  bool _setup2gbRunning = false;
  String _setup2gbMessage = '';
  String? _setup2gbError;
  Timer? _setup2gbPollTimer;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _setup2gbPollTimer?.cancel();
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
      final cfg = await ref.read(apiServiceProvider).getTelegramConfig();
      if (mounted) {
        setState(() {
          _configured = cfg['configured'] as bool? ?? false;
          _botRunning = cfg['bot_running'] as bool? ?? false;
          _maxFileMb = cfg['max_file_mb'] as int? ?? 20;
          _linkedCount = cfg['linked_count'] as int? ?? 0;
          _apiId = cfg['api_id'] as int? ?? 0;
          if (_apiId > 0) _apiIdCtrl.text = _apiId.toString();
          _loading = false;
        });
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _denyPending(int chatId) async {
    try {
      await ref.read(apiServiceProvider).denyTelegramRequest(chatId);
      await _loadPending();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  // ── Save bot token only ──────────────────────────────────────────────────

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty && !_configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.telegramBotTokenRequiredError)),
      );
      return;
    }
    setState(() {
      _savingToken = true;
      _errorMsg = null;
    });
    try {
      await ref
          .read(apiServiceProvider)
          .saveTelegramConfig(token.isNotEmpty ? token : '');
      if (mounted) {
        _tokenCtrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.telegramConfiguredSnackbar)),
        );
        await _loadConfig();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = friendlyError(e));
    } finally {
      if (mounted) setState(() => _savingToken = false);
    }
  }

  // ── Enable 2 GB Mode ────────────────────────────────────────────────────

  Future<void> _enable2GbMode() async {
    final l10n = AppLocalizations.of(context)!;
    final apiId = int.tryParse(_apiIdCtrl.text.trim()) ?? 0;
    final apiHash = _apiHashCtrl.text.trim();

    if (apiId <= 0 || apiHash.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.telegramLargeFileModeRequiredError)),
      );
      return;
    }

    // Show confirmation dialog before starting the long build.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          l10n.telegram2GbSetupTitle,
          style: GoogleFonts.sora(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600),
        ),
        content: Text(
          l10n.telegram2GbBuildConfirmation,
          style: GoogleFonts.dmSans(
              color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.buttonCancel,
                style: GoogleFonts.dmSans(
                    color: AppColors.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary),
            child: Text(l10n.telegram2GbStartBuildButton,
                style: GoogleFonts.dmSans(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _setup2gbRunning = true;
      _setup2gbMessage = 'Starting\u2026';
      _setup2gbError = null;
    });

    try {
      final jobId = await ref.read(apiServiceProvider).setupTelegramLocalApi(
            apiId: apiId,
            apiHash: apiHash,
            botToken: _tokenCtrl.text.trim(),
          );
      _setup2gbJobId = jobId;
      _startSetupPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _setup2gbRunning = false;
          _setup2gbError = friendlyError(e);
        });
      }
    }
  }

  void _startSetupPolling() {
    _setup2gbPollTimer?.cancel();
    _setup2gbPollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) async {
      final jobId = _setup2gbJobId;
      if (jobId == null) return;
      try {
        final job =
            await ref.read(apiServiceProvider).getJobStatus(jobId);
        if (!mounted) return;
        final msg =
            (job.result?['message'] as String?) ?? _setup2gbMessage;
        setState(() => _setup2gbMessage = msg);
        if (job.isTerminal) {
          _setup2gbPollTimer?.cancel();
          if (job.status == 'completed') {
            setState(() {
              _setup2gbRunning = false;
              _setup2gbError = null;
              _setup2gbJobId = null;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        AppLocalizations.of(context)!
                            .telegram2GbActivatedSnackbar)),
              );
            }
            await _loadConfig();
          } else {
            setState(() {
              _setup2gbRunning = false;
              _setup2gbError = job.error ?? 'Setup failed.';
              _setup2gbJobId = null;
            });
          }
        }
      } catch (_) {
        // keep polling on transient errors
      }
    });
  }

  // ── Pending approvals section ────────────────────────────────────────────

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
                          strokeWidth: 2, color: AppColors.primary)),
                ),
              )
            : Column(
                children: _pendingApprovals.asMap().entries.map((e) {
                  final i = e.key;
                  final p = e.value;
                  final chatId = p['chat_id'] as int;
                  final firstName =
                      p['first_name'] as String? ?? 'Unknown';
                  final username = p['username'] as String? ?? '';
                  return Column(
                    children: [
                      if (i > 0)
                        const Divider(
                            color: AppColors.cardBorder, height: 16),
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
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(firstName,
                                    style: GoogleFonts.dmSans(
                                        color: AppColors.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                  username.isNotEmpty
                                      ? '@$username \u00b7 ID: $chatId'
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
                                  borderRadius:
                                      BorderRadius.circular(8)),
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

  // ── Build ────────────────────────────────────────────────────────────────

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
                // ── Status card ────────────────────────────────────
                _StatusCard(configured: _configured, running: _botRunning),
                const SizedBox(height: 24),

                // ── Setup steps ────────────────────────────────────
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
                      _stepText('1', l10n.telegramSetupStep1),
                      _stepText('2', l10n.telegramSetupStep2),
                      _stepText('3', l10n.telegramSetupStep3),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Bot token field ─────────────────────────────────
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
                      borderSide:
                          const BorderSide(color: AppColors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.primary, width: 1.5),
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

                if (_errorMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(_errorMsg!,
                      style: GoogleFonts.dmSans(
                          color: AppColors.error, fontSize: 13)),
                ],
                const SizedBox(height: 16),

                // ── Save & Connect button ───────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _savingToken ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _savingToken
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(l10n.telegramSaveActivateButton,
                            style: GoogleFonts.dmSans(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Linked accounts ─────────────────────────────────
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
                                    : l10n.telegramAccountsLinked(
                                        _linkedCount),
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

                  // ── Pending approvals ───────────────────────────
                  if (_pendingApprovals.isNotEmpty || _pendingLoading) ...[
                    ..._buildPendingSection(),
                    const SizedBox(height: 16),
                  ],
                ],

                // ── File limit banner ───────────────────────────────
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
                              _maxFileMb >= 2000
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

                // ── 2 GB Mode section ───────────────────────────────
                if (_maxFileMb >= 2000)
                  // Already active badge
                  AppCard(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                              Icons.rocket_launch_rounded,
                              color: AppColors.success,
                              size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.telegram2GbModeActive,
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.success,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              Text(l10n.telegramLargeFileModeActive,
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  // Setup card
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withAlpha(30),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                  Icons.rocket_launch_rounded,
                                  color: AppColors.primary,
                                  size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(l10n.telegram2GbSetupTitle,
                                      style: GoogleFonts.dmSans(
                                          color: AppColors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  Text(l10n.telegram2GbSetupSubtitle,
                                      style: GoogleFonts.dmSans(
                                          color: AppColors.textSecondary,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(
                            color: AppColors.cardBorder, height: 24),

                        // API ID field
                        TextField(
                          controller: _apiIdCtrl,
                          keyboardType: TextInputType.number,
                          enabled: !_setup2gbRunning,
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
                                    color: AppColors.cardBorder)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.cardBorder)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.primary,
                                    width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // API Hash field
                        TextField(
                          controller: _apiHashCtrl,
                          obscureText: _obscureApiHash,
                          enabled: !_setup2gbRunning,
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
                                    color: AppColors.cardBorder)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.cardBorder)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.primary,
                                    width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _obscureApiHash
                                      ? Icons.visibility_off_rounded
                                      : Icons.visibility_rounded,
                                  color: AppColors.textMuted,
                                  size: 18),
                              onPressed: _setup2gbRunning
                                  ? null
                                  : () => setState(() =>
                                      _obscureApiHash = !_obscureApiHash),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.telegramScriptHint,
                          style: GoogleFonts.dmSans(
                              color: AppColors.primary, fontSize: 11),
                        ),
                        const SizedBox(height: 16),

                        // Progress row
                        if (_setup2gbRunning) ...[
                          Row(
                            children: [
                              const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(_setup2gbMessage,
                                    style: GoogleFonts.dmSans(
                                        color: AppColors.textSecondary,
                                        fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Error box
                        if (_setup2gbError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(_setup2gbError!,
                                style: GoogleFonts.dmSans(
                                    color: AppColors.error,
                                    fontSize: 12)),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Enable button
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _setup2gbRunning
                                ? null
                                : _enable2GbMode,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12)),
                            ),
                            child: _setup2gbRunning
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                                : Text(l10n.telegramEnable2GbButton,
                                    style: GoogleFonts.dmSans(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                          ),
                        ),
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
                    style: GoogleFonts.dmSans(color: color, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
