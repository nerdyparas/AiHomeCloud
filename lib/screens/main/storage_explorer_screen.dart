import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/app_card.dart';

/// Storage explorer â€” shows each physical drive as one card.
/// No partition names, no /dev/ paths, no filesystem terms shown to the user.
class StorageExplorerScreen extends ConsumerStatefulWidget {
  const StorageExplorerScreen({super.key});

  @override
  ConsumerState<StorageExplorerScreen> createState() =>
      _StorageExplorerScreenState();
}

class _StorageExplorerScreenState extends ConsumerState<StorageExplorerScreen> {
  bool _scanning = false;
  List<StorageDevice>? _devices;
  String? _error;
  String? _busyDevice;
  String? _activateJobId;
  DateTime? _activateStartedAt;
  Timer? _jobPollTimer;
  Timer? _elapsedTimer;

  bool get _activateInProgress => _activateJobId != null;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _jobPollTimer?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await ref.read(apiServiceProvider).getStorageDevices();
      if (mounted) setState(() => _devices = devices);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final devices = await ref.read(apiServiceProvider).scanDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = friendlyError(e);
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
        title: Text(l10n.storageExplorerTitle,
            style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: l10n.storageExplorerScanTooltip,
            onPressed: _scanning ? null : _scan,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null && _devices == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(l10n.storageCouldNotLoadDrives,
                style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.buttonRetry),
            ),
          ],
        ),
      );
    }

    if (_devices == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    // OS disks hidden entirely â€” backend filters them, extra guard client-side.
    final drives = _devices!.where((d) => !d.isOsDisk).toList();

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _scan,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (_activateInProgress) ...[
            _buildActivateProgressCard(),
            const SizedBox(height: 12),
          ],
          if (drives.isEmpty)
            _emptyBanner()
          else
            for (final dev in drives)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DriveCard(
                  device: dev,
                  busy: _busyDevice == dev.path,
                  onActivate: () => _smartActivate(dev),
                  onPrepare: () => _showPrepareDialog(dev),
                  onSafelyRemove: () => dev.transport == 'usb'
                      ? _safeRemove(dev)
                      : _unmountDevice(dev),
                ),
              ),
        ],
      ),
    );
  }

  Widget _emptyBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.usb_rounded,
                color: AppColors.primary, size: 48),
          ),
          const SizedBox(height: 20),
          Text(l10n.storageEmptyBannerTitle,
              style: GoogleFonts.sora(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(l10n.storageEmptyBannerMessage,
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(_scanning ? l10n.storageExplorerScanning : l10n.storageExplorerScanAgain),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  // â”€â”€ Actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _smartActivate(StorageDevice dev) async {
    setState(() => _busyDevice = dev.path);
    try {
      final result =
          await ref.read(apiServiceProvider).smartActivate(dev.path);
      if (!mounted) return;
      final action = result['action'] as String? ?? '';
      switch (action) {
        case 'already_active':
          await _loadDevices();
        case 'mounted':
          _showSnack(AppLocalizations.of(context)!.storageActivatedSnackbar);
          await _loadDevices();
        case 'formatting':
          final jobId = result['jobId'] as String?;
          if (jobId != null) _startJobPolling(jobId);
        default:
          await _loadDevices();
      }
    } catch (e) {
      _showSnack(friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyDevice = null);
    }
  }

  Future<void> _unmountDevice(StorageDevice dev) async {
    setState(() => _busyDevice = dev.path);
    try {
      final usage = await ref.read(apiServiceProvider).checkStorageUsage();
      final blockers = (usage['blockers'] as List?) ?? [];

      if (blockers.isNotEmpty && mounted) {
        final force = await _showBlockerDialog(blockers);
        if (force != true) {
          setState(() => _busyDevice = null);
          return;
        }
      }

      await ref
          .read(apiServiceProvider)
          .unmountDevice(force: blockers.isNotEmpty);
      _showSnack(AppLocalizations.of(context)!.storageStoppedSnackbar(dev.displayName));
      await _loadDevices();
    } catch (e) {
      _showSnack(friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyDevice = null);
    }
  }

  Future<void> _safeRemove(StorageDevice dev) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SafeRemoveSheet(device: dev),
    );

    if (confirm != true || !mounted) return;

    setState(() => _busyDevice = dev.path);
    try {
      await ref.read(apiServiceProvider).ejectDevice(dev.path);
      _showSnack(AppLocalizations.of(context)!.storageSafeToUnplugSnackbar(dev.displayName));
      await _loadDevices();
    } catch (e) {
      _showSnack(friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyDevice = null);
    }
  }

  void _showPrepareDialog(StorageDevice dev) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Icon(Icons.warning_rounded, color: AppColors.error, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.storagePrepareDialogTitle)),
          ],
        ),
        titleTextStyle: GoogleFonts.sora(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600),
        content: Text(
          l10n.storagePrepareDialogMessage(dev.displayName),
          style: GoogleFonts.dmSans(
              color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.buttonCancel,
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.storagePrepareButton,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && mounted) _smartActivate(dev);
    });
  }

  void _startJobPolling(String jobId) {
    _jobPollTimer?.cancel();
    _elapsedTimer?.cancel();

    setState(() {
      _activateJobId = jobId;
      _activateStartedAt = DateTime.now();
    });

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _activateInProgress) setState(() {});
    });

    _jobPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final id = _activateJobId;
      if (id == null) return;
      try {
        final status = await ref.read(apiServiceProvider).getJobStatus(id);
        if (!mounted) return;
        setState(() => _activateStartedAt ??= status.startedAt);

        if (status.status == 'completed') {
          _jobPollTimer?.cancel();
          _elapsedTimer?.cancel();
          setState(() => _activateJobId = null);
          await _loadDevices();
          final active = _devices?.where((d) => d.isNasActive).firstOrNull;
          final msg = active != null
              ? AppLocalizations.of(context)!.storageReadySnackbar(active.sizeDisplay)
              : AppLocalizations.of(context)!.storageReadySimpleSnackbar;
          _showSnack(msg);
          return;
        }

        if (status.status == 'failed') {
          _jobPollTimer?.cancel();
          _elapsedTimer?.cancel();
          setState(() => _activateJobId = null);
          _showSnack(
              AppLocalizations.of(context)!.storageActivateFailedSnackbar,
              isError: true);
        }
      } catch (e) {
        if (mounted) _showSnack(friendlyError(e), isError: true);
      }
    });
  }

  Widget _buildActivateProgressCard() {
    final started = _activateStartedAt;
    final elapsed =
        started == null ? Duration.zero : DateTime.now().difference(started);
    final mm = elapsed.inMinutes;
    final ss = elapsed.inSeconds.remainder(60);
    final elapsedStr = mm > 0 ? '$mm min $ss sec' : '$ss sec';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.storagePreparingTitle,
            style: GoogleFonts.sora(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)!.storagePreparingSubtitle,
            style: GoogleFonts.dmSans(
                color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            elapsedStr,
            style:
                GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 4),
        ],
      ),
    );
  }

  Future<bool?> _showBlockerDialog(List blockers) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.storageBlockerDialogTitle, style: GoogleFonts.sora(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.storageBlockerDialogMessage(blockers.length),
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: blockers.length,
                itemBuilder: (_, i) {
                  final b = blockers[i] as Map;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.apps_rounded,
                            color: AppColors.textMuted, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${b['command']} (PID ${b['pid']})',
                            style: GoogleFonts.dmSans(
                                color: AppColors.textPrimary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.buttonCancel,
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.storageRemoveAnywayButton,
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : null,
    ));
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// DRIVE CARD â€” one card per physical drive, no partition/path/fstype shown
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class _DriveCard extends StatelessWidget {
  final StorageDevice device;
  final bool busy;
  final VoidCallback? onActivate;     // ext4 ready â†’ mount
  final VoidCallback? onPrepare;      // no ext4 â†’ format + mount
  final VoidCallback? onSafelyRemove; // active â†’ unmount / eject

  const _DriveCard({
    required this.device,
    required this.busy,
    this.onActivate,
    this.onPrepare,
    this.onSafelyRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      glowing: device.isNasActive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(device.icon, color: _accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      style: GoogleFonts.dmSans(
                          color: AppColors.textPrimary,
                          fontSize: 15,
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
              _statusBadge(context),
            ],
          ),

          // â”€â”€ Action area â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.cardBorder),
          const SizedBox(height: 12),
          if (busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              ),
            )
          else
            _actionRow(context),
        ],
      ),
    );
  }

  Widget _actionRow(BuildContext context) {
    if (device.isNasActive) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: onSafelyRemove,
          icon: const Icon(Icons.eject_rounded, size: 16),
          label: Text(AppLocalizations.of(context)!.storageSafelyRemoveButton,
              style: GoogleFonts.dmSans(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      );
    }

    if (device.fstype == 'ext4') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onPressed: onActivate,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(AppLocalizations.of(context)!.storageActivateButton,
              style: GoogleFonts.dmSans(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onPressed: onPrepare,
        icon: const Icon(Icons.drive_eta_rounded, size: 18),
        label: Text(AppLocalizations.of(context)!.storagePrepareAsStorageButton,
            style:
                GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _statusBadge(BuildContext context) {
    final String text;
    final Color color;

    if (device.isNasActive) {
      text = AppLocalizations.of(context)!.storageActiveStatusBadge;
      color = AppColors.success;
    } else if (device.fstype == 'ext4') {
      text = AppLocalizations.of(context)!.storageReadyStatusBadge;
      color = AppColors.secondary;
    } else {
      text = AppLocalizations.of(context)!.storageNotReadyStatusBadge;
      color = AppColors.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: GoogleFonts.dmSans(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Color get _accentColor => switch (device.transport) {
        'usb' => AppColors.primary,
        'nvme' => AppColors.secondary,
        _ => AppColors.textSecondary,
      };
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// SAFE REMOVE BOTTOM SHEET
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class _SafeRemoveSheet extends StatelessWidget {
  final StorageDevice device;
  const _SafeRemoveSheet({required this.device});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.eject_rounded,
                color: AppColors.error, size: 32),
          ),
          const SizedBox(height: 16),
          Text(AppLocalizations.of(context)!.storageSafeRemoveSheetTitle,
              style: GoogleFonts.sora(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.storageSafeRemoveSheetBody(device.displayName),
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
                color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          _step(Icons.stop_circle_outlined, AppLocalizations.of(context)!.storageSafeRemoveStepStopSharing),
          _step(Icons.sync_rounded, AppLocalizations.of(context)!.storageSafeRemoveStepFinishTransfers),
          _step(Icons.usb_off_rounded, AppLocalizations.of(context)!.storageSafeRemoveStepSafeToUnplug),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(AppLocalizations.of(context)!.buttonCancel,
                      style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(AppLocalizations.of(context)!.storageSafeRemoveSheetTitle,
                      style:
                          GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _step(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 18),
          const SizedBox(width: 10),
          Text(text,
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

