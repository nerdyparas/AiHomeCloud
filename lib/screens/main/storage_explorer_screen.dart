import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../core/error_utils.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/cubie_card.dart';

/// Full storage explorer — pushed from the Home storage tile.
/// Shows all detected devices with status, actions (mount/unmount/format/eject).
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
  String? _busyDevice; // device currently being acted on
  String? _formatJobId;
  DateTime? _formatStartedAt;
  String _formatStatus = '';
  Timer? _jobPollTimer;
  Timer? _elapsedTimer;

  bool get _formatInProgress => _formatJobId != null;

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
      if (mounted) setState(() => _error = e.toString());
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
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CubieColors.background,
      appBar: AppBar(
        title: Text('Storage Devices',
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
                        strokeWidth: 2, color: CubieColors.primary))
                : const Icon(Icons.refresh_rounded, color: CubieColors.primary),
            tooltip: 'Scan for devices',
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
                color: CubieColors.error, size: 48),
            const SizedBox(height: 12),
            Text('Failed to load devices',
                style: GoogleFonts.dmSans(
                    color: CubieColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_devices == null) {
      return const Center(
          child: CircularProgressIndicator(color: CubieColors.primary));
    }

    // Separate: external devices vs OS disks
    final external_ =
        _devices!.where((d) => !d.isOsDisk).toList();
    final osDisk =
        _devices!.where((d) => d.isOsDisk).toList();

    return RefreshIndicator(
      color: CubieColors.primary,
      onRefresh: _scan,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (_formatInProgress) ...[
            _buildFormatProgressCard(),
            const SizedBox(height: 12),
          ],

          // ── External storage ───────────────────────────────────────────
          if (external_.isEmpty)
            _emptyExternalBanner()
          else ...[
            _sectionLabel('External Storage'),
            const SizedBox(height: 8),
            for (final dev in external_)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DeviceCard(
                  device: dev,
                  busy: _busyDevice == dev.path,
                  onMount: () => _mountDevice(dev),
                  onUnmount: () => _unmountDevice(dev),
                  onFormat: () => _showFormatDialog(dev),
                  onEject: () => _safeRemove(dev),
                ),
              ),
          ],

          // ── System storage ─────────────────────────────────────────────
          if (osDisk.isNotEmpty) ...[
            const SizedBox(height: 8),
            _sectionLabel('System (OS)'),
            const SizedBox(height: 8),
            for (final dev in osDisk)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DeviceCard(device: dev, isSystem: true),
              ),
          ],
        ],
      ),
    );
  }

  Widget _emptyExternalBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: CubieColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.usb_rounded,
                color: CubieColors.primary, size: 48),
          ),
          const SizedBox(height: 20),
          Text('No external storage detected',
              style: GoogleFonts.sora(
                  color: CubieColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Connect a USB drive or NVMe SSD',
              style: GoogleFonts.dmSans(
                  color: CubieColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(_scanning ? 'Scanning…' : 'Scan Again'),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: GoogleFonts.sora(
          color: CubieColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5));

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _mountDevice(StorageDevice dev) async {
    setState(() => _busyDevice = dev.path);
    try {
      await ref.read(apiServiceProvider).mountDevice(dev.path);
      _showSnack('${dev.label ?? dev.name} mounted as NAS storage');
      await _loadDevices();
    } catch (e) {
      _showSnack('Mount failed: ${friendlyError(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _busyDevice = null);
    }
  }

  Future<void> _unmountDevice(StorageDevice dev) async {
    setState(() => _busyDevice = dev.path);
    try {
      // Check for open files first
      final usage = await ref.read(apiServiceProvider).checkStorageUsage();
      final blockers = (usage['blockers'] as List?) ?? [];

      if (blockers.isNotEmpty && mounted) {
        final force = await _showBlockerDialog(blockers);
        if (force != true) {
          setState(() => _busyDevice = null);
          return;
        }
      }

      await ref.read(apiServiceProvider).unmountDevice(
            force: blockers.isNotEmpty,
          );
      _showSnack('Storage unmounted');
      await _loadDevices();
    } catch (e) {
      _showSnack('Unmount failed: ${friendlyError(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _busyDevice = null);
    }
  }

  Future<void> _safeRemove(StorageDevice dev) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: CubieColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SafeRemoveSheet(device: dev),
    );

    if (confirm != true || !mounted) return;

    setState(() => _busyDevice = dev.path);
    try {
      await ref.read(apiServiceProvider).ejectDevice(dev.path);
      _showSnack('${dev.label ?? dev.name} safely ejected — you can remove it');
      await _loadDevices();
    } catch (e) {
      _showSnack('Eject failed: ${friendlyError(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _busyDevice = null);
    }
  }

  void _showFormatDialog(StorageDevice dev) {
    final confirmCtrl = TextEditingController();
    final labelCtrl = TextEditingController(text: 'CubieNAS');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final matches = confirmCtrl.text == dev.path;
          return AlertDialog(
            backgroundColor: CubieColors.surface,
            title: Row(
              children: [
                const Icon(Icons.warning_rounded,
                    color: CubieColors.error, size: 24),
                const SizedBox(width: 8),
                Text('Format Device', style: GoogleFonts.sora(fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will ERASE ALL DATA on ${dev.label ?? dev.name} '
                  '(${dev.sizeDisplay}).\nThis cannot be undone.',
                  style: GoogleFonts.dmSans(
                      color: CubieColors.textSecondary, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: labelCtrl,
                  style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Volume label',
                    hintText: 'CubieNAS',
                  ),
                ),
                const SizedBox(height: 12),
                Text('Type "${dev.path}" to confirm:',
                    style: GoogleFonts.dmSans(
                        color: CubieColors.error, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: confirmCtrl,
                  style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: dev.path,
                    hintStyle: GoogleFonts.dmSans(
                        color: CubieColors.textMuted, fontSize: 13),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel',
                    style: GoogleFonts.dmSans(color: CubieColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: matches ? CubieColors.error : CubieColors.textMuted),
                onPressed: matches
                    ? () {
                        Navigator.pop(ctx, true);
                      }
                    : null,
                child: Text('Format',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    ).then((confirmed) async {
      if (confirmed != true || !mounted) return;
      setState(() => _busyDevice = dev.path);
      try {
        final started = await ref.read(apiServiceProvider).startFormatJob(
              dev.path,
              labelCtrl.text.trim().isEmpty ? 'CubieNAS' : labelCtrl.text.trim(),
              dev.path,
            );

        final jobId = started['jobId'] as String?;
        if (jobId == null || jobId.isEmpty) {
          throw Exception('Format job start returned no jobId');
        }

        _startFormatPolling(jobId);
        _showSnack('Format started for ${dev.name}. Tracking progress…');
      } catch (e) {
        _showSnack('Format failed: ${friendlyError(e)}', isError: true);
      } finally {
        if (mounted) setState(() => _busyDevice = null);
      }
    });
  }

  void _startFormatPolling(String jobId) {
    _jobPollTimer?.cancel();
    _elapsedTimer?.cancel();

    setState(() {
      _formatJobId = jobId;
      _formatStartedAt = DateTime.now();
      _formatStatus = 'running';
    });

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _formatInProgress) {
        setState(() {});
      }
    });

    _jobPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final id = _formatJobId;
      if (id == null) return;
      try {
        final status = await ref.read(apiServiceProvider).getJobStatus(id);
        if (!mounted) return;

        setState(() {
          _formatStatus = status.status;
          _formatStartedAt ??= status.startedAt;
        });

        if (status.status == 'completed') {
          _jobPollTimer?.cancel();
          _elapsedTimer?.cancel();
          setState(() {
            _formatJobId = null;
            _formatStatus = '';
          });
          _showSnack('Format completed successfully');
          await _loadDevices();
          return;
        }

        if (status.status == 'failed') {
          _jobPollTimer?.cancel();
          _elapsedTimer?.cancel();
          setState(() {
            _formatJobId = null;
            _formatStatus = '';
          });
          _showSnack('Format failed: ${status.error ?? 'Unknown error'}',
              isError: true);
        }
      } catch (e) {
        if (!mounted) return;
        _showSnack('Job polling error: ${friendlyError(e)}', isError: true);
      }
    });
  }

  Widget _buildFormatProgressCard() {
    final started = _formatStartedAt;
    final elapsed =
        started == null ? Duration.zero : DateTime.now().difference(started);
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');

    return CubieCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Formatting in progress',
            style: GoogleFonts.sora(
              color: CubieColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Status: ${_formatStatus.isEmpty ? 'running' : _formatStatus} • Elapsed: $mm:$ss',
            style: GoogleFonts.dmSans(
              color: CubieColors.textSecondary,
              fontSize: 12,
            ),
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
        backgroundColor: CubieColors.surface,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: CubieColors.primary, size: 24),
            const SizedBox(width: 8),
            Text('Files In Use', style: GoogleFonts.sora(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${blockers.length} process(es) have open files on the NAS:',
              style: GoogleFonts.dmSans(
                  color: CubieColors.textSecondary, fontSize: 13),
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
                            color: CubieColors.textMuted, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${b['command']} (PID ${b['pid']})',
                            style: GoogleFonts.dmSans(
                                color: CubieColors.textPrimary, fontSize: 13),
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
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: CubieColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: CubieColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Force Unmount',
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
      backgroundColor: isError ? CubieColors.error : null,
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEVICE CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _DeviceCard extends StatelessWidget {
  final StorageDevice device;
  final bool isSystem;
  final bool busy;
  final VoidCallback? onMount;
  final VoidCallback? onUnmount;
  final VoidCallback? onFormat;
  final VoidCallback? onEject;

  const _DeviceCard({
    required this.device,
    this.isSystem = false,
    this.busy = false,
    this.onMount,
    this.onUnmount,
    this.onFormat,
    this.onEject,
  });

  @override
  Widget build(BuildContext context) {
    return CubieCard(
      glowing: device.isNasActive,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ─────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.12),
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
                      device.label ?? device.model ?? device.name,
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.typeLabel}  •  ${device.sizeDisplay}',
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _statusBadge(),
            ],
          ),

          // ── Detail row ─────────────────────────────────────────────────
          const SizedBox(height: 12),
          Row(
            children: [
              _infoChip(Icons.code_rounded, device.path),
              const SizedBox(width: 8),
              if (device.fstype != null)
                _infoChip(Icons.disc_full_rounded, device.fstype!),
              if (device.fstype == null)
                _infoChip(Icons.disc_full_rounded, 'Unformatted'),
            ],
          ),

          // ── Action buttons (external only) ─────────────────────────────
          if (!isSystem) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: CubieColors.cardBorder),
            const SizedBox(height: 12),
            if (busy)
              const Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: CubieColors.primary),
                ),
              )
            else
              _actionRow(),
          ],
        ],
      ),
    );
  }

  Widget _actionRow() {
    // Case 1: NAS active → unmount / eject
    if (device.isNasActive) {
      return Row(
        children: [
          _actionBtn(Icons.eject_rounded, 'Unmount', CubieColors.primary,
              onUnmount),
          const SizedBox(width: 8),
          if (device.transport == 'usb')
            _actionBtn(Icons.usb_off_rounded, 'Safe Remove', CubieColors.error,
                onEject),
        ],
      );
    }

    // Case 2: Has filesystem, not mounted → mount
    if (device.fstype != null && !device.mounted) {
      return Row(
        children: [
          _actionBtn(
              Icons.play_arrow_rounded, 'Mount', CubieColors.success, onMount),
          const SizedBox(width: 8),
          _actionBtn(Icons.format_paint_rounded, 'Format', CubieColors.error,
              onFormat),
          if (device.transport == 'usb') ...[
            const SizedBox(width: 8),
            _actionBtn(
                Icons.eject_rounded, 'Eject', CubieColors.textSecondary, onEject),
          ],
        ],
      );
    }

    // Case 3: No filesystem → format
    return Row(
      children: [
        _actionBtn(
            Icons.format_paint_rounded, 'Format', CubieColors.primary, onFormat),
        if (device.transport == 'usb') ...[
          const SizedBox(width: 8),
          _actionBtn(
              Icons.eject_rounded, 'Eject', CubieColors.textSecondary, onEject),
        ],
      ],
    );
  }

  Widget _actionBtn(
      IconData icon, String label, Color color, VoidCallback? onTap) {
    return Expanded(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.3)),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _statusBadge() {
    String text;
    Color color;

    if (device.isNasActive) {
      text = 'Active';
      color = CubieColors.success;
    } else if (device.mounted) {
      text = 'Mounted';
      color = CubieColors.secondary;
    } else if (device.isOsDisk) {
      text = 'System';
      color = CubieColors.textSecondary;
    } else if (device.fstype == null) {
      text = 'Unformatted';
      color = CubieColors.primary;
    } else {
      text = 'Ready';
      color = CubieColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: GoogleFonts.dmSans(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: CubieColors.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: CubieColors.textMuted, size: 12),
          const SizedBox(width: 4),
          Text(text,
              style: GoogleFonts.dmSans(
                  color: CubieColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Color get _accentColor => switch (device.transport) {
        'usb' => CubieColors.primary,
        'nvme' => CubieColors.secondary,
        'sd' => CubieColors.textSecondary,
        _ => CubieColors.textSecondary,
      };
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAFE REMOVE BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

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
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: CubieColors.textMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: CubieColors.error.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.eject_rounded,
                color: CubieColors.error, size: 32),
          ),
          const SizedBox(height: 16),

          Text('Safe Remove',
              style: GoogleFonts.sora(
                  color: CubieColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          Text(
            'This will stop NAS services, unmount '
            '${device.label ?? device.name}, and power off the USB port.\n\n'
            'Make sure all transfers are complete.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
                color: CubieColors.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),

          // Steps preview
          _step(Icons.stop_circle_outlined, 'Stop file sharing services'),
          _step(Icons.sync_rounded, 'Flush writes & unmount'),
          _step(Icons.usb_off_rounded, 'Power off USB port'),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel',
                      style: GoogleFonts.dmSans(
                          color: CubieColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: CubieColors.error),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Eject Now',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
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
          Icon(icon, color: CubieColors.textMuted, size: 18),
          const SizedBox(width: 10),
          Text(text,
              style: GoogleFonts.dmSans(
                  color: CubieColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}
