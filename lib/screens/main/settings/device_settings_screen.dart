import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';
import '../../../core/error_utils.dart';
import '../../../providers.dart';
import '../../../widgets/app_card.dart';

class DeviceSettingsScreen extends ConsumerStatefulWidget {
  const DeviceSettingsScreen({super.key});

  @override
  ConsumerState<DeviceSettingsScreen> createState() =>
      _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends ConsumerState<DeviceSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(deviceInfoProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Device',
            style: GoogleFonts.sora(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
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
            data: (d) => AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _row('Name', d.name,
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_rounded,
                            size: 18, color: AppColors.textMuted),
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
            loading: () => const AppCard(
                child: SizedBox(
                    height: 160,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)))),
            error: (e, _) => AppCard(child: Text(friendlyError(e))),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(text,
      style: GoogleFonts.sora(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5));

  Widget _row(String label, String value, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(label,
                style: GoogleFonts.dmSans(
                    color: AppColors.textSecondary, fontSize: 13)),
            const Spacer(),
            Text(value,
                style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _divider() => const Divider(
      height: 1, indent: 16, endIndent: 16, color: AppColors.cardBorder);

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
          style: GoogleFonts.dmSans(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Enter device name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
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
