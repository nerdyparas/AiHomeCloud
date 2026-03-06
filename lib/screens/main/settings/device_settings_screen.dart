import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';
import '../../../core/error_utils.dart';
import '../../../providers.dart';
import '../../../widgets/cubie_card.dart';

class DeviceSettingsScreen extends ConsumerStatefulWidget {
  const DeviceSettingsScreen({super.key});

  @override
  ConsumerState<DeviceSettingsScreen> createState() =>
      _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends ConsumerState<DeviceSettingsScreen> {
  bool _checkingUpdate = false;
  Map<String, dynamic>? _updateInfo;

  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(deviceInfoProvider);

    return Scaffold(
      backgroundColor: CubieColors.background,
      appBar: AppBar(
        backgroundColor: CubieColors.background,
        title: Text('Device',
            style: GoogleFonts.sora(
                color: CubieColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: CubieColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          // ── Device info ──────────────────────────────────────────────────
          const SizedBox(height: 12),
          _sectionLabel('Information'),
          const SizedBox(height: 12),
          deviceAsync.when(
            data: (d) => CubieCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _row('Name', d.name,
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_rounded,
                            size: 18, color: CubieColors.textMuted),
                        onPressed: () => _editName(d.name),
                      )),
                  _divider(),
                  _row('Serial', d.serial),
                  _divider(),
                  _row('IP Address', d.ip),
                  _divider(),
                  _row('Firmware', d.firmwareVersion),
                ],
              ),
            ).animate().fadeIn(duration: 300.ms),
            loading: () => const CubieCard(
                child: SizedBox(
                    height: 160,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: CubieColors.primary)))),
            error: (e, _) => CubieCard(child: Text(friendlyError(e))),
          ),

          // ── Firmware update ─────────────────────────────────────────────
          const SizedBox(height: 24),
          _sectionLabel('Firmware Update'),
          const SizedBox(height: 12),
          CubieCard(
            child:
                _updateInfo != null ? _updateAvailable() : _checkButton(),
          ).animate().fadeIn(delay: 100.ms),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(text,
      style: GoogleFonts.sora(
          color: CubieColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5));

  Widget _row(String label, String value, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(label,
                style: GoogleFonts.dmSans(
                    color: CubieColors.textSecondary, fontSize: 13)),
            const Spacer(),
            Text(value,
                style: GoogleFonts.dmSans(
                    color: CubieColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _divider() => const Divider(
      height: 1, indent: 16, endIndent: 16, color: CubieColors.cardBorder);

  // ── OTA ────────────────────────────────────────────────────────────────────

  Widget _checkButton() => SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _checkingUpdate
              ? null
              : () async {
                  setState(() => _checkingUpdate = true);
                  final info =
                      await ref.read(apiServiceProvider).checkFirmwareUpdate();
                  setState(() {
                    _updateInfo = info;
                    _checkingUpdate = false;
                  });
                },
          icon: _checkingUpdate
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: CubieColors.primary))
              : const Icon(Icons.system_update_rounded, size: 18),
          label: Text(
            _checkingUpdate ? 'Checking…' : 'Check for Updates',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
          ),
        ),
      );

  Widget _updateAvailable() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: CubieColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('v${_updateInfo!['latest_version']} available',
                    style: GoogleFonts.dmSans(
                        color: CubieColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              Text('${_updateInfo!['size_mb']} MB',
                  style: GoogleFonts.dmSans(
                      color: CubieColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Text(_updateInfo!['changelog'] as String,
              style: GoogleFonts.dmSans(
                  color: CubieColors.textSecondary,
                  fontSize: 13,
                  height: 1.5)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await ref.read(apiServiceProvider).triggerOtaUpdate();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Update started. Device will reboot automatically.')));
                }
              },
              child: Text('Install Update',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      );

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _editName(String current) {
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Device Name', style: GoogleFonts.sora()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.dmSans(color: CubieColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Enter device name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: CubieColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(apiServiceProvider).updateDeviceName(ctrl.text);
              ref.invalidate(deviceInfoProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Save',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
